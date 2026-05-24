#!/usr/bin/env bash
# 宿主机：创建/启动容器并完成容器内自动化配置
#
# 用法:
#   ./launch-container.sh <image> <name> <ip>
#
# 配置见 config.local.env；由 lib/common.sh 按 README 优先级加载

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $0 <image> <container_name> <container_ip>

环境变量：见 config.local.env；命令行 export 可临时覆盖。
  SKIP_SETUP=1  只启动容器，不跑容器内 setup
EOF
    exit 1
}

[[ $# -ge 3 ]] || usage

IMAGE="$1"
NAME="$2"
IP="$3"

SSH_PORT="$(resolve_ssh_port "$IP")"

log() { echo "==> $*"; }

if ! docker network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1; then
    echo "WARN: 网络 ${DOCKER_NETWORK} 不存在，请先创建: docker network create --subnet=... ${DOCKER_NETWORK}"
fi

if docker ps -a --format '{{.Names}}' | grep -qx "${NAME}"; then
    log "容器 ${NAME} 已存在，删除后重建..."
    docker rm -f "${NAME}"
fi

docker_collect_extra_volumes
if ((${#DOCKER_VOLUME_ARGS[@]} > 0)); then
    log "额外挂载 ${#DOCKER_VOLUME_ARGS[@]} 项（DOCKER_EXTRA_VOLUMES / config.extra-volumes）"
fi

log "启动容器 ${NAME} (${IMAGE}) IP=${IP}"
docker run \
    --network="${DOCKER_NETWORK}" \
    --ip="${IP}" \
    --gpus all \
    -d -it \
    -v "${VOL_WORKSPACE_HOST}:${VOL_WORKSPACE}" \
    -v "${VOL_DATA_HOST}:${VOL_DATA}" \
    -v "${VOL_MODEL_HOST}:${VOL_MODEL}" \
    "${DOCKER_VOLUME_ARGS[@]}" \
    --name="${NAME}" \
    "${IMAGE}" \
    bash

log "等待容器就绪..."
for _ in $(seq 1 30); do
    if docker exec "${NAME}" true 2>/dev/null; then
        break
    fi
    sleep 1
done

ACTUAL_IP="$(container_ip "$NAME")"
log "容器 IP: ${ACTUAL_IP} (期望 ${IP})"

if [ "${SKIP_SETUP:-0}" = "1" ]; then
    log "SKIP_SETUP=1，跳过容器内配置"
    exit 0
fi

log "执行容器内 setup-inside-container.sh ..."
# 容器内再次 load_repo_config；此处传入运行时 IP 与命令行覆盖项
mapfile -t _DOCKER_ENV < <(config_docker_exec_env "${ACTUAL_IP:-$IP}")
docker exec "${NAME}" env "${_DOCKER_ENV[@]}" bash "${CONTAINER_SETUP_ROOT}/setup-inside-container.sh"

echo ""
echo "=========================================="
echo "容器: ${NAME}"
echo "IP:   ${ACTUAL_IP:-$IP}"
echo "SSH:  ssh root@${ACTUAL_IP:-$IP} -p ${SSH_PORT}"
echo "进入: docker exec -it ${NAME} bash"
echo "连接信息（容器内）: docker exec ${NAME} bash -ic container_info"
echo "密码见: docker exec ${NAME} cat /workspace/.container.env"
echo "=========================================="
