#!/bin/bash
# ============================================================
# cpolar-monitor 鈥?cpolar tunnel change monitor with Telegram alerts
# https://github.com/buwangni2016/cpolar-monitor
# ============================================================
# Monitors cpolar tunnel URLs and sends Telegram notifications
# when tunnels are added or removed. Supports on-demand queries
# via Telegram /cpolar command.
#
# Usage:
#   cpolar-monitor start      # Start daemon (background)
#   cpolar-monitor stop       # Stop daemon
#   cpolar-monitor status     # Show status & current tunnels
#   cpolar-monitor log        # View recent logs
#   cpolar-monitor run        # Run in foreground (for debugging)
#
# Requires: bash, curl, python3
# ============================================================

set -euo pipefail

# ============ Config ============
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Load .env if exists
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
fi

CPOLAR_EMAIL="${CPOLAR_EMAIL:?Set CPOLAR_EMAIL in .env}"
CPOLAR_PASSWORD="${CPOLAR_PASSWORD:?Set CPOLAR_PASSWORD in .env}"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:?Set TELEGRAM_TOKEN in .env}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:?Set TELEGRAM_CHAT_ID in .env}"

CHECK_INTERVAL="${CHECK_INTERVAL:-600}"       # Tunnel check interval (seconds)
TELEGRAM_POLL_TIMEOUT="${TELEGRAM_POLL_TIMEOUT:-30}"  # Long polling timeout

# File paths
COOKIE_FILE="${SCRIPT_DIR}/.cpolar_cookie"
STATE_FILE="${SCRIPT_DIR}/.tunnel_state"
LOG_FILE="${SCRIPT_DIR}/cpolar-monitor.log"
LOCK_FILE="${SCRIPT_DIR}/cpolar-monitor.lock"
OFFSET_FILE="${SCRIPT_DIR}/.tg_offset"

# ============ Lock ============
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "Already running (PID: $pid)"
            exit 0
        fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

# ============ Logging ============
log() {
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

# ============ Telegram ============
send_telegram() {
    local chat_id="$1" text="$2"
    local resp
    resp=$(curl --connect-timeout 15 --max-time 15 -s -X POST \
        "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=HTML" 2>&1)

    if printf '%s' "$resp" | grep -q '"ok":true'; then
        log "Telegram sent -> $chat_id"
    else
        log "ERROR: Telegram failed: $resp"
    fi
}

# ============ cpolar Auth ============
do_login() {
    local page token resp
    page=$(curl -s -c "$COOKIE_FILE" "https://dashboard.cpolar.com/login")

    token=$(printf '%s' "$page" | grep -oP 'name="csrf_token"\s+value="\K[^"]+' || true)
    if [ -z "$token" ]; then
        log "ERROR: Failed to get CSRF token"
        return 1
    fi

    resp=$(curl -s -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST \
        "https://dashboard.cpolar.com/login" \
        -d "login=${CPOLAR_EMAIL}&password=${CPOLAR_PASSWORD}&csrf_token=${token}" \
        -L 2>/dev/null)

    if printf '%s' "$resp" | grep -q 'id="captcha-form"'; then
        log "ERROR: Login failed"
        return 1
    fi
    log "Login successful"
}

# ============ Tunnel Discovery ============
# Output: one "name|url" per line, sorted
get_tunnels() {
    local html
    html=$(curl -s -b "$COOKIE_FILE" "https://dashboard.cpolar.com/status")

    # Re-login if cookie expired
    if printf '%s' "$html" | grep -q 'id="captcha-form"'; then
        log "Cookie expired, re-login..."
        rm -f "$COOKIE_FILE"
        do_login || return 1
        html=$(curl -s -b "$COOKIE_FILE" "https://dashboard.cpolar.com/status")
    fi

    # Parse HTML table: extract tunnel name + URL pairs
    python3 -c "
import re, sys

html = sys.stdin.read()
# Strip scripts/styles
text = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL)
text = re.sub(r'<style[^>]*>.*?</style>', '', text, flags=re.DOTALL)
text = re.sub(r'<[^>]+>', '\n', text)
text = text.replace('&#43;', '+').replace('&amp;', '&')
lines = [l.strip() for l in text.split('\n') if l.strip()]

url_re = re.compile(
    r'(https?://[a-z0-9]+\.r\d+\.cpolar\.(cn|top)'
    r'|tcp://\d+\.tcp\.cpolar\.top:\d+)'
)
results = []
for i, line in enumerate(lines):
    if url_re.match(line):
        # Look backwards for tunnel name (skip region codes)
        name = ''
        for j in range(i - 1, max(i - 5, 0), -1):
            if (lines[j]
                and not url_re.match(lines[j])
                and not re.match(r'^(cn|cn_top|us|ap)$', lines[j])):
                name = lines[j]
                break
        results.append(f'{name or \"unknown\"}|{line}')

for r in sorted(set(results)):
    print(r)
" <<< "$html" || true
}

