# 容器环境：端口信息 + 快捷命令（由 setup-inside-container.sh 自动写入 bashrc）
declare -f container_info >/dev/null 2>&1 && return

_CONTAINER_ENV="${CONTAINER_ENV_FILE:-${WORKSPACE_SECRETS:-/workspace}/.container.env}"
if [ -f "$_CONTAINER_ENV" ]; then
    # shellcheck disable=SC1090
    . "$_CONTAINER_ENV"
fi

container_info() {
    echo "-------- 容器连接信息 --------"
    echo "IP:        ${CONTAINER_IP:-未知}"
    echo "SSH:       ssh root@${CONTAINER_IP:-<IP>} -p ${SSH_PORT:-22}"
    if [ -n "${ROOT_PASSWORD:-}" ]; then
        echo "Password:  ${ROOT_PASSWORD}"
    fi
    echo "Clash:     127.0.0.1:${CLASH_PORT:-7890}  (xcjs / ${CLASH_RUN_STATE_FILE:-/etc/clash/.run_state})"
    _ps="off"
    if [ -f "${PROXY_STATE_FILE:-${WORKSPACE_SECRETS:-/workspace}/.proxy_state}" ]; then
        _ps="$(tr -d '[:space:]' < "${PROXY_STATE_FILE:-${WORKSPACE_SECRETS:-/workspace}/.proxy_state}" 2>/dev/null || true)"
    fi
    echo "Term proxy: ${_ps:-off}  (proxy_on/off -> ${PROXY_STATE_FILE:-${WORKSPACE_SECRETS:-/workspace}/.proxy_state})"
    unset _ps
    echo "------------------------------"
}

# 从本机 SSH 进容器（在容器内执行时提示用宿主机 IP）
ssh_hint() {
    container_info
}
