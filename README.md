# ailab-container-setup

GPU 实验容器的自动化搭建：Docker 固定 IP 启动、SSH、xcjs Clash 代理、bashrc 端口与代理管理。

支持两种用法：

| 方式 | 适用场景 |
|------|----------|
| [方式一：完全脱手](#方式一完全脱手一键) | 宿主机一条命令起容器并完成 SSH / Clash / bashrc |
| [方式二：先建容器再手动配](#方式二先建容器再手动配置) | 只要空容器或 `docker exec` 进来，SSH、代理、端口自己按需装 |

---

## 前置准备（两种方式共用）

### 1. 克隆仓库到 workspace 卷

宿主机或容器内均可（容器内路径一般为 `/workspace/ailab-container-setup`）：

```bash
cd /workspace
git clone <你的远程仓库地址> ailab-container-setup
cd ailab-container-setup
```

### 2. 本环境配置（推荐，勿提交 Git）

所有会因环境变化的项（挂载路径、Clash 订阅/下载节点、SSH 密码、端口等）集中在 **`config.local.env`**，无需每次 `export`。

```bash
cd ailab-container-setup
cp config.local.env.example config.local.env
# 编辑 config.local.env，至少填写：
#   CLASH_SUBLINK、CLASH_DOWNLOAD_BASE
#   VOL_*_HOST、DOCKER_NETWORK（宿主机 launch 时）
#   ROOT_PASSWORD、SSH_PORT 等（按需）
```

加载顺序（`lib/load-config.sh` / `lib/load_config.py`，由 `common.sh` 与各入口统一执行）：

1. `config.defaults.env` — 最低优先级
2. `config.local.env` — 覆盖 defaults（**已 gitignore**）
3. 命令行在启动脚本**之前**已 `export` 的变量 — 最高优先级（例如 `AUTO_SSH=0 ./setup-inside-container.sh`、`ROOT_PASSWORD=xxx ./container/run-ssh-config.sh`）

配置文件使用 `KEY=value` 行格式（不要用 `source` 解析，避免与命令行冲突）。

**宿主机**跑 `setup_container.sh launch` 时，请在**宿主机仓库目录**有一份 `config.local.env`；若仓库在 `/workspace` 卷上，容器内同路径也有一份，两边一致即可。

### 3. 配置项速查（写在 `config.local.env`）

| 变量 | 说明 |
|------|------|
| `CLASH_SUBLINK` | xcjs Clash 订阅链接（一行） |
| `CLASH_DOWNLOAD_BASE` | xcjs 下载节点基址 |
| `DOCKER_NETWORK`、`VOL_*_HOST` | 宿主机 `docker run` 网络与 3 个默认卷 |
| `DOCKER_EXTRA_VOLUMES` | 额外挂载，一行、分号分隔 `host:container`（如 SSD `/fast`） |
| `config.extra-volumes` | 可选列表文件，每行一条 `host:container`（见 `config.extra-volumes.example`） |
| `SSH_PORT` | 默认 `22`；写死则固定端口，不随 IP 推算 |
| `SSH_PORT_BASE` | 仅当 `SSH_PORT` 留空时：端口 = 基数 + IP 末段 |
| `CONTAINER_IP` | `launch` 会把命令行里的 `<ip>` 传入容器；留空则容器内自动检测 |
| `ROOT_PASSWORD` | root 密码（空则随机） |
| `CONTAINER_ENV_FILE`、`PROXY_STATE_FILE`、`CLASH_RUN_STATE_FILE` | 状态文件路径 |
| `AUTO_SSH`、`AUTO_CLASH` | 是否自动配 SSH / 装 Clash |

完整模板与注释见 `config.local.env.example`。

---

## 方式一：完全脱手（一键）

宿主机执行，自动完成：`docker run` → 容器内 **SSH** → **Clash**（有订阅时）→ **bashrc**（`proxy_on` / `container_info`）。

```bash
cd /path/to/ailab-container-setup   # 宿主机上的仓库路径
cp config.local.env.example config.local.env   # 首次：编辑好 CLASH_*、VOL_* 等

./setup_container.sh launch \
  hub.designorder.cn/verlai/verl:vllm017.latest \
  zhuxiaohai_llm_test \
  10.20.20.53
```

结束后宿主机会打印 SSH 命令；密码在容器内：

```bash
docker exec zhuxiaohai_llm_test cat /workspace/.container.env
```

### 已有容器，只补跑自动化配置

不重建容器，在容器内再执行一遍 `setup-inside-container.sh`：

```bash
./setup_container.sh configure zhuxiaohai_llm_test
# 或兼容写法：./setup_container.sh zhuxiaohai_llm_test
```

### 容器内日常使用

```bash
docker exec -it <容器名> bash
container_info
proxy_on       # 终端走代理，并写入 /workspace/.proxy_state=on
proxy_off      # 关闭并持久为 off
proxy_status
xcjs           # Clash 菜单：启停、换节点、更新订阅
```

### 只起容器、不要自动配置

```bash
SKIP_SETUP=1 ./setup_container.sh launch <image> <name> <ip>
```

之后按 [方式二](#方式二先建容器再手动配置) 在容器内自行安装。

---

## 方式二：先建容器，再手动配置

适合：镜像/容器已存在、只想 `docker exec` 进来、或 SSH / Clash / 代理要分开、分步安装。

### 步骤 0：创建容器（宿主机）

**A. 用本仓库脚本，但跳过容器内 setup**

```bash
SKIP_SETUP=1 ./setup_container.sh launch <image> <name> <ip>
```

**B. 自己 `docker run`**

保证挂载 workspace（以便访问 `/workspace/ailab-container-setup` 与 `config.local.env`），网络与 IP 按你环境配置即可。若需与 `launch` 相同的额外 SSD 等挂载，自行追加与 `config.extra-volumes` / `DOCKER_EXTRA_VOLUMES` 一致的 `-v` 参数。

### 额外挂载卷（任意多条）

默认仍有 3 个 NFS 卷（`VOL_*`）。本地 SSD 等可再加任意多条，二选一或组合：

**方式 A — `config.local.env` 一行（分号分隔）**

```bash
DOCKER_EXTRA_VOLUMES="/mnt/local_ssd_550/zhuxiaohai:/fast;/other/host/path:/other/ctr"
```

**方式 B — 列表文件（推荐多条时）**

```bash
cp config.extra-volumes.example config.extra-volumes
# 编辑，每行 host:container，例如：
# /mnt/local_ssd_550/zhuxiaohai:/fast
```

`launch-container.sh` 会在 3 个默认卷之后追加这些 `-v`。建议只挂个人子目录（如 `.../zhuxiaohai` → `/fast`），不要挂整盘 `local_ssd_550`（避免把宿主机 `dockers2` 暴露进容器）。

### 步骤 1：进入容器

```bash
docker exec -it <容器名> bash
```

确认仓库在卷上：

```bash
ls /workspace/ailab-container-setup/install-clash.sh
```

### 步骤 2：配置 SSH（端口 + root 密码）

先在 `config.local.env` 里写好 **`ROOT_PASSWORD`**、**`SSH_PORT`**（默认 22），然后：

```bash
cd /workspace/ailab-container-setup
./container/run-ssh-config.sh
```

脚本会加载 `config.local.env`；直接跑 `python3 container/ssh-config-auto.py` 也会自动读该文件。

```bash
cat /workspace/.container.env
```

若密码不对：多半是未读到 `config.local.env`（请用 `./container/run-ssh-config.sh`，或确认 `config.local.env` 在仓库根目录且含 `ROOT_PASSWORD=...`）。

#### 可选：宿主机 SSH 免密登录

```bash
ssh-copy-id -p 22 root@<容器IP>
```

### 步骤 3：安装 Clash（xcjs）

`config.local.env` 中配置好 **`CLASH_SUBLINK`**、**`CLASH_DOWNLOAD_BASE`** 后：

```bash
cd /workspace/ailab-container-setup
bash install-clash.sh
```

检查：`pgrep -af clash`；管理菜单：`xcjs`。

### 步骤 4：配置 bashrc（`proxy_on`，不重复装 SSH/Clash）

```bash
cd /workspace/ailab-container-setup
AUTO_SSH=0 AUTO_CLASH=0 bash setup-inside-container.sh
source ~/.bashrc
```

应看到 **跳过 SSH**、**跳过 Clash**，只配置 `~/.bashrc`。

### 步骤 5：手动开启终端代理（与官网端口一致）

Clash 监听一般为 **7890**（以订阅 `config.yaml` 为准）。终端代理与 Clash 进程**分开**持久化：

```bash
source ~/.bashrc    # 若未加载 proxy 函数
proxy_on            # 写入 /workspace/.proxy_state=on，并按官网参数 export
proxy_status
```

官网对应关系（本仓库 `proxy_on` 已对齐）：

| 项 | 值 |
|----|-----|
| HTTP / HTTPS | `http://127.0.0.1:7890` |
| FTP | 关闭（不设 `ftp_proxy`） |
| SOCKS | `socks5://127.0.0.1:7890` |
| 忽略主机 | `localhost,127.0.0.0/8,::1` |

改监听端口时：先改 `/etc/clash/config.yaml` 并重启 Clash，再 `export CLASH_PORT=新端口` 后执行 `proxy_on`。

### 方式二推荐顺序小结

```
进容器 → ./container/run-ssh-config.sh（SSH）
      → install-clash.sh（Clash）
      → AUTO_SSH=0 AUTO_CLASH=0 setup-inside-container.sh（bashrc）
      → proxy_on（终端代理，可选）
```

---

## 端口规则

### SSH

`setup_container.sh launch <image> <name> <ip>` 会：

1. `docker run --ip=<ip>` 固定容器 IP  
2. 把 `<ip>` 作为 **`CONTAINER_IP`** 传入 `setup-inside-container.sh`  
3. **`SSH_PORT`**：若在 `config.local.env` 里已设置（默认 **`22`**），则直接用；若**留空**且有 `CONTAINER_IP`，则用 `SSH_PORT_BASE + IP末段`（例：`20000+53=20053`）；否则用 `SSH_FALLBACK_PORT`（默认 22）

多容器各自固定 IP 时，通常 **`SSH_PORT=22`** 即可（容器网络相互独立，端口不冲突）。

### Clash

终端代理默认 `CLASH_PORT=7890`（与订阅 `config.yaml` 监听一致）。

---

## SSH / FileZilla

容器内执行（会读取 `config.local.env` 中的 `ROOT_PASSWORD`、`SSH_PORT`）：

```bash
./container/run-ssh-config.sh
cat /workspace/.container.env
```

---

## 状态持久化（exit / 再 exec / SSH 重连）

| 文件 | 位置 | 含义 |
|------|------|------|
| `.proxy_state` | `/workspace/.proxy_state` | 终端代理 on/off（`proxy_on` / `proxy_off`） |
| `.run_state` | `/etc/clash/.run_state` | Clash 进程 on/off（`xcjs` 启停） |
| `.container.env` | `/workspace/.container.env` | IP、SSH 端口、root 密码 |

- **没有** `.proxy_state`：不报错，默认终端代理 **off**，不自动 `export`。
- `.proxy_state` 在 workspace 卷上，删容器但保留卷时仍可保留；`.run_state` 在容器内 `/etc`，删容器通常会丢。

---

## 目录结构

```
ailab-container-setup/
├── setup_container.sh      # 宿主机入口（launch / configure）
├── launch-container.sh     # docker run + 可选自动 setup
├── setup-inside-container.sh
├── install-clash.sh        # 容器内单独装 Clash
├── config.defaults.env       # 默认值（提交 Git）
├── config.local.env.example  # 复制为 config.local.env 后修改
├── config.local.env          # 本环境配置（gitignore，不提交）
├── config.extra-volumes.example  # 复制为 config.extra-volumes（额外挂载，可选）
├── bashrc/                 # .proxy.bashrc / .container.bashrc
├── clash/                  # 容器适配版 xcjs 脚本
├── container/              # ssh-config-auto.py, run-ssh-config.sh
├── examples/
└── optional/               # 宿主机监控脚本（可选）
```

---

## 环境变量

- **`config.defaults.env`**：仓库内置默认（可提交 Git）
- **`config.local.env`**：本环境实际配置（`cp config.local.env.example config.local.env`，**勿提交**）

所有入口脚本先 `source lib/common.sh`（或 Python 的 `load_repo_config`），自动按上表优先级合并配置；临时覆盖请在命令前 `export VAR=value`。

---

## 推送到远程

```bash
git remote add origin <你的 Git 服务器 URL>
git push -u origin main
```
