#!/usr/bin/env bash
# 非交互安装 Clash（基于 xcjs 官方 linux_script.sh 流程，容器适配版）
# 参考: https://www.xcjs123.com/user/help/linux
# 用法:
#   事先配置 config.local.env（CLASH_SUBLINK、CLASH_DOWNLOAD_BASE）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/common.sh"
CLASH_BIN="${CLASH_BIN:-/usr/local/clash}"
CLASH_PORT="${CLASH_PORT:-7890}"
CONTAINER_SCRIPT="${SCRIPT_DIR}/clash/linux_script.container.sh"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

log() { echo -e "${green}==>${plain} $*"; }
warn() { echo -e "${yellow}==>${plain} $*"; }
die() { echo -e "${red}ERROR:${plain} $*" >&2; exit 1; }

is_container() {
    [ -f /.dockerenv ] || grep -Eq '(docker|containerd|lxc|kubepods)' /proc/1/cgroup 2>/dev/null
}

sudo() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else command sudo "$@"; fi
}

detect_arch() {
    local arch
    arch="$(arch)"
    case "$arch" in
        x86_64|x64|amd64) echo amd64 ;;
        aarch64|arm64) echo arm64 ;;
        i686|i386) echo 386 ;;
        *) echo amd64 ;;
    esac
}

clash_run_wanted() {
    [ -x "${CLASH_BIN}" ] || return 1
    [ -f "${CLASH_DIR}/config.yaml" ] || return 1
    case "$(cat "${CLASH_RUN_STATE_FILE}" 2>/dev/null | tr -d '[:space:]')" in
        off) return 1 ;;
        *) return 0 ;;
    esac
}

set_clash_run_state() {
    echo "$1" | sudo tee "${CLASH_RUN_STATE_FILE}" > /dev/null
}

setup_autostart() {
    local hook="/etc/profile.d/clash-autostart.sh"
    sudo tee "$hook" > /dev/null << EOF
# Clash autostart for container (respects ${CLASH_RUN_STATE_FILE}: on|off)
_clash_run_wanted() {
    [ -x ${CLASH_BIN} ] || return 1
    [ -f ${CLASH_DIR}/config.yaml ] || return 1
    case "\$(cat ${CLASH_RUN_STATE_FILE} 2>/dev/null | tr -d '[:space:]')" in
        off) return 1 ;;
        *) return 0 ;;
    esac
}
_clash_autostart() {
    _clash_run_wanted || return
    pgrep -f "${CLASH_BIN}.*-d.*${CLASH_DIR}" >/dev/null 2>&1 && return
    setsid ${CLASH_BIN} -d ${CLASH_DIR} >> /dev/null 2>&1 &
}
_clash_autostart
unset -f _clash_run_wanted _clash_autostart
EOF
    sudo chmod 644 "$hook"
    sudo touch "${CLASH_DIR}/.container_mode"
    if [ ! -f "${CLASH_RUN_STATE_FILE}" ]; then
        if pgrep -f "${CLASH_BIN}.*-d.*${CLASH_DIR}" >/dev/null 2>&1; then
            set_clash_run_state on
        else
            set_clash_run_state off
        fi
    fi
}

read_sublink() {
    read_clash_sublink && return 0
    if [ -f "${CLASH_DIR}/.sublink" ]; then
        cat "${CLASH_DIR}/.sublink"
        return 0
    fi
    return 1
}

read_download_base() {
    read_clash_download_base && return 0
    return 1
}

install_clash_binary() {
    local cpu_arch="$1"
    local base="$2"
    local url
    if [ "$cpu_arch" = "arm64" ]; then
        url="${base}/app-download/AppForLinuxArm64.gz"
    else
        url="${base}/app-download/AppForLinux.gz"
    fi
    log "下载 Clash (${cpu_arch})..."
    sudo wget --no-check-certificate -O "${CLASH_BIN}.gz" "$url" || die "下载 clash 失败，请检查网络或订阅服务"
    sudo rm -f "${CLASH_BIN}"
    sudo gzip -d "${CLASH_BIN}.gz"
    sudo chmod +x "${CLASH_BIN}"
}

download_mmdb() {
    local base="$1"
    log "下载 Country.mmdb..."
    sudo wget -q -O "${CLASH_DIR}/Country.mmdb" "${base}/app-download/Country.mmdb" || warn "mmdb 下载失败（可稍后重试）"
}

import_sublink() {
    local sublink="$1"
    sudo wget -q -O "${CLASH_DIR}/config.yaml" "$sublink" || die "导入订阅失败"
    echo "$sublink" | sudo tee "${CLASH_DIR}/.sublink" > /dev/null
    sudo sh -c "echo $(date +%s) > ${CLASH_DIR}/.last_update_node"
    setup_autostart
    set_clash_run_state on
    log "订阅导入成功"
}

run_clash() {
    set_clash_run_state on
    setsid "${CLASH_BIN}" -d "${CLASH_DIR}" >> /dev/null 2>&1 &
    sleep 1
    if pgrep -f "${CLASH_BIN}.*-d.*${CLASH_DIR}" >/dev/null 2>&1; then
        log "Clash 已启动，端口 ${CLASH_PORT}"
    else
        die "Clash 启动失败"
    fi
}

install_management_script() {
    if [ -f "$CONTAINER_SCRIPT" ]; then
        sudo mkdir -p "${CLASH_DIR}"
        sudo cp -f "$CONTAINER_SCRIPT" "${CLASH_DIR}/linux_script.sh"
        sudo chmod +x "${CLASH_DIR}/linux_script.sh"
        if ! grep -q 'alias xcjs=' ~/.bashrc 2>/dev/null; then
            echo 'alias xcjs="/etc/clash/linux_script.sh"' >> ~/.bashrc
        fi
        log "已安装管理脚本: xcjs"
    fi
}

main() {
    is_container || warn "未检测到容器环境，部分自启逻辑可能不适用"

    if [ -x "${CLASH_BIN}" ] && [ -f "${CLASH_DIR}/config.yaml" ]; then
        setup_autostart
        install_management_script
        if clash_run_wanted; then
            log "Clash 已安装，按状态启动..."
            run_clash
        else
            log "Clash 已安装，保持停止（${CLASH_RUN_STATE_FILE}=off）"
        fi
        exit 0
    fi

    local sublink base arch
    sublink="$(read_sublink)" || die "请在 config.local.env 设置 CLASH_SUBLINK（已安装过则可从 /etc/clash/.sublink 读取）"
    base="$(read_download_base)" || die "请在 config.local.env 设置 CLASH_DOWNLOAD_BASE，或已有 ${CLASH_DIR}/.downloadlink"
    arch="$(detect_arch)"

    log "安装依赖..."
    if command -v apt >/dev/null 2>&1; then
        sudo apt-get update -qq
        sudo apt-get install -y gzip wget
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y gzip wget
    else
        die "未找到 apt/yum"
    fi

    sudo mkdir -p "${CLASH_DIR}"
    echo "$base" | sudo tee "${CLASH_DIR}/.downloadlink" > /dev/null

    install_clash_binary "$arch" "$base"
    download_mmdb "$base"
    import_sublink "$sublink"
    install_management_script
    run_clash

    echo ""
    log "完成。终端代理: proxy_on / proxy_off；管理菜单: xcjs"
}

main "$@"
