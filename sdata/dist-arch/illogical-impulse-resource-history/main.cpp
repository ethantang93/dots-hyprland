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
//
// C++ port of the original Rust implementation; the on-disk format is
// byte-identical, so existing history files carry over.

#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {

constexpr char MAGIC[4] = {'R', 'H', 'B', '1'};
constexpr uint32_t VERSION = 1;
constexpr uint64_t HEADER_SIZE = 16;
constexpr uint64_t REC_SIZE = 8;

struct Tier {
    uint64_t interval; // bucket size in seconds
    uint64_t slots;
};

// Tier 0 is the raw source of truth (10s x 7 days); the rest are display
// rollups sized so each window renders as ~120 points (window / 120).
constexpr Tier TIERS[] = {
    {10, 60480},
    {30, 120},  // 1h
    {180, 120}, // 6h
    {360, 120}, // 12h
    {720, 120}, // 1d
};
constexpr size_t TIER_COUNT = sizeof(TIERS) / sizeof(TIERS[0]);

uint64_t tier_offset(size_t idx) {
    uint64_t off = HEADER_SIZE;
    for (size_t i = 0; i < idx; i++) off += TIERS[i].slots * REC_SIZE;
    return off;
}

uint64_t total_file_size() { return tier_offset(TIER_COUNT); }

struct Rec {
    uint32_t bucket = 0; // unix_ts / tier.interval; 0 = never written
    uint8_t cpu_avg = 0;
    uint8_t cpu_max = 0;
    uint8_t mem_avg = 0;
    uint8_t mem_max = 0;

    void encode(uint8_t out[REC_SIZE]) const {
        out[0] = bucket & 0xff;
        out[1] = (bucket >> 8) & 0xff;
        out[2] = (bucket >> 16) & 0xff;
        out[3] = (bucket >> 24) & 0xff;
        out[4] = cpu_avg;
        out[5] = cpu_max;
        out[6] = mem_avg;
        out[7] = mem_max;
    }

    static Rec decode(const uint8_t *b) {
        Rec r;
        r.bucket = uint32_t(b[0]) | uint32_t(b[1]) << 8 | uint32_t(b[2]) << 16 |
                   uint32_t(b[3]) << 24;
        r.cpu_avg = b[4];
        r.cpu_max = b[5];
        r.mem_avg = b[6];
        r.mem_max = b[7];
        return r;
    }
};

// Running aggregate for a tier's in-progress bucket.
struct Agg {
    uint64_t bucket = 0;
    uint64_t cpu_sum = 0;
    uint8_t cpu_max = 0;
    uint64_t mem_sum = 0;
    uint8_t mem_max = 0;
    uint64_t count = 0;

    explicit Agg(uint64_t b = 0) : bucket(b) {}

    void add(uint8_t cpu, uint8_t mem) {
        cpu_sum += cpu;
        mem_sum += mem;
        cpu_max = std::max(cpu_max, cpu);
        mem_max = std::max(mem_max, mem);
        count++;
    }

    Rec rec() const {
        uint64_t n = std::max<uint64_t>(count, 1);
        Rec r;
        r.bucket = uint32_t(bucket);
        r.cpu_avg = uint8_t((cpu_sum + n / 2) / n);
        r.cpu_max = cpu_max;
        r.mem_avg = uint8_t((mem_sum + n / 2) / n);
        r.mem_max = mem_max;
        return r;
    }
};

uint64_t unix_now() { return uint64_t(time(nullptr)); }

std::string data_path() {
    const char *state = getenv("XDG_STATE_HOME");
    std::string base;
    if (state && state[0] == '/') {
        base = state;
    } else {
        const char *home = getenv("HOME");
        if (!home) {
            fprintf(stderr, "resource-history: HOME not set\n");
            exit(1);
        }
        base = std::string(home) + "/.local/state";
    }
    return base + "/resource-history/history.bin";
}

void mkdir_p(const std::string &dir) {
    std::string partial;
    std::istringstream ss(dir);
    std::string part;
    while (std::getline(ss, part, '/')) {
        if (part.empty()) continue;
        partial += "/" + part;
        mkdir(partial.c_str(), 0755); // EEXIST is fine
    }
}

// Returns fd, or -1 on failure (read-only mode with missing/invalid file).
int open_data_file(bool writable) {
    std::string path = data_path();
    if (writable) mkdir_p(path.substr(0, path.rfind('/')));

    int fd = open(path.c_str(), writable ? (O_RDWR | O_CREAT) : O_RDONLY, 0644);
    if (fd < 0) return -1;

    struct stat st{};
    uint8_t header[HEADER_SIZE] = {};
    bool valid = fstat(fd, &st) == 0 && uint64_t(st.st_size) == total_file_size() &&
                 pread(fd, header, HEADER_SIZE, 0) == ssize_t(HEADER_SIZE) &&
                 memcmp(header, MAGIC, 4) == 0 &&
                 (uint32_t(header[4]) | uint32_t(header[5]) << 8 |
                  uint32_t(header[6]) << 16 | uint32_t(header[7]) << 24) == VERSION;

    if (!valid) {
        if (!writable) {
            close(fd);
            return -1;
        }
        // (Re)initialize: header + zero-filled rings. bucket=0 slots read as gaps.
        if (ftruncate(fd, 0) != 0) { close(fd); return -1; }
        uint8_t h[HEADER_SIZE] = {};
        memcpy(h, MAGIC, 4);
        h[4] = VERSION & 0xff;
        h[5] = (VERSION >> 8) & 0xff;
        h[6] = (VERSION >> 16) & 0xff;
        h[7] = (VERSION >> 24) & 0xff;
        if (pwrite(fd, h, HEADER_SIZE, 0) != ssize_t(HEADER_SIZE) ||
            ftruncate(fd, off_t(total_file_size())) != 0) {
            close(fd);
            return -1;
        }
    }
    return fd;
}

