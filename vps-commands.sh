#!/bin/bash
# /status command handler for Telegram bot
# Outputs system status in a compact format

get_status() {
    local msg
    msg=$(printf "馃搳 <b>Debian VPS 鐘舵€?/b>\n鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣\n")

    # Uptime & Load
    local uptime_str load
    uptime_str=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | sed 's/,.*load.*//')
    load=$(uptime | grep -oP 'load average: \K.*')
    msg=$(printf "%s鈴?%s\n馃搱 Load: %s\n\n" "$msg" "$uptime_str" "$load")

    # Memory
    local mem_total mem_used mem_pct
    mem_total=$(free -m | awk '/Mem:/{print $2}')
    mem_used=$(free -m | awk '/Mem:/{print $3}')
    mem_pct=$((mem_used * 100 / mem_total))
    msg=$(printf "%s馃捑 鍐呭瓨: %sMB / %sMB (%s%%)\n" "$msg" "$mem_used" "$mem_total" "$mem_pct")

    # Disk
    local disk_used disk_total disk_pct
    disk_used=$(df -h / | awk 'NR==2{print $3}')
    disk_total=$(df -h / | awk 'NR==2{print $2}')
    disk_pct=$(df -h / | awk 'NR==2{print $5}')
    msg=$(printf "%s馃捒 纾佺洏: %s / %s (%s)\n\n" "$msg" "$disk_used" "$disk_total" "$disk_pct")

    # Docker
    local docker_count
    docker_count=$(docker ps -q 2>/dev/null | wc -l)
    msg=$(printf "%s馃惓 Docker 瀹瑰櫒: %s 涓繍琛屼腑\n" "$msg" "$docker_count")
    if [ "$docker_count" -gt 0 ]; then
        while IFS= read -r line; do
            msg=$(printf "%s  %s\n" "$msg" "$line")
        done < <(docker ps --format "{{.Names}}: {{.Status}}" 2>/dev/null)
    fi
    msg=$(printf "%s\n" "$msg")

    # Key services
    msg=$(printf "%s馃攲 鏈嶅姟鐘舵€?\n" "$msg")
    for svc in sing-box ssh docker; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            msg=$(printf "%s  鉁?%s\n" "$msg" "$svc")
        else
            msg=$(printf "%s  鉂?%s\n" "$msg" "$svc")
        fi
    done

    msg=$(printf "%s鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣\n馃晲 %s" "$msg" "$(date '+%Y-%m-%d %H:%M:%S')")
    printf '%s' "$msg"
}

get_docker() {
    local msg
    msg=$(printf "馃惓 <b>Docker 瀹瑰櫒</b>\n鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣\n")
    while IFS= read -r line; do
        msg=$(printf "%s%s\n" "$msg" "$line")
    done < <(docker ps -a --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | column -t)
    printf '%s' "$msg"
}

get_top() {
    local msg
    msg=$(printf "馃敐 <b>Top 杩涚▼ (CPU)</b>\n鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣\n")
    while IFS= read -r line; do
        msg=$(printf "%s%s\n" "$msg" "$line")
    done < <(ps aux --sort=-%cpu | head -6 | tail -5 | awk '{printf "%s %s%% %s\n", $1, $3, $11}')
    printf '%s' "$msg"
}

get_network() {
    local msg
    msg=$(printf "馃寪 <b>缃戠粶鐘舵€?/b>\n鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣\n")
    msg=$(printf "%s馃摗 鐩戝惉绔彛:\n" "$msg")
    while IFS= read -r line; do
        msg=$(printf "%s  %s\n" "$msg" "$line")
    done < <(ss -tlnp 2>/dev/null | grep LISTEN | awk '{print $4, $6}' | head -10)
    printf '%s' "$msg"
}

get_disk() {
    local msg
    msg=$(printf "馃捒 <b>纾佺洏浣跨敤</b>\n鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣\n")
    while IFS= read -r line; do
        msg=$(printf "%s%s\n" "$msg" "$line")
    done < <(df -h | grep -E '^/dev/' | awk '{printf "%s  %s / %s (%s)\n", $6, $3, $2, $5}')
    printf '%s' "$msg"
}

case "${1:-status}" in
    status)  get_status ;;
    docker)  get_docker ;;
    top)     get_top ;;
    network) get_network ;;
    disk)    get_disk ;;
    *)       echo "Unknown command: $1" ;;
esac
