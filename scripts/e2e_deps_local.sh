#!/usr/bin/env bash
# 单机 e2e：使用 --filter-prefix /lib 指定依赖目录，无需 Lustre /vol8，在无共享存储环境下即可跑通依赖分发测试。
#
# 单机多 agent 场景：
#   - 每个 agent 监听不同端口（19951/19952/19953）
#   - 每个 agent 用 --dest-override 指定自己的本地存储目录，互不覆盖
#   - 节点列表使用 "host:port" 格式让端口随协议流转，无需环境变量
#
# 生产环境示例：
#   - 所有节点监听同一端口：--nodes "cn[1-100]" --port 2007
#   - 每台节点用自己的 --dest-override /local/deps 启动 agent
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_TRANS="${ROOT_DIR}/bin/trans-tools"
BIN_AGENT="${ROOT_DIR}/bin/agent"

if [[ $# -lt 2 ]]; then
  echo "用法: $0 /path/to/program \"cn[1-3]\""
  echo "  （节点列表支持 nodeset 表达式或 host:port 格式，如 \"cn1:19951,cn2:19952,cn3:19953\"）"
  exit 2
fi

PROGRAM="$1"
NODES_EXPR="$2"

PORT_CN1=19951
PORT_CN2=19952
PORT_CN3=19953

if [[ ! -x "${BIN_TRANS}" || ! -x "${BIN_AGENT}" ]]; then
  echo "请先构建二进制: go build -o bin/trans-tools ./cmd/trans-tools && go build -o bin/agent ./cmd/agent"
  exit 1
fi

echo "== 启动本地 agent 进程（每节点不同端口 + 不同 dest） =="
PIDS=()
for node in cn1 cn2 cn3; do
  TMP_NAME="deps-${node}"
  DEST_DIR="/tmp/recv-${node}"   # 每个 agent 独立的落盘目录，方便验证
  case "${node}" in
    cn1) PORT="${PORT_CN1}" ;;
    cn2) PORT="${PORT_CN2}" ;;
    cn3) PORT="${PORT_CN3}" ;;
    *)   PORT=2007 ;;
  esac
  echo "  agent ${node}: port=${PORT}  dest-override=${DEST_DIR}"
  "${BIN_AGENT}" \
    -tmp-name "${TMP_NAME}" \
    -port "${PORT}" \
    -dest-override "${DEST_DIR}" \
    --insecure > /tmp/agent-${node}.log 2>&1 &
  PIDS+=("$!")
done

cleanup() {
  echo
  echo "== 停止 agent 进程 =="
  for pid in "${PIDS[@]}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" || true
    fi
  done
}
trap cleanup EXIT

sleep 2

# 单机测试使用 localhost，端口区分不同 agent 实例
NODES_WITH_PORTS="localhost:${PORT_CN1},localhost:${PORT_CN2},localhost:${PORT_CN3}"

echo
echo "== 运行 deps 分发命令（节点列表: ${NODES_WITH_PORTS}） =="
set +e
"${BIN_TRANS}" deps \
  --program "${PROGRAM}" \
  --nodes "${NODES_WITH_PORTS}" \
  --width 2 \
  --buffer 2M \
  --dest /tmp/dependencies \
  --min-size-mb 1 \
  --filter-prefix /lib \
  --insecure
STATUS=$?
set -e

echo
echo "== 验证每个 agent 的接收目录（各自独立，不互相覆盖） =="
for node in cn1 cn2 cn3; do
  RECV_DIR="/tmp/recv-${node}"
  echo "  ${node} (${RECV_DIR}):"
  if ls -lh "${RECV_DIR}" 2>/dev/null | grep -v '^total 0$' | grep -v '^$'; then
    :
  else
    echo "    (空或不存在)"
  fi
done

echo
echo "== agent 日志（最后 5 行） =="
for node in cn1 cn2 cn3; do
  echo "  --- agent-${node}.log ---"
  tail -5 /tmp/agent-${node}.log 2>/dev/null || echo "    (无日志)"
done

if [[ ${STATUS} -ne 0 ]]; then
  echo "deps 命令返回非 0 状态: ${STATUS}"
  exit "${STATUS}"
fi

echo
echo "本地端到端依赖分发测试完成。"
