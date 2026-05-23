"""与 lib/load-config.sh 相同优先级：CLI > config.local.env > config.defaults.env"""
from __future__ import annotations

import os
from typing import Dict


def _parse_env_file(path: str) -> Dict[str, str]:
    out: Dict[str, str] = {}
    if not os.path.isfile(path):
        return out
    with open(path, encoding="utf-8", errors="ignore") as f:
        for raw in f:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            if line.startswith("export "):
                line = line[7:].strip()
            if "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            val = val.strip().strip('"').strip("'")
            if key:
                out[key] = val
    return out


def load_repo_config(repo_root: str | None = None) -> None:
    root = (repo_root or os.environ.get("CONTAINER_SETUP_ROOT", "/workspace/ailab-container-setup")).strip()
    defaults = _parse_env_file(os.path.join(root, "config.defaults.env"))
    local = _parse_env_file(os.path.join(root, "config.local.env"))
    all_keys = set(defaults) | set(local)
    cli = {k: os.environ[k] for k in all_keys if k in os.environ}
    merged = {**defaults, **local}
    for key, val in merged.items():
        if key not in cli:
            os.environ[key] = val
    for key, val in cli.items():
        os.environ[key] = val
