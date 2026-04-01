# trans-tools

`trans-tools` 是一个 Go 工具集，目前核心提供 **程序依赖分析 + 多节点树形分发**（`deps` 子命令），并配套一个在各节点上运行的 **接收端 gRPC agent**（`cmd/agent`）。

## 核心功能

- **依赖分析**：输入一个可执行文件路径（`--program`），扫描其依赖文件并按最小大小阈值过滤（`--min-size-mb`）。
- **依赖筛选**：可按挂载目录前缀筛选依赖（`--filter-prefix`，逗号分隔多个目录；为空表示不筛选）。
- **按目录打包**：将依赖按目录分组并分别打 tar 包。
- **树形分发**：通过 DistTree 方式将 tar 包分发到目标节点（`--nodes` + `--width`），支持配置 payload 大小（`--buffer`）。
- **落盘目录**：接收端将内容落盘到 `--dest`（客户端请求），或由 agent 使用 `--dest-override` 强制覆盖落到本地指定目录。
- **测试用不安全模式**：`--insecure` 关闭 TLS/认证（仅用于测试环境）。

## 快速开始

### 构建

```bash
make build
go build -o bin/agent ./cmd/agent
```

### 查看版本

```bash
./bin/trans-tools -version
```

### 启动 agent（每台目标机都要运行）

```bash
./bin/agent -port 2007
```

测试环境可使用不安全模式：

```bash
./bin/agent -port 2007 --insecure
```

### 执行依赖分发（deps）

```bash
./bin/trans-tools deps \
  --program /abs/path/to/program \
  --nodes "cn[1-3]" \
  --port 2007 \
  --width 50 \
  --buffer 2M \
  --dest /tmp/dependencies \
  --min-size-mb 10 \
  --filter-prefix "/vol8"
```

运行前请确保目标节点上已启动 `agent` 并监听对应端口（默认 `2007`）。

常用变体：

- **关闭目录筛选（使用全部依赖）**：`--filter-prefix ""`
- **单机环境（不需要 /vol8），只发 /lib 与 /usr/lib 的依赖**：`--filter-prefix "/lib,/usr/lib"`
- **测试用关闭 TLS**：在 `deps` 与 `agent` 两端都加 `--insecure`

## 工具参数用法

### `trans-tools`

- `-version`：输出版本、构建时间、commit 信息。

示例：

```bash
./bin/trans-tools -version
```

### `trans-tools deps`

- `--program`：必填，待分析程序的绝对路径。
- `--nodes`：必填，目标节点列表。支持 nodeset（如 `cn[1-3]`）或 `host:port` 列表。
- `--min-size-mb`：依赖文件最小大小阈值（MB），默认 `10`。
- `--port`：目标 agent 监听端口，默认 `2007`（当 `--nodes` 使用 `host:port` 时以节点内端口为准）。
- `--buffer`：单次发送 payload 大小，默认 `2M`（如 `512k`、`1M`、`2M`）。
- `--width`：树形分发宽度，默认 `50`。
- `--dest`：远端依赖落盘目录，默认 `/tmp/dependencies`。
- `--filter-prefix`：依赖目录前缀过滤，默认 `/vol8`；多个目录用逗号分隔；空字符串表示不过滤。
- `--auto-clean`：是否自动删除本地临时 tar 包，默认 `true`。
- `--insecure`：关闭 TLS/认证（仅测试环境）。

示例（生产常见）：

```bash
./bin/trans-tools deps \
  --program /opt/app/bin/myprog \
  --nodes "cn[1-100]" \
  --port 2007 \
  --width 50 \
  --buffer 2M \
  --dest /local/dependencies \
  --min-size-mb 10 \
  --filter-prefix "/vol8"
```

示例（单机/测试常见）：

```bash
./bin/trans-tools deps \
  --program /usr/bin/python3 \
  --nodes "cn1:19951,cn2:19952,cn3:19953" \
  --width 2 \
  --buffer 2M \
  --dest /tmp/dependencies \
  --min-size-mb 1 \
  --filter-prefix "/lib,/usr/lib" \
  --insecure
```

### `agent`