# Ensure cookie exists, then fetch tunnels
ensure_and_get() {
    if [ ! -f "$COOKIE_FILE" ]; then
        log "First run, logging in..."
        do_login || return 1
    fi
    get_tunnels
}

# ============ Format Message ============
format_tunnels() {
    local tunnels="$1"
    local msg
    msg=$(printf "馃搵 <b>褰撳墠 cpolar 闅ч亾</b>\n")

    while IFS='|' read -r name url; do
        [ -z "$url" ] && continue
        if printf '%s' "$url" | grep -q "^tcp://"; then
            msg=$(printf "%s\n馃枼 %s\n %s" "$msg" "$name" "$url")
        else
            msg=$(printf "%s\n馃寪 %s\n %s" "$msg" "$name" "$url")
        fi
    done <<< "$tunnels"

    msg=$(printf "%s\n\n馃晲 %s" "$msg" "$(date '+%Y-%m-%d %H:%M:%S')")
    printf '%s' "$msg"
}

# ============ Tunnel Check ============
do_check() {
    local tunnels
    tunnels=$(ensure_and_get)

    if [ -z "$tunnels" ]; then
        log "ERROR: Failed to get tunnel info"
        return 1
    fi

    # First run: save state and notify
    if [ ! -f "$STATE_FILE" ]; then
        printf '%s\n' "$tunnels" > "$STATE_FILE"
        log "Initial tunnel state recorded"
        send_telegram "$TELEGRAM_CHAT_ID" "$(format_tunnels "$tunnels")"
        return 0
    fi

    # Compare with previous state (comm requires sorted input)
    local old new added removed
    old=$(mktemp)
    new=$(mktemp)
    sort "$STATE_FILE" > "$old"
    printf '%s\n' "$tunnels" | sort > "$new"

    added=$(comm -13 "$old" "$new" || true)
    removed=$(comm -23 "$old" "$new" || true)

    rm -f "$old" "$new"
    printf '%s\n' "$tunnels" > "$STATE_FILE"

    if [ -n "$added" ] || [ -n "$removed" ]; then
        log "Tunnel change detected"
        local msg
        msg=$(printf "鈿?<b>cpolar 闅ч亾鍙樻洿</b>\n鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣")

        if [ -n "$added" ]; then
            msg=$(printf "%s\n馃啎 <b>鏂板:</b>" "$msg")
            while IFS='|' read -r n u; do
                [ -z "$u" ] && continue
                msg=$(printf "%s\n馃煝 <b>%s</b> 鈫?<code>%s</code>" "$msg" "$n" "$u")
            done <<< "$added"
        fi

        if [ -n "$removed" ]; then
            msg=$(printf "%s\n馃棏 <b>澶辨晥:</b>" "$msg")
            while IFS='|' read -r n u; do
                [ -z "$u" ] && continue
                msg=$(printf "%s\n馃敶 <b>%s</b> 鈫?<code>%s</code>" "$msg" "$n" "$u")
            done <<< "$removed"
        fi

        msg=$(printf "%s\n鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣\n鈿狅笍 璇峰強鏃舵洿鏂拌繛鎺ラ厤缃? "$msg")
        send_telegram "$TELEGRAM_CHAT_ID" "$msg"
    else
        log "No tunnel change"
    fi
}

# ============ Telegram Command Listener ============
BOT_USERNAME=""

init_bot_username() {
    BOT_USERNAME=$(curl --connect-timeout 10 --max-time 10 -s \
        "https://api.telegram.org/bot${TELEGRAM_TOKEN}/getMe" 2>/dev/null \
        | grep -oP '"username":\s*"\K[^"]+' || true)
    log "Bot: @${BOT_USERNAME}"
}

do_telegram_poll() {
    local offset
    if [ -f "$OFFSET_FILE" ]; then
        offset=$(cat "$OFFSET_FILE")
    else
        offset="0"
    fi

    local updates
    updates=$(curl --connect-timeout 15 \
        --max-time $((TELEGRAM_POLL_TIMEOUT + 10)) -s \
        "https://api.telegram.org/bot${TELEGRAM_TOKEN}/getUpdates?offset=${offset}&timeout=${TELEGRAM_POLL_TIMEOUT}" \
        2>/dev/null || true)

    [ -z "$updates" ] && return 0
    printf '%s' "$updates" | grep -q '"update_id"' || return 0

    local uid
    for uid in $(printf '%s' "$updates" | grep -oP '"update_id":\K\d+'); do
        offset=$((uid + 1))
        printf '%s\n' "$offset" > "$OFFSET_FILE"

        local text chat_id
        text=$(python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
for r in d.get('result', []):
    if r.get('update_id') == ${uid}:
        print(r.get('message', {}).get('text', ''))
        break
" <<< "$updates" 2>/dev/null || true)

        chat_id=$(python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
for r in d.get('result', []):
    if r.get('update_id') == ${uid}:
        print(r.get('message', {}).get('chat', {}).get('id', ''))
        break
" <<< "$updates" 2>/dev/null || true)

        [ -z "$text" ] && continue
        [ -z "$chat_id" ] && continue

        # Only respond to authorized chat_id
        if [ "$chat_id" != "$TELEGRAM_CHAT_ID" ]; then
            log "Ignored unauthorized request from chat_id=$chat_id"
            continue
        fi

        local cmd="" exec_args=""
        case "$text" in
            "/cpolar"|"/cpolar@${BOT_USERNAME}") cmd="cpolar" ;;
            "/status"|"/status@${BOT_USERNAME}") cmd="status" ;;
            "/docker"|"/docker@${BOT_USERNAME}") cmd="docker" ;;
            "/top"|"/top@${BOT_USERNAME}") cmd="top" ;;
            "/disk"|"/disk@${BOT_USERNAME}") cmd="disk" ;;
            "/net"|"/net@${BOT_USERNAME}") cmd="net" ;;
            "/help"|"/help@${BOT_USERNAME}") cmd="help" ;;
            "/ip"|"/ip@${BOT_USERNAME}") cmd="ip" ;;
            "/users"|"/users@${BOT_USERNAME}") cmd="users" ;;
            "/log"|"/log@${BOT_USERNAME}") cmd="log" ;;
            "/fail2ban"|"/fail2ban@${BOT_USERNAME}") cmd="fail2ban" ;;
            "/update"|"/update@${BOT_USERNAME}") cmd="update" ;;
            /exec*)
                cmd="exec"
                # Extract args: remove "/exec " or "/exec@bot "
                exec_args=$(printf '%s' "$text" | sed -E 's|^/exec(@[^ ]+)? ||')
                ;;
        esac

        if [ -n "$cmd" ]; then
            log "Received /$cmd command"
            case "$cmd" in
                cpolar)
                    local tunnels
                    tunnels=$(ensure_and_get)
                    if [ -n "$tunnels" ]; then
                        printf '%s\n' "$tunnels" > "$STATE_FILE"
                        send_telegram "$chat_id" "$(format_tunnels "$tunnels")"
                    else
                        send_telegram "$chat_id" "鉂?鑾峰彇闅ч亾淇℃伅澶辫触"
                    fi
                    ;;
                status)
                    send_telegram "$chat_id" "$(bash "$SCRIPT_DIR/vps-commands.sh" status)"
                    ;;
                docker)
                    send_telegram "$chat_id" "$(bash "$SCRIPT_DIR/vps-commands.sh" docker)"
                    ;;
                top)
                    send_telegram "$chat_id" "$(bash "$SCRIPT_DIR/vps-commands.sh" top)"
                    ;;
                disk)
                    send_telegram "$chat_id" "$(bash "$SCRIPT_DIR/vps-commands.sh" disk)"
                    ;;
                net)
                    send_telegram "$chat_id" "$(bash "$SCRIPT_DIR/vps-commands.sh" network)"
                    ;;
                ip)
                    send_telegram "$chat_id" "$(bash "$SCRIPT_DIR/vps-commands.sh" ip)"
                    ;;
                users)
                    send_telegram "$chat_id" "$(bash "$SCRIPT_DIR/vps-commands.sh" users)"
                    ;;
                log)
                    send_telegram "$chat_id" "$(bash "$SCRIPT_DIR/vps-commands.sh" log)"
                    ;;
                fail2ban)
                    send_telegram "$chat_id" "$(bash "$SCRIPT_DIR/vps-commands.sh" fail2ban)"
                    ;;
                update)
                    send_telegram "$chat_id" "$(bash "$SCRIPT_DIR/vps-commands.sh" update)"
                    ;;
                exec)
                    if [ -z "$exec_args" ]; then
                        send_telegram "$chat_id" "鐢ㄦ硶: /exec <鍛戒护>\n绀轰緥: /exec uptime"
                    else
                        log "EXEC: $exec_args"
                        local output
                        output=$(timeout 30 bash -c "$exec_args" 2>&1 || true)
                        if [ -z "$output" ]; then
                            output="(鏃犺緭鍑?"
                        fi
                        # Truncate to Telegram limit (4096 chars)
                        if [ ${#output} -gt 3800 ]; then
                            output="${output:0:3800}\n... (宸叉埅鏂?"
                        fi
                        send_telegram "$chat_id" "鈿欙笍 <code>$(printf '%s' "$exec_args" | head -1)</code>\n鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣\n<pre>$(printf '%s' "$output")</pre>"
                    fi
                    ;;
                help)
                    send_telegram "$chat_id" "馃摉 <b>鍙敤鍛戒护</b>\n鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣\n/cpolar - 闅ч亾鐘舵€乗n/status - 绯荤粺姒傝\n/docker - 瀹瑰櫒鍒楄〃\n/top - CPU 杩涚▼\n/disk - 纾佺洏浣跨敤\n/net - 缃戠粶绔彛\n/ip - 鍏綉 IP\n/users - 鍦ㄧ嚎鐢ㄦ埛\n/log - 绯荤粺鏃ュ織\n/fail2ban - 瀹夊叏灏佺\n/update - 鍙洿鏂板寘\n/exec <cmd> - 鎵ц鍛戒护\n/help - 甯姪"
                    ;;
            esac
            log "Replied /$cmd"
        fi
    done
}

