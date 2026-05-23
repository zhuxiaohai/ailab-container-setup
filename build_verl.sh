#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/common.sh"

# ---- verl 容器（host 网络 + 本地 SSD 挂载）----
# 用法:
#   ./build_verl.sh <image:tag> [container_name]
#
# 若需固定 IP + docker_network + 远程盘挂载，请用:
#   ./launch-container.sh <image> <name> <ip>
#   或 ./setup_container.sh launch <image> <name> <ip>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <image:tag> [container_name]"
    echo "  image:tag        Docker image to use (required)"
    echo "  container_name   Container name (default: verl)"
    echo ""
    echo "固定 IP 网络模式请使用: ${SCRIPT_DIR}/launch-container.sh"
    exit 1
fi

IMAGE="$1"
NAME="${2:-verl}"
LOCAL_ROOT="/mnt/local_ssd_550/zhuxiaohai"

mkdir -p \
    "${LOCAL_ROOT}/code" \
    "${LOCAL_ROOT}/model" \
    "${LOCAL_ROOT}/data" \
    "${LOCAL_ROOT}/checkpoints" \
    "${LOCAL_ROOT}/logs" \
    "${LOCAL_ROOT}/tensorboard"

if docker ps -a --format '{{.Names}}' | grep -q "^${NAME}$"; then
    echo "Container '${NAME}' already exists, removing..."
    docker rm -f "${NAME}"
fi

docker create \
    --name "${NAME}" \
    --runtime=nvidia \
    --gpus all \
    --net=host \
    --shm-size=64g \
    --memory=700g \
    --memory-swap=700g \
    --memory-reservation=400g \
    -v "${LOCAL_ROOT}/code:/workspace/verl" \
    -v "${LOCAL_ROOT}/model:/model" \
    -v "${LOCAL_ROOT}/data:/data" \
    -v "${LOCAL_ROOT}/checkpoints:/checkpoints" \
    -v "${LOCAL_ROOT}/logs:/logs" \
    -v "${LOCAL_ROOT}/tensorboard:/tensorboard" \
    "${IMAGE}" \
    sleep infinity

docker start "${NAME}"

echo ""
echo "Container '${NAME}' started (host network)."
echo "Enter: docker exec -it ${NAME} bash"
echo ""
echo "可选：容器内自动化（SSH/代理/bashrc）:"
echo "  docker exec ${NAME} bash ${SCRIPT_DIR}/setup-inside-container.sh"
echo "或使用固定 IP 流程:"
echo "  ${SCRIPT_DIR}/launch-container.sh <image> <name> <ip>"
