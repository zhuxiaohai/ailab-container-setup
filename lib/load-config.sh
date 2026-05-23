# 配置加载（由 lib/common.sh source）
# 优先级（与 README 一致）：
#   1. 命令行已 export 的变量（最高）
#   2. config.local.env
#   3. config.defaults.env（最低）

# shellcheck shell=bash

declare -A CONFIG_CLI=()

_load_config_trim() {
    local s="$1"
    s="${s%%#*}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

_load_config_parse_kv() {
    local line="$1"
    local key="${line%%=*}"
    local val="${line#*=}"
    key="$(_load_config_trim "$key")"
    val="$(_load_config_trim "$val")"
    val="${val%\"}"; val="${val#\"}"
    val="${val%\'}"; val="${val#\'}"
    [[ -z "$key" ]] && return 1
    REPLY_KEY="$key"
    REPLY_VAL="$val"
    return 0
}

_load_config_snapshot_cli() {
    local f line stripped key
    CONFIG_CLI=()
    for f in "${REPO_ROOT}/config.defaults.env" "${REPO_ROOT}/config.local.env"; do
        [[ -f "$f" ]] || continue
        while IFS= read -r line || [[ -n "$line" ]]; do
            stripped="$(_load_config_trim "$line")"
            [[ -z "$stripped" ]] && continue
            [[ "$stripped" == export\ * ]] && stripped="${stripped#export }"
            _load_config_parse_kv "$stripped" || continue
            key="$REPLY_KEY"
            if [[ -v "$key" && -z "${CONFIG_CLI[$key]+x}" ]]; then
                CONFIG_CLI["$key"]="${!key}"
            fi
        done < "$f"
    done
}

_load_config_apply_file() {
    local f="$1" line stripped
    [[ -f "$f" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        stripped="$(_load_config_trim "$line")"
        [[ -z "$stripped" ]] && continue
        [[ "$stripped" == export\ * ]] && stripped="${stripped#export }"
        _load_config_parse_kv "$stripped" || continue
        [[ -n "${CONFIG_CLI[$REPLY_KEY]+x}" ]] && continue
        export "$REPLY_KEY=$REPLY_VAL"
    done < "$f"
}

_load_config_restore_cli() {
    local k
    for k in "${!CONFIG_CLI[@]}"; do
        export "$k=${CONFIG_CLI[$k]}"
    done
}

load_repo_config() {
    _load_config_snapshot_cli
    _load_config_apply_file "${REPO_ROOT}/config.defaults.env"
    _load_config_apply_file "${REPO_ROOT}/config.local.env"
    _load_config_restore_cli
}

# launch/configure：传入容器的环境（运行时 IP + 命令行覆盖项）
config_docker_exec_env() {
    local container_ip="$1" k
    printf 'CONTAINER_SETUP_ROOT=%s\n' "${CONTAINER_SETUP_ROOT}"
    printf 'WORKSPACE_SECRETS=%s\n' "${WORKSPACE_SECRETS}"
    printf 'CONTAINER_IP=%s\n' "${container_ip}"
    for k in "${!CONFIG_CLI[@]}"; do
        printf '%s=%s\n' "$k" "${CONFIG_CLI[$k]}"
    done
}
