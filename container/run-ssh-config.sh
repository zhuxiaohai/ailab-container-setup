#!/usr/bin/env bash
# 加载 config.local.env 后执行 ssh-config-auto.py（与手动跑范例脚本等价）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/../lib/common.sh"
CONTAINER_IP="${CONTAINER_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
SSH_PORT="$(resolve_ssh_port "${CONTAINER_IP}")"
export CONTAINER_IP SSH_PORT CONTAINER_ENV_FILE WORKSPACE_SECRETS CONTAINER_SETUP_ROOT
export ROOT_PASSWORD REDIRECT_PYTHON
exec python3 "${SCRIPT_DIR}/ssh-config-auto.py"