void write_rec(int fd, size_t tier_idx, const Rec &rec) {
    const Tier &tier = TIERS[tier_idx];
    uint64_t slot = rec.bucket % tier.slots;
    uint64_t offset = tier_offset(tier_idx) + slot * REC_SIZE;
    uint8_t buf[REC_SIZE];
    rec.encode(buf);
    if (pwrite(fd, buf, REC_SIZE, off_t(offset)) != ssize_t(REC_SIZE))
        fprintf(stderr, "resource-history: write failed: %s\n", strerror(errno));
}

std::vector<Rec> read_tier(int fd, size_t tier_idx) {
    const Tier &tier = TIERS[tier_idx];
    std::vector<uint8_t> buf(tier.slots * REC_SIZE, 0);
    // On read failure the zeroed buffer decodes as gaps.
    if (fd >= 0)
        pread(fd, buf.data(), buf.size(), off_t(tier_offset(tier_idx)));
    std::vector<Rec> recs;
    recs.reserve(tier.slots);
    for (uint64_t i = 0; i < tier.slots; i++)
        recs.push_back(Rec::decode(buf.data() + i * REC_SIZE));
    return recs;
}

// ---------- /proc sampling ----------

bool read_cpu_jiffies(uint64_t &total, uint64_t &idle) {
    std::ifstream stat("/proc/stat");
    std::string cpu;
    if (!(stat >> cpu) || cpu != "cpu") return false;
    std::vector<uint64_t> f;
    uint64_t v;
    while (f.size() < 10 && stat >> v) f.push_back(v);
    if (f.size() < 5) return false;
    total = 0;
    for (size_t i = 0; i < std::min<size_t>(f.size(), 8); i++) total += f[i];
    idle = f[3] + f[4]; // idle + iowait
    return true;
}

bool read_mem_percent(uint8_t &out) {
    std::ifstream meminfo("/proc/meminfo");
    uint64_t total = 0, avail = 0;
    std::string line;
    while (std::getline(meminfo, line)) {
        if (line.rfind("MemTotal:", 0) == 0)
            total = strtoull(line.c_str() + 9, nullptr, 10);
        else if (line.rfind("MemAvailable:", 0) == 0)
            avail = strtoull(line.c_str() + 13, nullptr, 10);
        if (total && avail) break;
    }
    if (total == 0) return false;
    avail = std::min(avail, total);
    out = uint8_t(((total - avail) * 100 + total / 2) / total);
    return true;
}

// ---------- record ----------

// Tiers are derived caches of the raw ring: rebuild every bucket that is
// still inside each tier's window, so daemon downtime never leaves a tier
// slot stale or a restarted bucket under-averaged.
std::vector<Agg> rebuild_aggs(int fd, uint64_t now) {
    struct Sample { uint64_t ts; uint8_t cpu, mem; };
    std::vector<Sample> raw;
    for (const Rec &r : read_tier(fd, 0)) {
        uint64_t ts = uint64_t(r.bucket) * TIERS[0].interval;
        if (r.bucket != 0 && ts <= now && ts + 86400 > now)
            raw.push_back({ts, r.cpu_avg, r.mem_avg});
    }

    std::vector<Agg> aggs;
    for (size_t tier_idx = 1; tier_idx < TIER_COUNT; tier_idx++) {
        const Tier &tier = TIERS[tier_idx];
        uint64_t current_bucket = now / tier.interval;
        std::unordered_map<uint64_t, Agg> buckets;
        for (const Sample &s : raw) {
            uint64_t bucket = s.ts / tier.interval;
            if (bucket + tier.slots > current_bucket && bucket <= current_bucket) {
                auto it = buckets.try_emplace(bucket, Agg(bucket)).first;
                it->second.add(s.cpu, s.mem);
            }
        }
        for (const auto &[bucket, agg] : buckets) write_rec(fd, tier_idx, agg.rec());
        auto it = buckets.find(current_bucket);
        aggs.push_back(it != buckets.end() ? it->second : Agg(current_bucket));
    }
    return aggs;
}