# ============ Daemon Loop ============
daemon_loop() {
    init_bot_username
    log "Daemon started (PID: $$)"
    local last_check=0

    while true; do
        local now
        now=$(date +%s)

        if [ $((now - last_check)) -ge "$CHECK_INTERVAL" ]; then
            do_check
            last_check=$now
        fi

        do_telegram_poll
        sleep 1
    done
}

# ============ CLI ============
show_status() {
    if [ -f "$LOCK_FILE" ]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "鉁?Running (PID: $pid)"
            echo ""
            echo "Tunnels:"
            if [ -f "$STATE_FILE" ]; then
                while IFS='|' read -r name url; do
                    printf "  %s 鈫?%s\n" "$name" "$url"
                done < "$STATE_FILE"
            fi
            echo ""
            echo "Last log:"
            tail -3 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
        else
            rm -f "$LOCK_FILE"
            echo "鉂?Not running (stale lock cleaned)"
        fi
    else
        echo "鉂?Not running"
    fi
}

case "${1:-help}" in
    start)
        acquire_lock
        setsid bash "$0" run > /dev/null 2>&1 &
        echo "Daemon started (PID: $!)"
        ;;
    stop)
        if [ -f "$LOCK_FILE" ]; then
            pid=$(cat "$LOCK_FILE" 2>/dev/null || true)
            if [ -n "$pid" ]; then
                kill "$pid" 2>/dev/null || true
                for _ in $(seq 1 5); do
                    kill -0 "$pid" 2>/dev/null || break
                    sleep 1
                done
                kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
                release_lock
                echo "Stopped"
            else
                echo "Not running"
            fi
        else
            echo "Not running"
        fi
        ;;
    status)
        show_status
        ;;
    log)
        tail -${2:-20} "$LOG_FILE"
        ;;
    run)
        acquire_lock
        trap release_lock EXIT INT TERM
        daemon_loop
        ;;
    help|*)
        echo "cpolar-monitor 鈥?cpolar tunnel change monitor"
        echo ""
        echo "Usage: $(basename "$0") <command>"
        echo ""
        echo "Commands:"
        echo "  start     Start daemon in background"
        echo "  stop      Stop daemon"
        echo "  status    Show status and current tunnels"
        echo "  log [n]   Show last n log lines (default: 20)"
        echo "  run       Run in foreground (for debugging)"
        echo "  help      Show this help"
        echo ""
        echo "Config: .env file in the same directory"
        ;;
esac
