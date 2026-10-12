#!/usr/bin/env bash
# Print Claude / Codex plan usage as one JSON document for the bar.
# Reads the tokens the official CLIs store. Only an expired Claude login is ever renewed
# (and written back), and only while Claude Code isn't running; see renew_claude.
# Usage: ai-usage.sh [--force]   (--force skips the response cache)

# provider|label|short label (bar)|config dir. Accounts whose credentials don't exist are
# reported as "missing" and hidden by the bar.
ACCOUNTS=(
    "claude|Claude|C1|$HOME/.claude"
    "claude|Claude 2|C2|$HOME/.claude-2"
    "codex|Codex|CX|$HOME/.codex"
)

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ai-usage"
MAX_AGE=60 # seconds a response is reused for

force=0
[[ "$1" == "--force" ]] && force=1
now=$(date +%s)
mkdir -p "$CACHE_DIR"

# Decode a JWT's payload (base64url, unpadded)
jwt_payload() {
    local p
    p=$(cut -d. -f2 <<<"$1" | tr '_-' '/+')
    while (( ${#p} % 4 )); do p+="="; done
    base64 -d <<<"$p" 2>/dev/null
}

# GET $1 with headers read from stdin, keeping tokens out of argv (visible in ps).
# Prints "<body>\n<http code>"
http_get() {
    curl -sS -m 10 -w '\n%{http_code}' -H @- "$1" 2>&1
}

# Claude access tokens only live ~8h, and the refresh token is single-use (each refresh
# rotates it). Renew an expired login ourselves only while no Claude Code is running, so
# we never race it for the refresh token; a running Claude Code renews its own.
# Endpoint and client id are Claude Code's own (undocumented). At most one attempt per
# RENEW_GAP per account. On failure, sets renew_msg for the bar.
RENEW_GAP=600
CLAUDE_TOKEN_URL=https://platform.claude.com/v1/oauth/token
CLAUDE_CLIENT_ID=9d1c250a-e61b-44d9-88ed-5944d1962f5e
# The token endpoint answers curl's default User-Agent with 429
CLAUDE_UA="claude-cli/2.1.0 (external, cli)"
renew_msg=""

claude_code_running() {
    # Native install, or npm's node .../claude-code/cli.js. The Chrome extension's native
    # host stays resident but never refreshes the login.
    pgrep -af '(^|/)claude( |$)|@anthropic-ai/claude-code' | grep -qv -- --chrome-native-host
}

renew_claude() {
    local dir=$1 id=$2 creds lock
    creds=$(readlink -f "$dir/.credentials.json") # write through symlinks
    lock="$CACHE_DIR/renew-$id"
    # Serialize runs (bar poll vs --force), so a refresh token is never sent twice
    exec {lockfd}>>"$lock"
    flock -n "$lockfd" || { exec {lockfd}>&-; renew_msg="Login expired; renewing…"; return 1; }
    _renew_claude_locked "$creds" "$lock"
    local rc=$?
    exec {lockfd}>&-
    return $rc
}

_renew_claude_locked() {
    local creds=$1 lock=$2 refresh resp code body tmp
    if claude_code_running; then
        renew_msg="Login expired; Claude Code is open and renews it on its next request"
        return 1
    fi
    # Someone renewed while we waited
    (( now < $(jq -r '(.claudeAiOauth.expiresAt // 0) / 1000 | floor' "$creds") )) && return 0
    if [[ -n "$(cat "$lock")" ]] && (( now - $(stat -c %Y "$lock") < RENEW_GAP )); then
        renew_msg=$(cat "$lock")
        return 1
    fi

    refresh=$(jq -r '.claudeAiOauth.refreshToken // empty' "$creds")
    [[ -z "$refresh" ]] && { renew_msg="Login expired, run claude /login"; return 1; }
    # Tokens go through the environment and stdin, never argv (visible in ps)
    resp=$(RT=$refresh CID=$CLAUDE_CLIENT_ID jq -c '
            {grant_type: "refresh_token", refresh_token: env.RT, client_id: env.CID}
            + (.claudeAiOauth.scopes // [] | if length > 0 then {scope: join(" ")} else {} end)
        ' "$creds" \
        | curl -sS -m 15 -w '\n%{http_code}' -A "$CLAUDE_UA" -H 'Content-Type: application/json' \
            --data-binary @- "$CLAUDE_TOKEN_URL" 2>&1)
    code=${resp##*$'\n'}
    body=${resp%$'\n'*}
    if [[ "$code" != 200 ]] || ! jq -e '.access_token | strings' >/dev/null <<<"$body"; then
        case $code in
            400 | 401) renew_msg="Login revoked, run claude /login" ;;
            *) renew_msg="Login expired; renewal failed (HTTP $code)" ;;
        esac
        printf '%s' "$renew_msg" >"$lock" # rate-limits the next attempt
        return 1
    fi
    : >"$lock"

    # From here the old refresh token is spent: the new pair must reach the file.
    # Merge it into whatever the file holds now (newest copy), then rename over it.
    tmp=$(mktemp "${creds%/*}/.credentials.json.XXXXXX") || tmp=""
    if [[ -n "$tmp" ]] && R=$body NOWMS=$(date +%s%3N) jq '
            (env.R | fromjson) as $r | (env.NOWMS | tonumber) as $now
            | .claudeAiOauth.accessToken = $r.access_token
            | .claudeAiOauth.refreshToken = ($r.refresh_token // .claudeAiOauth.refreshToken)
            | .claudeAiOauth.expiresAt = ($now + ($r.expires_in // 3600) * 1000)
            | if $r.refresh_token_expires_in then
                .claudeAiOauth.refreshTokenExpiresAt = ($now + $r.refresh_token_expires_in * 1000)
              else . end
            | if $r.scope then .claudeAiOauth.scopes = ($r.scope | split(" ")) else . end
        ' "$creds" >"$tmp" && mv -f "$tmp" "$creds"; then
        return 0
    fi
    [[ -n "$tmp" ]] && rm -f "$tmp"
    # Last resort: keep the new tokens somewhere private rather than lose them
    (umask 077; printf '%s\n' "$body" >"${creds%/*}/.credentials.renewed.json")
    renew_msg="Renewed login could not be saved; see ${creds%/*}/.credentials.renewed.json"
    return 1
}

# Echo the normalized {plan, windows} for one account, or fail with a message on stdout
fetch_claude() {
    local dir=$1 id=$2 creds="$1/.credentials.json" token exp plan resp code
    token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds")
    exp=$(jq -r '(.claudeAiOauth.expiresAt // 0) / 1000 | floor' "$creds")
    plan=$(jq -r '.claudeAiOauth.subscriptionType // ""' "$creds")
    [[ -z "$token" ]] && { echo "No Claude login in $dir"; return 1; }
    if (( now >= exp )) && renew_claude "$dir" "$id"; then
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds")
        exp=$(jq -r '(.claudeAiOauth.expiresAt // 0) / 1000 | floor' "$creds")
    fi
    (( now >= exp )) && { echo "${renew_msg:-Login expired, open Claude Code to renew}"; return 2; }

    resp=$(printf '%s\n' "Authorization: Bearer $token" "anthropic-beta: oauth-2025-04-20" \
        | http_get https://api.anthropic.com/api/oauth/usage)
    code=${resp##*$'\n'}
    [[ "$code" != 200 ]] && { echo "HTTP $code"; return 1; }

    jq -c --arg plan "$plan" '
        def ts: if . == null then null
            else .[0:19] + "Z" | fromdate end; # always UTC: "2026-09-24T22:50:00.42+00:00"
        def win($key; $label; $secs):
            select(. != null and .utilization != null)
            | {key: $key, label: $label, used: .utilization, resetsAt: (.resets_at | ts), windowSeconds: $secs};
        {
            plan: $plan,
            windows: [
                (.five_hour | win("5h"; "Session"; 18000)),
                (.seven_day | win("7d"; "Weekly"; 604800)),
                (.seven_day_opus | win("7d-opus"; "Weekly · Opus"; 604800)),
                (.seven_day_sonnet | win("7d-sonnet"; "Weekly · Sonnet"; 604800))
            ]
        }' <<<"${resp%$'\n'*}"
}

fetch_codex() {
    local dir=$1 auth="$1/auth.json" token account exp resp code
    token=$(jq -r '.tokens.access_token // empty' "$auth")
    account=$(jq -r '.tokens.account_id // empty' "$auth")
    [[ -z "$token" ]] && { echo "No ChatGPT login in $dir"; return 1; }
    exp=$(jwt_payload "$token" | jq -r '.exp // 0')
    (( now >= exp )) && { echo "Login expired, open Codex to renew"; return 2; }

    resp=$(printf '%s\n' "Authorization: Bearer $token" "ChatGPT-Account-Id: $account" "User-Agent: codex-cli" \
        | http_get https://chatgpt.com/backend-api/wham/usage)
    code=${resp##*$'\n'}
    [[ "$code" != 200 ]] && { echo "HTTP $code"; return 1; }

    jq -c '
        def win($key; $label):
            select(. != null)
            | {key: $key, label: $label, used: .used_percent, resetsAt: .reset_at, windowSeconds: .limit_window_seconds};
        {
            plan: (.plan_type // ""),
            windows: [
                (.rate_limit.primary_window | win("5h"; "Session")),
                (.rate_limit.secondary_window | win("7d"; "Weekly"))
            ]
        }' <<<"${resp%$'\n'*}"
}

account_json() {
    local provider=$1 label=$2 short=$3 dir=$4 id cache credfile out rc
    id=$(tr -c 'a-zA-Z0-9' '-' <<<"$label" | tr 'A-Z' 'a-z' | sed 's/-*$//')
    cache="$CACHE_DIR/$id.json"
    case $provider in
        claude) credfile="$dir/.credentials.json" ;;
        codex) credfile="$dir/auth.json" ;;
    esac
    local base
    base=$(jq -nc --arg id "$id" --arg label "$label" --arg provider "$provider" --arg short "$short" \
        '{id: $id, label: $label, short: $short, provider: $provider}')

    if [[ ! -f "$credfile" ]]; then
        jq -c '. + {status: "missing"}' <<<"$base"
        return
    fi

    # Fresh enough cached response
    if (( !force )) && [[ -f "$cache" ]] \
        && (( now - $(jq -r '.fetchedAt // 0' "$cache") < MAX_AGE )); then
        jq -c --argjson b "$base" '$b + . + {status: "ok"}' "$cache"
        return
    fi

    out=$(fetch_"$provider" "$dir" "$id")
    rc=$?
    if (( rc == 0 )); then
        jq -c --argjson t "$now" '. + {fetchedAt: $t}' <<<"$out" >"$cache"
        jq -c --argjson b "$base" '$b + . + {status: "ok"}' "$cache"
        return
    fi

    # Failed: keep showing the last good numbers, marked stale
    local cached='{}'
    [[ -f "$cache" ]] && cached=$(cat "$cache")
    jq -c --argjson b "$base" --arg err "$out" --arg st "$( ((rc == 2)) && echo stale || echo error)" \
        '$b + . + {status: $st, error: $err}' <<<"$cached"
}

for entry in "${ACCOUNTS[@]}"; do
    IFS='|' read -r provider label short dir <<<"$entry"
    account_json "$provider" "$label" "$short" "$dir"
done | jq -sc --argjson t "$now" '{updatedAt: $t, accounts: .}'
