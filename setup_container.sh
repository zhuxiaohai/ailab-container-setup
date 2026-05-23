#!/usr/bin/env bash
# 宿主机入口：新建容器 或 仅对已有容器补跑配置

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/common.sh"

configure_existing() {
    local name="$1"
    echo "==> 容器: $name"
    docker inspect "$name" >/dev/null

    local ip
    ip="$(container_ip "$name")"
    echo "    IP: $ip"

    local ssh_port
    ssh_port="$(resolve_ssh_port "$ip")"

    echo "==> 容器内自动化配置 (SSH=${ssh_port})..."
    mapfile -t _DOCKER_ENV < <(config_docker_exec_env "$ip")
    docker exec "$name" env "${_DOCKER_ENV[@]}" bash "${CONTAINER_SETUP_ROOT}/setup-inside-container.sh"

    echo ""
    echo "完成。"
    echo "  进容器:  docker exec -it $name bash"
    echo "  连接信息: docker exec $name bash -ic container_info"
    echo "  开代理:  docker exec -it $name bash -ic 'proxy_on && proxy_status'"
    echo "  SSH:     ssh root@$ip -p $ssh_port"
}

case "${1:-}" in
    launch)
        shift
        exec "${SCRIPT_DIR}/launch-container.sh" "$@"
        ;;
    configure)
        configure_existing "${2:?用法: $0 configure <container_name>}"
        ;;
    -h|--help|help)
        sed -n '2,12p' "$0"
        ;;
    "")
        echo "用法: $0 launch <image> <name> <ip>  |  $0 configure <name>  |  $0 <name>"
        exit 1
        ;;
    *)
        configure_existing "$1"
        ;;
esac
