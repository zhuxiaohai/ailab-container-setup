#!/usr/bin/env python3
"""
非交互版 ssh-jupyter-config2.py（仅 SSH，无 Jupyter）
配置优先级: 命令行 export > config.local.env > config.defaults.env
"""
import os
import random
import sys

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.dirname(_SCRIPT_DIR)
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, os.path.join(_REPO_ROOT, "lib"))

from load_config import load_repo_config  # noqa: E402

load_repo_config(os.environ.get("CONTAINER_SETUP_ROOT", _REPO_ROOT))


def run(cmd: str) -> None:
    print(f"[run] {cmd}")
    os.system(cmd)


def random_password(n: int = 6) -> str:
    chars = [chr(i) for i in range(48, 58)] + [chr(i) for i in range(97, 123)]
    return "".join(random.sample(chars, n))


def main() -> int:
    password = os.environ.get("ROOT_PASSWORD", "").strip() or random_password(6)
    ssh_port = os.environ.get("SSH_PORT", "22").strip() or "22"
    redirect = os.environ.get("REDIRECT_PYTHON", "").strip().lower()

    run("apt update")
    run("apt install net-tools -y")
    run("apt install openssh-server -y")
    run(f'echo "root:{password}" | chpasswd')
    run(f'echo "Port {ssh_port}" >> /etc/ssh/sshd_config')
    run('echo "PermitRootLogin yes" >> /etc/ssh/sshd_config')
    run("service ssh restart")

    if redirect in ("y", "yes"):
        if os.path.exists("/opt/conda/bin/python3") and os.path.exists("/opt/conda/bin/pip3"):
            run("rm -f /usr/bin/python3 /usr/bin/pip3")
            run("ln -s /opt/conda/bin/python3 /usr/bin/python3")
            run("ln -s /opt/conda/bin/pip3 /usr/bin/pip3")
            run('echo \'export PATH="/opt/conda/bin/:$PATH"\' >> ~/.bashrc')
        else:
            print("WARN: /opt/conda/bin/python3 or pip3 not found, skip redirect")

    env_file = os.environ.get("CONTAINER_ENV_FILE", "/workspace/.container.env").strip()
    ip = os.environ.get("CONTAINER_IP", "")
    with open(env_file, "w", encoding="utf-8") as f:
        f.write(f"CONTAINER_IP={ip}\n")
        f.write(f"SSH_PORT={ssh_port}\n")
        f.write(f"ROOT_PASSWORD={password}\n")
    os.chmod(env_file, 0o600)

    print("\n======== Configuration succeeded ========")
    print(f"ssh port: {ssh_port}")
    print(f"ssh password: {password}")
    if ip:
        print(f"ssh: ssh root@{ip} -p {ssh_port}")
    print(f"env file: {env_file}")
    print("=========================================\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
