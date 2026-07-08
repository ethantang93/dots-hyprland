// resource-history: samples CPU/MEM usage every 10s into a fixed-size tiered
// ring-buffer file, RRD-style. `record` runs as a daemon (systemd user unit);
// `query --window <seconds>` prints the ~120 chart points for that window as
// JSON. Consumed by the Quickshell IStat widget (services/ResourceHistory.qml).
//
// File layout: 16-byte header, then one ring buffer per tier at fixed offsets.
// Slot index is derived purely from wall clock (bucket % slots), so there is
// no write index and no mutable header state; a slot is valid only if its
// stored bucket timestamp matches the expected one, which makes suspend gaps,
// crashes, and clock jumps self-healing.

use std::collections::HashMap;
use std::env;
use std::fs::{self, OpenOptions};
use std::os::unix::fs::FileExt;
use std::path::PathBuf;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const MAGIC: [u8; 4] = *b"RHB1";
const VERSION: u32 = 1;
const HEADER_SIZE: u64 = 16;
const REC_SIZE: u64 = 8;

#[derive(Clone, Copy)]
struct Tier {
    interval: u64, // bucket size in seconds
    slots: u64,
}

// Tier 0 is the raw source of truth (10s x 7 days); the rest are display
// rollups sized so each window renders as ~120 points (window / 120).
const TIERS: [Tier; 5] = [
    Tier { interval: 10, slots: 60480 },
    Tier { interval: 30, slots: 120 },  // 1h
    Tier { interval: 180, slots: 120 }, // 6h
    Tier { interval: 360, slots: 120 }, // 12h
    Tier { interval: 720, slots: 120 }, // 1d
];

fn tier_offset(idx: usize) -> u64 {
    HEADER_SIZE + TIERS[..idx].iter().map(|t| t.slots * REC_SIZE).sum::<u64>()
}

fn total_file_size() -> u64 {
    tier_offset(TIERS.len())
}

#[derive(Clone, Copy, Default)]
struct Rec {
    bucket: u32, // unix_ts / tier.interval; 0 = never written
    cpu_avg: u8,
    cpu_max: u8,
    mem_avg: u8,
    mem_max: u8,
}

impl Rec {
    fn encode(&self) -> [u8; REC_SIZE as usize] {
        let t = self.bucket.to_le_bytes();
        [t[0], t[1], t[2], t[3], self.cpu_avg, self.cpu_max, self.mem_avg, self.mem_max]
    }

    fn decode(b: &[u8]) -> Rec {
        Rec {
            bucket: u32::from_le_bytes([b[0], b[1], b[2], b[3]]),
            cpu_avg: b[4],
            cpu_max: b[5],
            mem_avg: b[6],
            mem_max: b[7],
        }
    }
}

// Running aggregate for a tier's in-progress bucket.
struct Agg {
    bucket: u64,
    cpu_sum: u64,
    cpu_max: u8,
    mem_sum: u64,
    mem_max: u8,
    count: u64,
}

impl Agg {
    fn new(bucket: u64) -> Agg {
        Agg { bucket, cpu_sum: 0, cpu_max: 0, mem_sum: 0, mem_max: 0, count: 0 }
    }

    fn add(&mut self, cpu: u8, mem: u8) {
        self.cpu_sum += cpu as u64;
        self.mem_sum += mem as u64;
        self.cpu_max = self.cpu_max.max(cpu);
        self.mem_max = self.mem_max.max(mem);
        self.count += 1;
    }

    fn rec(&self) -> Rec {
        let avg = |sum: u64| ((sum + self.count / 2) / self.count.max(1)) as u8;
        Rec {
            bucket: self.bucket as u32,
            cpu_avg: avg(self.cpu_sum),
            cpu_max: self.cpu_max,
            mem_avg: avg(self.mem_sum),
            mem_max: self.mem_max,
        }
    }
}

fn unix_now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs()
}

fn data_path() -> PathBuf {
    let base = env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| {
            PathBuf::from(env::var_os("HOME").expect("HOME not set")).join(".local/state")
        });
    base.join("resource-history/history.bin")
}

