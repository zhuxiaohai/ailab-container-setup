# 终端代理（与 xcjs 官网一致）：
#   HTTP/HTTPS  127.0.0.1:7890
#   FTP         关闭（端口 0）
#   SOCKS       127.0.0.1:7890
#   忽略主机    localhost,127.0.0.0/8,::1
# 容器内无本机 Clash 时，HTTP/HTTPS/SOCKS 主机可改为 host.docker.internal
#
# 持久化：${WORKSPACE_SECRETS}/.proxy_state (on|off)
#   proxy_on / proxy_off 会写入；exit、SSH 断开、再次 exec/ssh 进容器后，交互 shell 自动恢复
declare -f proxy_on >/dev/null 2>&1 && return

CLASH_PORT="${CLASH_PORT:-7890}"
PROXY_STATE_FILE="${PROXY_STATE_FILE:-${WORKSPACE_SECRETS:-/workspace}/.proxy_state}"

if [ -x /usr/local/clash ] && [ -f /etc/clash/config.yaml ]; then
    CLASH_HOST="${CLASH_HOST:-127.0.0.1}"
else
    CLASH_HOST="${CLASH_HOST:-host.docker.internal}"
fi

_PROXY="http://${CLASH_HOST}:${CLASH_PORT}"
_SOCKS="socks5://${CLASH_HOST}:${CLASH_PORT}"
_NO_PROXY="localhost,127.0.0.0/8,::1"

_proxy_save_state() {
    local state="$1"
    echo "$state" > "${PROXY_STATE_FILE}" 2>/dev/null || return 1
    chmod 600 "${PROXY_STATE_FILE}" 2>/dev/null || true
}

_proxy_read_state() {
    if [ ! -f "${PROXY_STATE_FILE}" ]; then
        return 0
    fi
    tr -d '[:space:]' < "${PROXY_STATE_FILE}" 2>/dev/null || true
}

_proxy_apply_exports() {
    export http_proxy="$_PROXY" https_proxy="$_PROXY"
    export HTTP_PROXY="$_PROXY" HTTPS_PROXY="$_PROXY"
    export socks_proxy="$_SOCKS" SOCKS_PROXY="$_SOCKS"
    export no_proxy="$_NO_PROXY" NO_PROXY="$_NO_PROXY"
    unset ftp_proxy FTP_PROXY
}

proxy_on() {
    _proxy_apply_exports
    _proxy_save_state on
    echo "[proxy on]  HTTP/HTTPS=${_PROXY}  SOCKS=${_SOCKS}  FTP=off  NO_PROXY=${_NO_PROXY}  (saved)"
}

proxy_off() {
    unset http_proxy https_proxy ftp_proxy socks_proxy
    unset HTTP_PROXY HTTPS_PROXY FTP_PROXY SOCKS_PROXY
    unset no_proxy NO_PROXY
    _proxy_save_state off
    echo "[proxy off] -> direct connection (saved)"
}

proxy_status() {
    local saved
    saved="$(_proxy_read_state)"
    if [ -n "${http_proxy}${https_proxy}${HTTP_PROXY}${HTTPS_PROXY}" ]; then
        echo "proxy: ON (${CLASH_HOST}:${CLASH_PORT})  persisted=${saved:-unknown}"
        env | grep -iE '^(https?|ftp|socks|no)_proxy=' | sort
    else
        echo "proxy: OFF  persisted=${saved:-off}"
    fi
}

# Clash 已安装且 .run_state 非 off 时，交互 shell 自动拉起（与 xcjs 停止状态一致）
if [ -x /usr/local/clash ] && [ -f /etc/clash/config.yaml ]; then
    _clash_run_state="$(cat "${CLASH_RUN_STATE_FILE:-/etc/clash/.run_state}" 2>/dev/null | tr -d '[:space:]')"
    if [ "$_clash_run_state" != "off" ] && ! pgrep -f "/usr/local/clash.*-d.*/etc/clash" >/dev/null 2>&1; then
        setsid /usr/local/clash -d /etc/clash >>/dev/null 2>&1 &
    fi
    unset _clash_run_state
fi

# 交互 shell：按 .proxy_state 恢复终端代理（非交互命令不受影响）
case $- in
    *i*)
        if [ "$(_proxy_read_state)" = "on" ]; then
            _proxy_apply_exports
        fi
        ;;
esac