void sleep_to_next_sample() {
    struct timespec ts{};
    clock_gettime(CLOCK_REALTIME, &ts);
    uint64_t now_ms = uint64_t(ts.tv_sec) * 1000 + uint64_t(ts.tv_nsec) / 1000000;
    uint64_t step = TIERS[0].interval * 1000;
    // Wake 100ms past the boundary so the sample lands firmly in the new slot.
    uint64_t next = (now_ms / step + 1) * step + 100;
    uint64_t delay = next - now_ms;
    struct timespec req{time_t(delay / 1000), long(delay % 1000 * 1000000)};
    nanosleep(&req, nullptr);
}

int cmd_record() {
    int fd = open_data_file(true);
    if (fd < 0) {
        fprintf(stderr, "resource-history: cannot open history file: %s\n",
                strerror(errno));
        return 1;
    }
    std::vector<Agg> aggs = rebuild_aggs(fd, unix_now());

    uint64_t prev_total = 0, prev_idle = 0;
    bool have_prev = read_cpu_jiffies(prev_total, prev_idle);

    for (;;) {
        sleep_to_next_sample();
        uint64_t now = unix_now();

        uint64_t cur_total = 0, cur_idle = 0;
        bool have_cur = read_cpu_jiffies(cur_total, cur_idle);
        if (!have_prev || !have_cur || cur_total <= prev_total) {
            have_prev = have_cur;
            prev_total = cur_total;
            prev_idle = cur_idle;
            continue;
        }
        uint64_t total = cur_total - prev_total;
        uint64_t idle = std::min(cur_idle - prev_idle, total);
        uint8_t cpu = uint8_t(((total - idle) * 100 + total / 2) / total);
        have_prev = true;
        prev_total = cur_total;
        prev_idle = cur_idle;

        uint8_t mem = 0;
        if (!read_mem_percent(mem)) continue;

        Rec raw;
        raw.bucket = uint32_t(now / TIERS[0].interval);
        raw.cpu_avg = raw.cpu_max = cpu;
        raw.mem_avg = raw.mem_max = mem;
        write_rec(fd, 0, raw);

        for (size_t i = 0; i < aggs.size(); i++) {
            size_t tier_idx = i + 1;
            uint64_t bucket = now / TIERS[tier_idx].interval;
            if (aggs[i].bucket != bucket) aggs[i] = Agg(bucket);
            aggs[i].add(cpu, mem);
            // Write-through so the newest chart point is live mid-bucket.
            write_rec(fd, tier_idx, aggs[i].rec());
        }
    }
}

// ---------- query ----------

template <typename ValueFn>
std::string json_series(const std::vector<Rec> &recs, const Tier &tier,
                        uint64_t current_bucket, ValueFn value) {
    std::string out = "[";
    char num[16];
    for (uint64_t i = 0; i < tier.slots; i++) {
        uint64_t bucket = current_bucket + 1 + i - tier.slots;
        const Rec &rec = recs[bucket % tier.slots];
        if (i > 0) out += ",";
        if (uint64_t(rec.bucket) == bucket && bucket != 0) {
            snprintf(num, sizeof(num), "%.2f", double(value(rec)) / 100.0);
            out += num;
        } else {
            out += "-1";
        }
    }
    out += "]";
    return out;
}

int cmd_query(uint64_t window) {
    // Pick the display tier whose full span best matches the requested window.
    size_t tier_idx = 1;
    uint64_t best_diff = UINT64_MAX;
    for (size_t i = 1; i < TIER_COUNT; i++) {
        uint64_t span = TIERS[i].interval * TIERS[i].slots;
        uint64_t diff = span > window ? span - window : window - span;
        if (diff < best_diff) {
            best_diff = diff;
            tier_idx = i;
        }
    }
    const Tier &tier = TIERS[tier_idx];
    uint64_t current_bucket = unix_now() / tier.interval;

    int fd = open_data_file(false);
    std::vector<Rec> recs = read_tier(fd, tier_idx);
    if (fd >= 0) close(fd);

    printf("{\"window\":%llu,\"bucketSeconds\":%llu,\"cpu\":%s,\"cpuMax\":%s,"
           "\"mem\":%s,\"memMax\":%s}\n",
           (unsigned long long)(tier.interval * tier.slots),
           (unsigned long long)tier.interval,
           json_series(recs, tier, current_bucket, [](const Rec &r) { return r.cpu_avg; }).c_str(),
           json_series(recs, tier, current_bucket, [](const Rec &r) { return r.cpu_max; }).c_str(),
           json_series(recs, tier, current_bucket, [](const Rec &r) { return r.mem_avg; }).c_str(),
           json_series(recs, tier, current_bucket, [](const Rec &r) { return r.mem_max; }).c_str());
    return 0;
}

} // namespace

int main(int argc, char **argv) {
    std::string cmd = argc > 1 ? argv[1] : "";
    if (cmd == "record") return cmd_record();
    if (cmd == "query") {
        uint64_t window = 3600;
        for (int i = 2; i + 1 < argc; i++)
            if (strcmp(argv[i], "--window") == 0)
                window = strtoull(argv[i + 1], nullptr, 10);
        return cmd_query(window);
    }
    fprintf(stderr, "usage: resource-history record | query --window <seconds>\n");
    return 2;
}