fn open_data_file(writable: bool) -> std::io::Result<fs::File> {
    let path = data_path();
    if writable {
        fs::create_dir_all(path.parent().unwrap())?;
    }
    let file = OpenOptions::new().read(true).write(writable).create(writable).open(&path)?;

    let mut header = [0u8; HEADER_SIZE as usize];
    let valid = file.metadata()?.len() == total_file_size()
        && file.read_exact_at(&mut header, 0).is_ok()
        && header[0..4] == MAGIC
        && u32::from_le_bytes([header[4], header[5], header[6], header[7]]) == VERSION;

    if !valid {
        if !writable {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "history file missing or invalid (is the recorder running?)",
            ));
        }
        // (Re)initialize: header + zero-filled rings. bucket=0 slots read as gaps.
        file.set_len(0)?;
        let mut h = [0u8; HEADER_SIZE as usize];
        h[0..4].copy_from_slice(&MAGIC);
        h[4..8].copy_from_slice(&VERSION.to_le_bytes());
        file.write_all_at(&h, 0)?;
        file.set_len(total_file_size())?;
    }
    Ok(file)
}

fn write_rec(file: &fs::File, tier_idx: usize, rec: Rec) {
    let tier = TIERS[tier_idx];
    let slot = rec.bucket as u64 % tier.slots;
    let offset = tier_offset(tier_idx) + slot * REC_SIZE;
    if let Err(e) = file.write_all_at(&rec.encode(), offset) {
        eprintln!("resource-history: write failed: {e}");
    }
}

fn read_tier(file: &fs::File, tier_idx: usize) -> Vec<Rec> {
    let tier = TIERS[tier_idx];
    let mut buf = vec![0u8; (tier.slots * REC_SIZE) as usize];
    // On read failure fall back to zeroes, which decode as gaps.
    let _ = file.read_exact_at(&mut buf, tier_offset(tier_idx));
    buf.chunks_exact(REC_SIZE as usize).map(Rec::decode).collect()
}

// ---------- /proc sampling ----------

fn read_cpu_jiffies() -> Option<(u64, u64)> {
    let stat = fs::read_to_string("/proc/stat").ok()?;
    let line = stat.lines().next()?;
    let f: Vec<u64> = line.split_whitespace().skip(1).filter_map(|x| x.parse().ok()).collect();
    if f.len() < 5 {
        return None;
    }
    let total: u64 = f.iter().take(8).sum();
    let idle = f[3] + f[4]; // idle + iowait
    Some((total, idle))
}

fn read_mem_percent() -> Option<u8> {
    let meminfo = fs::read_to_string("/proc/meminfo").ok()?;
    let field = |name: &str| -> Option<u64> {
        meminfo
            .lines()
            .find(|l| l.starts_with(name))?
            .split_whitespace()
            .nth(1)?
            .parse()
            .ok()
    };
    let total = field("MemTotal:")?;
    let avail = field("MemAvailable:")?;
    if total == 0 {
        return None;
    }
    Some((((total - avail.min(total)) * 100 + total / 2) / total) as u8)
}

// ---------- record ----------

fn rebuild_aggs(file: &fs::File, now: u64) -> Vec<Agg> {
    // Tiers are derived caches of the raw ring: rebuild every bucket that is
    // still inside each tier's window, so daemon downtime never leaves a tier
    // slot stale or a restarted bucket under-averaged.
    let raw: Vec<(u64, u8, u8)> = read_tier(file, 0)
        .iter()
        .filter(|r| {
            let ts = r.bucket as u64 * TIERS[0].interval;
            r.bucket != 0 && ts <= now && ts + 86400 > now
        })
        .map(|r| (r.bucket as u64 * TIERS[0].interval, r.cpu_avg, r.mem_avg))
        .collect();

    let mut aggs = Vec::new();
    for (tier_idx, tier) in TIERS.iter().enumerate().skip(1) {
        let current_bucket = now / tier.interval;
        let mut buckets: HashMap<u64, Agg> = HashMap::new();
        for &(ts, cpu, mem) in &raw {
            let bucket = ts / tier.interval;
            if bucket + tier.slots > current_bucket && bucket <= current_bucket {
                buckets.entry(bucket).or_insert_with(|| Agg::new(bucket)).add(cpu, mem);
            }
        }
        for agg in buckets.values() {
            write_rec(file, tier_idx, agg.rec());
        }
        aggs.push(buckets.remove(&current_bucket).unwrap_or_else(|| Agg::new(current_bucket)));
    }
    aggs
}

