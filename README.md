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
./bin/agent -port 1995
```

测试环境可使用不安全模式：

```bash
./bin/agent -port 1995 --insecure
```

### 执行依赖分发（deps）

```bash
./bin/trans-tools deps \
  --program /abs/path/to/program \
  --nodes "cn[1-3]" \
  --port 1995 \
  --width 50 \
  --buffer 2M \
  --dest /tmp/dependencies \
  --min-size-mb 10 \
  --filter-prefix "/vol8"
```

运行前请确保目标节点上已启动 `agent` 并监听对应端口（默认 `1995`）。

常用变体：

- **关闭目录筛选（使用全部依赖）**：`--filter-prefix ""`
- **单机环境（不需要 /vol8），只发 /lib 与 /usr/lib 的依赖**：`--filter-prefix "/lib,/usr/lib"`
- **测试用关闭 TLS**：在 `deps` 与 `agent` 两端都加 `--insecure`

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
│   └── agent/                # gRPC 接收端 agent
├── internal/                 # 私有实现（deps / distree / version 等）
├── pkg/                      # 可复用包（例如 nodeset 表达式解析）
├── scripts/                  # e2e 脚本与辅助脚本
├── Makefile
└── README.md
```

## 环境要求

- Go 1.21+
