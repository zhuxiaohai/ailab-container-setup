#!/usr/bin/env bash
# 在容器内执行：SSH → Clash → bashrc（非交互）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/common.sh"
SETUP_ROOT="${CONTAINER_SETUP_ROOT}"
BASHRC_DIR="${SETUP_ROOT}/bashrc"

log() { echo "==> $*"; }

CONTAINER_IP="${CONTAINER_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
SSH_PORT="$(resolve_ssh_port "${CONTAINER_IP}")"

setup_bashrc() {
    log "配置 ~/.bashrc ..."
    local marker="# >>> workspace container setup >>>"
    if ! grep -q "$marker" ~/.bashrc 2>/dev/null; then
        cat >> ~/.bashrc << EOF

# >>> workspace container setup >>>
[ -f ${BASHRC_DIR}/.proxy.bashrc ] && . ${BASHRC_DIR}/.proxy.bashrc
[ -f ${BASHRC_DIR}/.container.bashrc ] && . ${BASHRC_DIR}/.container.bashrc
# <<< workspace container setup <<<
EOF
    fi
    if grep -q '^proxy_on()' ~/.bashrc 2>/dev/null && grep -q 'workspace container setup' ~/.bashrc; then
        python3 - <<'PY'
from pathlib import Path
p = Path.home() / ".bashrc"
text = p.read_text(encoding="utf-8", errors="ignore")
marker = "# >>> workspace container setup >>>"
if "proxy_on()" not in text or marker not in text:
    raise SystemExit(0)
start = text.find("proxy_on()")
end = text.find(marker)
if start != -1 and end != -1 and start < end:
    p.write_text(text[:start] + text[end:], encoding="utf-8")
    print("已移除 ~/.bashrc 中旧的 proxy_on 函数块")
PY
    fi
}

install_clash_if_needed() {
    if [ "${AUTO_CLASH:-1}" != "1" ]; then
        log "跳过 Clash (AUTO_CLASH=0)"
        return
    fi
    if [ -x /usr/local/clash ] && [ -f /etc/clash/config.yaml ]; then
        if [ ! -f "${CLASH_RUN_STATE_FILE}" ]; then
            if pgrep -f "/usr/local/clash.*-d.*/etc/clash" >/dev/null 2>&1; then
                echo on > "${CLASH_RUN_STATE_FILE}"
            else
                echo off > "${CLASH_RUN_STATE_FILE}"
            fi
        fi
        local run_state
        run_state="$(cat "${CLASH_RUN_STATE_FILE}" 2>/dev/null | tr -d '[:space:]')"
        if [ "$run_state" = "off" ]; then
            log "Clash 已存在，按 .run_state=off 保持停止"
        else
            log "Clash 已存在，确保运行..."
            pgrep -f "/usr/local/clash.*-d.*/etc/clash" >/dev/null 2>&1 || \
                setsid /usr/local/clash -d /etc/clash >>/dev/null 2>&1 &
        fi
        return
    fi
    if ! read_clash_sublink >/dev/null 2>&1; then
        log "跳过 Clash：请在 config.local.env 设置 CLASH_SUBLINK"
        return
    fi
    log "安装 Clash ..."
    bash "${SCRIPT_DIR}/install-clash.sh"
}

setup_ssh() {
    if [ "${AUTO_SSH:-1}" != "1" ]; then
        log "跳过 SSH (AUTO_SSH=0)"
        return
    fi
    log "配置 SSH(${SSH_PORT}) ..."
    export CONTAINER_IP SSH_PORT ROOT_PASSWORD REDIRECT_PYTHON
    export CONTAINER_ENV_FILE WORKSPACE_SECRETS CONTAINER_SETUP_ROOT
    python3 "${SETUP_ROOT}/container/ssh-config-auto.py"
}

main() {
    log "容器内初始化 (IP=${CONTAINER_IP}, SSH=${SSH_PORT})"
    setup_ssh
    install_clash_if_needed
    setup_bashrc
    log "完成。执行 container_info 查看连接信息"
    if declare -f container_info >/dev/null 2>&1; then
        container_info
    elif [ -f "${CONTAINER_ENV_FILE}" ]; then
        # shellcheck disable=SC1091
        . "${CONTAINER_ENV_FILE}"
        echo "SSH: ssh root@${CONTAINER_IP} -p ${SSH_PORT}"
    fi
}

main "$@"