fn sleep_to_next_sample() {
    let now_ms = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64;
    let step = TIERS[0].interval * 1000;
    // Wake 100ms past the boundary so the sample lands firmly in the new slot.
    let next = (now_ms / step + 1) * step + 100;
    std::thread::sleep(Duration::from_millis(next - now_ms));
}

fn cmd_record() {
    let file = open_data_file(true).expect("cannot open history file");
    let mut aggs = rebuild_aggs(&file, unix_now());
    let mut prev = read_cpu_jiffies();

    loop {
        sleep_to_next_sample();
        let now = unix_now();
        let cur = read_cpu_jiffies();

        let cpu = match (prev, cur) {
            (Some((pt, pi)), Some((ct, ci))) if ct > pt => {
                let total = ct - pt;
                let idle = (ci - pi).min(total);
                (((total - idle) * 100 + total / 2) / total) as u8
            }
            _ => {
                prev = cur;
                continue;
            }
        };
        prev = cur;

        let Some(mem) = read_mem_percent() else { continue };

        let raw_bucket = now / TIERS[0].interval;
        write_rec(&file, 0, Rec {
            bucket: raw_bucket as u32,
            cpu_avg: cpu,
            cpu_max: cpu,
            mem_avg: mem,
            mem_max: mem,
        });

        for (i, agg) in aggs.iter_mut().enumerate() {
            let tier_idx = i + 1;
            let bucket = now / TIERS[tier_idx].interval;
            if agg.bucket != bucket {
                *agg = Agg::new(bucket);
            }
            agg.add(cpu, mem);
            // Write-through so the newest chart point is live mid-bucket.
            write_rec(&file, tier_idx, agg.rec());
        }
    }
}

// ---------- query ----------

fn json_series(recs: &[Rec], tier: Tier, current_bucket: u64, value: impl Fn(&Rec) -> u8) -> String {
    let mut out = String::with_capacity(tier.slots as usize * 6);
    out.push('[');
    for i in 0..tier.slots {
        let bucket = current_bucket + 1 + i - tier.slots;
        let rec = recs[(bucket % tier.slots) as usize];
        if i > 0 {
            out.push(',');
        }
        if rec.bucket as u64 == bucket && bucket != 0 {
            out.push_str(&format!("{:.2}", value(&rec) as f64 / 100.0));
        } else {
            out.push_str("-1");
        }
    }
    out.push(']');
    out
}

fn cmd_query(window: u64) {
    // Pick the display tier whose full span best matches the requested window.
    let tier_idx = (1..TIERS.len())
        .min_by_key(|&i| (TIERS[i].interval * TIERS[i].slots).abs_diff(window))
        .unwrap();
    let tier = TIERS[tier_idx];
    let current_bucket = unix_now() / tier.interval;

    let recs = match open_data_file(false) {
        Ok(file) => read_tier(&file, tier_idx),
        Err(_) => vec![Rec::default(); tier.slots as usize],
    };

    println!(
        "{{\"window\":{},\"bucketSeconds\":{},\"cpu\":{},\"cpuMax\":{},\"mem\":{},\"memMax\":{}}}",
        tier.interval * tier.slots,
        tier.interval,
        json_series(&recs, tier, current_bucket, |r| r.cpu_avg),
        json_series(&recs, tier, current_bucket, |r| r.cpu_max),
        json_series(&recs, tier, current_bucket, |r| r.mem_avg),
        json_series(&recs, tier, current_bucket, |r| r.mem_max),
    );
}

fn main() {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("record") => cmd_record(),
        Some("query") => {
            let window = args
                .iter()
                .position(|a| a == "--window")
                .and_then(|i| args.get(i + 1))
                .and_then(|v| v.parse().ok())
                .unwrap_or(3600);
            cmd_query(window);
        }
        _ => {
            eprintln!("usage: resource-history record | query --window <seconds>");
            std::process::exit(2);
        }
    }
}
