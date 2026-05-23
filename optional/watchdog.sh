#!/usr/bin/env bash
# 监控 verl 容器,死掉的瞬间立刻把现场打到磁盘
# 用法: bash watchdog.sh [容器名]

NAME="${1:-verl}"
LOG_ROOT="/mnt/local_ssd_550/zhuxiaohai/logs/monitor"

# 等 monitor.sh 建好 latest 软链,把 watchdog 日志也写到同一目录
sleep 2
LOGDIR="$(readlink -f "${LOG_ROOT}/latest")"
if [[ -z "$LOGDIR" || ! -d "$LOGDIR" ]]; then
    LOGDIR="${LOG_ROOT}/$(date +%Y%m%d_%H%M%S)_watchdog_only"
    mkdir -p "$LOGDIR"
fi

WATCH="$LOGDIR/watchdog.log"
exec >> "$WATCH" 2>&1

echo "===== watchdog start $(date), target=$NAME, logdir=$LOGDIR ====="

PREV_STATE="running"
while true; do
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${NAME}$"; then
        CUR_STATE="running"
    else
        CUR_STATE="gone"
    fi

    if [[ "$CUR_STATE" == "gone" && "$PREV_STATE" == "running" ]]; then
        echo ""
        echo "===== container '${NAME}' GONE at $(date) ====="

        echo "--- docker ps -a ---"
        docker ps -a --filter "name=${NAME}" 2>&1

        echo "--- docker inspect key fields ---"
        docker inspect "${NAME}" 2>&1 | grep -E 'OOMKilled|ExitCode|Error|FinishedAt|StartedAt|Status' | head -20

        echo "--- last 50 lines of dmesg ---"
        dmesg -T 2>/dev/null | tail -50

        echo "--- recent OOM/NFS/Xid hits ---"
        dmesg -T 2>/dev/null | grep -iE 'oom|killed process|nfs|xid|hung_task|blocked for more than' | tail -30

        sync
    fi

    PREV_STATE="$CUR_STATE"
    sleep 5
done
