#!/bin/bash
# Watchdog: restart if daemon is dead or consuming too much memory
LOCK="/opt/cpolar-monitor/cpolar-monitor.lock"
LOG="/opt/cpolar-monitor/cpolar-monitor.log"
MAX_RSS_KB=51200  # 50MB threshold

if [ -f "$LOCK" ]; then
    pid=$(cat "$LOCK" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
        if [ -n "$rss" ] && [ "$rss" -gt "$MAX_RSS_KB" ]; then
            echo "[$(date)] Watchdog: RSS ${rss}KB > ${MAX_RSS_KB}KB, restarting" >> "$LOG"
            kill -9 "$pid" 2>/dev/null
            rm -f "$LOCK"
            sleep 1
            bash /opt/cpolar-monitor/cpolar-monitor.sh start
        fi
    else
        echo "[$(date)] Watchdog: daemon dead, restarting" >> "$LOG"
        rm -f "$LOCK"
        bash /opt/cpolar-monitor/cpolar-monitor.sh start
    fi
else
    echo "[$(date)] Watchdog: no lock file, starting daemon" >> "$LOG"
    bash /opt/cpolar-monitor/cpolar-monitor.sh start
fi
