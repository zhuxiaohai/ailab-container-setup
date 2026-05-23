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