- `-port`：gRPC 监听端口，默认 `2007`。
- `-tmp-name`：临时目录名（实际路径 `/tmp/<tmp-name>`），默认 `trans-tools-agent`。
- `-dest-override`：强制覆盖客户端请求的 `dest_dir`，统一落盘到本地指定目录（可选）。
- `--insecure`：关闭 TLS（仅测试环境）。

示例：

```bash
./bin/agent -port 2007 -tmp-name deps-cn1 -dest-override /local/dependencies
```

### `wrappersrun` (script)

Use `scripts/wrappersrun.sh` to keep the same `srun` usage while running fixed `trans-tools deps` first, then `srun`.

```bash
scripts/wrappersrun.sh -N 2 -n 64 /path/to/your_prog --arg1 x
```

Fixed deps parameters can be configured by environment variables:

```bash
export WRAPPERSRUN_DEPS_NODES='cn[1-32]'          # or rely on SLURM_* env, or `srun -w` / `--nodelist` parsed from args
export WRAPPERSRUN_DEPS_DEST='/tmp/dependencies'
export WRAPPERSRUN_DEPS_FILTER_PREFIX='/vol8'
export WRAPPERSRUN_DEPS_PORT='2007'
export WRAPPERSRUN_DEPS_WIDTH='50'
export WRAPPERSRUN_DEPS_BUFFER='2M'
export WRAPPERSRUN_DEPS_MIN_SIZE_MB='10'
scripts/wrappersrun.sh -N 2 -n 64 /path/to/your_prog
```

### Slurm Prolog / Epilog (`dependency_mount_fakefs.sh`)

Use `scripts/dependency_mount_fakefs.sh` as **Prolog** and `scripts/dependency_mount_cleanup_fakefs.sh` as **Epilog** so per-job dependencies are mounted and torn down on compute nodes.

Example `slurm.conf` snippets (paths must exist and be executable on compute nodes):

```ini
Prolog=/shared/trans-tools/scripts/dependency_mount_fakefs.sh
Epilog=/shared/trans-tools/scripts/dependency_mount_cleanup_fakefs.sh
```

Behavior when **`SLURM_JOB_ID` is set** (normal Prolog/Epilog): scripts **exit 0** even if mounts, cleanup, or strict checks fail, so Slurm does not drain the node solely because of hook exit status. Failures are written to **`${DEPENDENCY_STORAGE_DIR:-/tmp/dependencies}/hook-errors.log`** (and to syslog via `logger -t slurm-fakefs-hook` when available).

- Override dependency directory for Slurm jobs: set **`DEPENDENCY_STORAGE_DIR`** in the job environment or Prolog wrapper.
- Force strict non-zero exits under Slurm (debug only): **`SLURM_HOOK_SOFT_FAIL=0`**.
- Force soft-fail without `SLURM_JOB_ID` (e.g. tests): **`SLURM_HOOK_SOFT_FAIL=1`**.

Regression check:

```bash
bash scripts/slurm_fakefs_hook_soft_fail_test.sh
```

## 测试脚本

### 单机端到端（不依赖 /vol8 / Lustre）

脚本 `scripts/e2e_deps_local.sh` 会在本机启动 3 个 agent（不同端口、不同 `--dest-override`），并用 `deps --filter-prefix /lib` 跑通依赖分发链路。

```bash
make build
go build -o bin/agent ./cmd/agent

bash scripts/e2e_deps_local.sh /abs/path/to/program "cn[1-3]"
```

说明：

- `--nodes` 支持 nodeset 表达式（如 `cn[1-3]`），也支持 `host:port` 列表（如 `cn1:19951,cn2:19952,cn3:19953`），用于本地多端口模拟。
- 脚本会把 agent 日志写到 `/tmp/agent-cn*.log`，接收目录为 `/tmp/recv-cn*`，方便核对。

## 常用命令

```bash
make build
make test
make fmt
make lint
```

## 目录结构

```
trans-tools/
├── cmd/
│   ├── trans-tools/          # CLI（deps 子命令）
│   ├── agent/                # gRPC 接收端 agent
│   └── wrappersrun/          # srun wrapper binary
├── internal/                 # 私有实现（deps / distree / version 等）
├── pkg/                      # 可复用包（例如 nodeset 表达式解析）
├── scripts/                  # e2e and wrapper scripts
├── Makefile
└── README.md
```

## 环境要求

- Go 1.21+
