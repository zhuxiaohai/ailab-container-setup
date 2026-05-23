#!/usr/bin/env bash
# 宿主机资源监控,每5秒采集一次,sync 强制落盘
# 用法: bash monitor.sh

LOG_ROOT="/mnt/local_ssd_550/zhuxiaohai/logs/monitor"
LOGDIR="${LOG_ROOT}/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOGDIR"

# 维护一个 latest 软链,事后排查直接看
ln -sfn "$LOGDIR" "${LOG_ROOT}/latest"

echo "Monitor PID=$$ logdir=$LOGDIR"
echo $$ > "$LOGDIR/monitor.pid"

# 1) 持续 tail 内核日志(NFS hang / OOM / Xid 都在这里)
( dmesg -wT > "$LOGDIR/dmesg.log" 2>&1 ) &
echo $! > "$LOGDIR/dmesg.pid"

# 2) 主循环:内存 + GPU + 进程 + 负载,打到同一个文件
exec > "$LOGDIR/host.log" 2>&1
trap 'echo "stopped at $(date)"; sync; kill $(cat "$LOGDIR/dmesg.pid") 2>/dev/null; exit 0' INT TERM

while true; do
    TS=$(date '+%F %T')
    echo "===== $TS ====="

    echo "--- loadavg / D-state count ---"
    cat /proc/loadavg
    echo "D-state procs: $(ps -eo stat | grep -c '^D')"

    echo "--- free ---"
    free -h

    echo "--- top 15 by RSS ---"
    ps -eo pid,user,stat,rss,comm --sort=-rss | head -15

    echo "--- nvidia-smi ---"
    nvidia-smi --query-gpu=index,memory.used,memory.total,utilization.gpu,temperature.gpu,power.draw \
               --format=csv,noheader 2>&1

    echo "--- df SSD/root/NFS ---"
    df -h / /mnt/local_ssd_550 /mnt/remotedisk_ailab_common /mnt/remotedisk_ailab_node1 2>&1

    echo ""
    sync           # 强制把 host.log 刷到 SSD
    sleep 5
done
