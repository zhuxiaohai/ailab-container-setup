#!/usr/bin/env bash
set -euo pipefail

_REPO_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${_REPO_LIB}/.." && pwd)"
export REPO_ROOT

# shellcheck source=load-config.sh
. "${_REPO_LIB}/load-config.sh"
load_repo_config

CONTAINER_SETUP_ROOT="${CONTAINER_SETUP_ROOT:-${REPO_ROOT}}"
WORKSPACE_SECRETS="${WORKSPACE_SECRETS:-/workspace}"
CLASH_DIR="${CLASH_DIR:-/etc/clash}"
CLASH_BIN="${CLASH_BIN:-/usr/local/clash}"
CONTAINER_ENV_FILE="${CONTAINER_ENV_FILE:-${WORKSPACE_SECRETS}/.container.env}"
PROXY_STATE_FILE="${PROXY_STATE_FILE:-${WORKSPACE_SECRETS}/.proxy_state}"
CLASH_RUN_STATE_FILE="${CLASH_RUN_STATE_FILE:-${CLASH_DIR}/.run_state}"

read_clash_sublink() {
    if [ -n "${CLASH_SUBLINK:-}" ]; then
        echo "$CLASH_SUBLINK"
        return 0
    fi
    return 1
}

read_clash_download_base() {
    if [ -n "${CLASH_DOWNLOAD_BASE:-}" ]; then
        echo "$CLASH_DOWNLOAD_BASE"
        return 0
    fi
    if [ -f "${CLASH_DIR}/.downloadlink" ]; then
        cat "${CLASH_DIR}/.downloadlink"
        return 0
    fi
    return 1
}

last_ip_octet() {
    local ip="$1"
    echo "${ip##*.}"
}

auto_ssh_port() {
    local ip="$1"
    echo $((SSH_PORT_BASE + $(last_ip_octet "$ip")))
}

# SSH_PORT 留空时按 IP 推算；config 里写死则用配置值
resolve_ssh_port() {
    local ip="${1:-}"
    local port="${SSH_PORT:-}"
    if [ -z "$port" ] && [ -n "$ip" ]; then
        port=$((SSH_PORT_BASE + $(last_ip_octet "$ip")))
    fi
    port="${port:-${SSH_FALLBACK_PORT:-22}}"
    echo "$port"
}

container_ip() {
    local name="$1"
    docker inspect "$name" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | head -1
}

_trim_volume_spec() {
    local s="$1"
    s="${s%%#*}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# 解析单条 host:container，成功则向 DOCKER_VOLUME_ARGS 追加 -v
_add_docker_volume_spec() {
    local spec host container
    spec="$(_trim_volume_spec "$1")"
    [[ -z "$spec" ]] && return 0
    if [[ "$spec" != *:* ]]; then
        echo "WARN: 忽略无效挂载（需 host:container）: $spec" >&2
        return 0
    fi
    host="${spec%%:*}"
    container="${spec#*:}"
    host="$(_trim_volume_spec "$host")"
    container="$(_trim_volume_spec "$container")"
    if [[ -z "$host" || -z "$container" ]]; then
        echo "WARN: 忽略无效挂载（host 或 container 为空）: $spec" >&2
        return 0
    fi
    if [[ ! -e "$host" ]]; then
        echo "WARN: 宿主机路径不存在，仍将挂载: $host -> $container" >&2
    fi
    DOCKER_VOLUME_ARGS+=(-v "${host}:${container}")
}

# 从字符串解析（分号或换行分隔）
_parse_docker_extra_volumes_var() {
    local raw="$1" part
    [[ -z "$raw" ]] && return 0
    raw="${raw//$'\n'/;}"
    local IFS=';'
    for part in $raw; do
        _add_docker_volume_spec "$part"
    done
}

# 从列表文件解析（每行 host:container，# 开头为注释）
_parse_docker_extra_volumes_file() {
    local f="$1" line
    [[ -f "$f" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(_trim_volume_spec "$line")"
        [[ -z "$line" ]] && continue
        _add_docker_volume_spec "$line"
    done <"$f"
}

# 收集额外挂载到 DOCKER_VOLUME_ARGS（调用方 docker run 时展开 "${DOCKER_VOLUME_ARGS[@]}"）
# 来源（按顺序合并）：
#   1. DOCKER_EXTRA_VOLUMES（config.local.env 一行，分号分隔）
#   2. config.extra-volumes（可选，每行一条，见 config.extra-volumes.example）
docker_collect_extra_volumes() {
    DOCKER_VOLUME_ARGS=()
    _parse_docker_extra_volumes_var "${DOCKER_EXTRA_VOLUMES:-}"
    _parse_docker_extra_volumes_file "${REPO_ROOT}/config.extra-volumes"
}
