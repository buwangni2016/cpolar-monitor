#!/bin/bash
# cpolar-monitor — cpolar tunnel monitor with Telegram alerts
# Core: tunnel change detection + /cpolar query only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
[ -f "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

CPOLAR_EMAIL="${CPOLAR_EMAIL:?Set in .env}"
CPOLAR_PASSWORD="${CPOLAR_PASSWORD:?Set in .env}"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:?Set in .env}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:?Set in .env}"
CHECK_INTERVAL="${CHECK_INTERVAL:-600}"
TELEGRAM_POLL_TIMEOUT="${TELEGRAM_POLL_TIMEOUT:-30}"

COOKIE_FILE="${SCRIPT_DIR}/.cpolar_cookie"
STATE_FILE="${SCRIPT_DIR}/.tunnel_state"
LOG_FILE="${SCRIPT_DIR}/cpolar-monitor.log"
LOCK_FILE="${SCRIPT_DIR}/cpolar-monitor.lock"
OFFSET_FILE="${SCRIPT_DIR}/.tg_offset"

# Lock
[ -f "$LOCK_FILE" ] && { pid=$(cat "$LOCK_FILE" 2>/dev/null); [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && { echo "Running (PID: $pid)"; exit 0; }; }
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT INT TERM

log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

send_telegram() {
    local chat_id="$1" text="$2"
    curl --connect-timeout 15 --max-time 15 -s -X POST \
        "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${chat_id}" --data-urlencode "text=${text}" -d parse_mode="HTML" >/dev/null 2>&1 \
        && log "Telegram -> $chat_id" || log "ERROR: Telegram failed"
}

do_login() {
    local page token
    page=$(curl -s -c "$COOKIE_FILE" "https://dashboard.cpolar.com/login")
    token=$(printf '%s' "$page" | grep -oP 'name="csrf_token"\s+value="\K[^"]+' || true)
    [ -z "$token" ] && { log "ERROR: No CSRF token"; return 1; }
    local resp
    resp=$(curl -s -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST \
        "https://dashboard.cpolar.com/login" \
        -d "login=${CPOLAR_EMAIL}&password=${CPOLAR_PASSWORD}&csrf_token=${token}" -L)
    if printf '%s' "$resp" | grep -q 'id="captcha-form"'; then log "ERROR: Login failed"; return 1; fi
    log "Login OK"
}

get_tunnels() {
    local html
    html=$(curl -s -b "$COOKIE_FILE" "https://dashboard.cpolar.com/status")
    if printf '%s' "$html" | grep -q 'id="captcha-form"' || printf '%s' "$html" | grep -q '/login'; then
        rm -f "$COOKIE_FILE"; do_login || return 1
        html=$(curl -s -b "$COOKIE_FILE" "https://dashboard.cpolar.com/status")
    fi
    python3 -c "
import re,sys
html=sys.stdin.read()
t=re.sub(r'<script[^>]*>.*?</script>','',html,flags=re.DOTALL)
t=re.sub(r'<style[^>]*>.*?</style>','',t,flags=re.DOTALL)
t=re.sub(r'<[^>]+>','\n',t).replace('&#43;','+').replace('&amp;','&')
lines=[l.strip() for l in t.split('\n') if l.strip()]
url_re=re.compile(r'(https?://[a-z0-9]+\.r\d+\.cpolar\.(cn|top)|tcp://\d+\.tcp\.cpolar\.top:\d+)')
r=[]
for i,l in enumerate(lines):
    if url_re.match(l):
        name=''
        for j in range(i-1,max(i-5,0),-1):
            if lines[j] and not url_re.match(lines[j]) and not re.match(r'^(cn|cn_top|us|ap)$',lines[j]):
                name=lines[j];break
        r.append(f'{name or \"unknown\"}|{l}')
for x in sorted(set(r)):print(x)
" <<< "$html" || true
}

ensure_and_get() {
    [ ! -f "$COOKIE_FILE" ] && { log "First login..."; do_login || return 1; }
    get_tunnels
}

format_tunnels() {
    local msg
    msg=$(printf "📋 <b>当前 cpolar 隧道</b>\n")
    while IFS='|' read -r name url; do
        [ -z "$url" ] && continue
        if printf '%s' "$url" | grep -q "^tcp://"; then
            msg=$(printf "%s\n🖥 %s\n %s" "$msg" "$name" "$url")
        else
            msg=$(printf "%s\n🌐 %s\n %s" "$msg" "$name" "$url")
        fi
    done <<< "$1"
    msg=$(printf "%s\n\n🕐 %s" "$msg" "$(date '+%Y-%m-%d %H:%M:%S')")
    printf '%s' "$msg"
}

do_check() {
    local tunnels
    tunnels=$(ensure_and_get)
    [ -z "$tunnels" ] && { log "ERROR: No tunnel data"; return 1; }

    if [ ! -f "$STATE_FILE" ]; then
        printf '%s\n' "$tunnels" > "$STATE_FILE"
        log "Initial state recorded"
        send_telegram "$TELEGRAM_CHAT_ID" "$(format_tunnels "$tunnels")"
        return 0
    fi

    local cur_hash old_hash
    cur_hash=$(printf '%s\n' "$tunnels" | sort | md5sum | cut -d' ' -f1)
    old_hash=$(sort "$STATE_FILE" | md5sum | cut -d' ' -f1)
    if [ "$cur_hash" = "$old_hash" ]; then
        log "No change"
        return 0
    fi

    local added removed
    added=$(comm -13 <(sort "$STATE_FILE") <(printf '%s\n' "$tunnels" | sort) || true)
    removed=$(comm -23 <(sort "$STATE_FILE") <(printf '%s\n' "$tunnels" | sort) || true)
    printf '%s\n' "$tunnels" > "$STATE_FILE"

    if [ -n "$added" ] || [ -n "$removed" ]; then
        log "Tunnel change detected"
        local msg
        msg=$(printf "⚡ <b>cpolar 隧道变更</b>\n━━━━━━━━━━━━━━━━━━━━━━")
        [ -n "$added" ] && { msg=$(printf "%s\n🆕 <b>新增:</b>" "$msg"); while IFS='|' read -r n u; do [ -z "$u" ] && continue; msg=$(printf "%s\n🟢 <b>%s</b> → <code>%s</code>" "$msg" "$n" "$u"); done <<< "$added"; }
        [ -n "$removed" ] && { msg=$(printf "%s\n🗑 <b>失效:</b>" "$msg"); while IFS='|' read -r n u; do [ -z "$u" ] && continue; msg=$(printf "%s\n🔴 <b>%s</b> → <code>%s</code>" "$msg" "$n" "$u"); done <<< "$removed"; }
        msg=$(printf "%s\n━━━━━━━━━━━━━━━━━━━━━━\n⚠️ 请及时更新连接配置" "$msg")
        send_telegram "$TELEGRAM_CHAT_ID" "$msg"
    else
        log "No change"
    fi
}

BOT_USERNAME=""
init_bot_username() {
    BOT_USERNAME=$(curl --connect-timeout 10 --max-time 10 -s \
        "https://api.telegram.org/bot${TELEGRAM_TOKEN}/getMe" 2>/dev/null \
        | grep -oP '"username":\s*"\K[^"]+' || true)
    log "Bot: @${BOT_USERNAME}"
}

do_telegram_poll() {
    local offset
    [ -f "$OFFSET_FILE" ] && offset=$(cat "$OFFSET_FILE") || offset="0"

    local updates
    updates=$(curl --connect-timeout 15 --max-time $((TELEGRAM_POLL_TIMEOUT + 10)) -s \
        "https://api.telegram.org/bot${TELEGRAM_TOKEN}/getUpdates?offset=${offset}&timeout=${TELEGRAM_POLL_TIMEOUT}" 2>/dev/null || true)
    [ -z "$updates" ] && return 0
    printf '%s' "$updates" | grep -q '"update_id"' || return 0

    # One Python call for all updates (was 3 calls per message)
    local parsed last_uid=""
    parsed=$(printf '%s' "$updates" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
for r in d.get('result',[]):
 uid=r.get('update_id','')
 msg=r.get('message',{})
 is_bot='1' if msg.get('from',{}).get('is_bot') else '0'
 text=msg.get('text','').replace('\t',' ').replace('\n',' ')
 chat_id=str(msg.get('chat',{}).get('id',''))
 print(str(uid)+'\t'+is_bot+'\t'+chat_id+'\t'+text)
" 2>/dev/null || true)
    [ -z "$parsed" ] && return 0

    while IFS=$'\t' read -r uid is_bot chat_id text; do
        last_uid=$uid
        [ "$is_bot" = "1" ] && continue
        [ -z "$text" ] || [ -z "$chat_id" ] && continue
        [ "$chat_id" != "$TELEGRAM_CHAT_ID" ] && { log "Ignored: $chat_id"; continue; }

        if [ "$text" = "/cpolar" ] || [ "$text" = "/cpolar@${BOT_USERNAME}" ]; then
            log "Received /cpolar"
            local tunnels
            tunnels=$(ensure_and_get)
            if [ -n "$tunnels" ]; then
                printf '%s\n' "$tunnels" > "$STATE_FILE"
                send_telegram "$chat_id" "$(format_tunnels "$tunnels")"
            else
                send_telegram "$chat_id" "❌ 获取失败"
            fi
        fi
    done <<< "$parsed"

    [ -n "$last_uid" ] && printf '%s\n' "$((last_uid + 1))" > "$OFFSET_FILE"
}

daemon_loop() {
    init_bot_username
    log "Daemon started (PID: $$)"
    local last_check=0
    while true; do
        local now
        now=$(date +%s)
        if [ $((now - last_check)) -ge "$CHECK_INTERVAL" ]; then
            do_check; last_check=$now
        fi
        do_telegram_poll; sleep 1
    done
}

case "${1:-help}" in
    start)
        [ -f "$LOCK_FILE" ] && { pid=$(cat "$LOCK_FILE" 2>/dev/null); [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && { echo "Running ($pid)"; exit 0; }; rm -f "$LOCK_FILE"; }
        setsid bash "$0" run >/dev/null 2>&1 &
        echo "Started (PID: $!)" ;;
    stop)
        [ -f "$LOCK_FILE" ] && { pid=$(cat "$LOCK_FILE"); kill "$pid" 2>/dev/null; sleep 1; kill -9 "$pid" 2>/dev/null; rm -f "$LOCK_FILE"; echo "Stopped"; } || echo "Not running" ;;
    status)
        if [ -f "$LOCK_FILE" ] && kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
            echo "✅ Running (PID: $(cat "$LOCK_FILE"))"
            [ -f "$STATE_FILE" ] && { echo ""; echo "Tunnels:"; while IFS='|' read -r n u; do echo "  $n → $u"; done < "$STATE_FILE"; }
        else echo "❌ Not running"; fi ;;
    log) tail -"${2:-20}" "$LOG_FILE" ;;    run) daemon_loop ;;
    run-once)
        do_check ;;
    help|*)
        echo "cpolar-monitor — tunnel change monitor"
        echo "Usage: $(basename "$0") {start|stop|status|log|run|run-once|help}" ;;
esac
