#!/usr/bin/env bash
# e2e fault-tolerance test: 10 local agents, one is killed before distribution starts.
#
# Tree layout with width=3, 10 nodes:
#   client → node1
#   node1  → node2 (subtree: node3→node4), node5 (subtree: node6→node7), node8 (subtree: node9→node10)
#
# With gateway-fallback: when a gateway fails, its parent promotes the next node
# in the group as new gateway.  Any single non-root failure → exactly 1 node fails,
# the rest of the subtree is still reached.
#
# Usage:
#   ./scripts/e2e_fault_tolerance.sh [/path/to/program] [failed_node_index]
#     program          - program to analyse (default: /bin/ls)
#     failed_node_index - which node to kill, 1-10 (default: 3, a middle node)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_TRANS="${ROOT_DIR}/bin/trans-tools"
BIN_AGENT="${ROOT_DIR}/bin/agent"

PROGRAM="${1:-/bin/ls}"
FAIL_IDX="${2:-3}"   # which node index (1-10) to kill; default=3 (middle node, was 2 failures before fix)

NODE_COUNT=10
BASE_PORT=19951      # node i uses port BASE_PORT+i-1

if [[ ! -x "${BIN_TRANS}" || ! -x "${BIN_AGENT}" ]]; then
  echo "[ERROR] binaries not found, run: make build-all"
  exit 1
fi

if (( FAIL_IDX < 1 || FAIL_IDX > NODE_COUNT )); then
  echo "[ERROR] failed_node_index must be 1-${NODE_COUNT}, got ${FAIL_IDX}"
  exit 1
fi

# ---- cleanup ---------------------------------------------------------------
cleanup() {
  echo
  echo "== stopping agent processes =="
  for pid in "${PIDS[@]+"${PIDS[@]}"}"; do
    kill "${pid}" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap cleanup EXIT

# ---- pre-clean -------------------------------------------------------------
for i in $(seq 1 "${NODE_COUNT}"); do
  rm -rf "/tmp/recv-node${i}" "/tmp/agent-node${i}.log"
done

# ---- start agents ----------------------------------------------------------
echo "== starting ${NODE_COUNT} local agent processes =="
declare -a PIDS=()
declare -A NODE_PORT=()
declare -A NODE_PID=()

for i in $(seq 1 "${NODE_COUNT}"); do
  port=$(( BASE_PORT + i - 1 ))
  NODE_PORT[$i]="${port}"
  dest="/tmp/recv-node${i}"
  "${BIN_AGENT}" \
    -tmp-name "node${i}" \
    -port "${port}" \
    -dest-override "${dest}" \
    --insecure > "/tmp/agent-node${i}.log" 2>&1 &
  pid=$!
  PIDS+=("${pid}")
  NODE_PID[$i]="${pid}"
  echo "  node${i}: port=${port}  dest=${dest}  pid=${pid}"
done

sleep 1

# ---- kill the target node --------------------------------------------------
fail_port="${NODE_PORT[$FAIL_IDX]}"
fail_pid="${NODE_PID[$FAIL_IDX]}"
echo
echo "== simulating failure: killing node${FAIL_IDX} (port=${fail_port} pid=${fail_pid}) =="
kill "${fail_pid}" 2>/dev/null || true
wait "${fail_pid}" 2>/dev/null || true

sleep 1

# ---- build node list (localhost:port,...) -----------------------------------
NODES_WITH_PORTS=""
for i in $(seq 1 "${NODE_COUNT}"); do
  entry="localhost:${NODE_PORT[$i]}"
  if [[ -z "${NODES_WITH_PORTS}" ]]; then
    NODES_WITH_PORTS="${entry}"
  else
    NODES_WITH_PORTS="${NODES_WITH_PORTS},${entry}"
  fi
done

# ---- run distribution ------------------------------------------------------
echo
echo "== running deps distribution (${NODE_COUNT} nodes, node${FAIL_IDX} is down) =="
echo "   nodes: ${NODES_WITH_PORTS}"
set +e
"${BIN_TRANS}" deps \
  --program  "${PROGRAM}" \
  --nodes    "${NODES_WITH_PORTS}" \
  --width    3 \
  --buffer   2M \
  --dest     /tmp/dependencies \
  --min-size-mb 1 \
  --filter-prefix /lib \
  --insecure
STATUS=$?
set -e

# ---- verify results --------------------------------------------------------
echo
echo "== verifying recv directories =="
ok_count=0
fail_count=0
for i in $(seq 1 "${NODE_COUNT}"); do
  recv="/tmp/recv-node${i}"
  if ls -lh "${recv}"/*.tar 2>/dev/null | grep -q '.'; then
    echo "  [OK  ] node${i} (port=${NODE_PORT[$i]}): $(ls "${recv}"/*.tar 2>/dev/null | wc -l) tar file(s)"
    (( ok_count++ )) || true
  else
    echo "  [FAIL] node${i} (port=${NODE_PORT[$i]}): no tar received"
    (( fail_count++ )) || true
  fi
done

echo
echo "== agent logs (last 3 lines each) =="
for i in $(seq 1 "${NODE_COUNT}"); do
  echo "  --- node${i} ---"
  tail -3 "/tmp/agent-node${i}.log" 2>/dev/null || echo "    (no log)"
done

# ---- summary ---------------------------------------------------------------
echo
echo "== summary =="
echo "  nodes total   : ${NODE_COUNT}"
echo "  killed node   : node${FAIL_IDX} (port=${fail_port})"
echo "  recv OK       : ${ok_count}"
echo "  recv FAIL     : ${fail_count}"
echo "  expected OK   : $(( NODE_COUNT - 1 ))"
echo "  expected FAIL : 1"

# With client+server fallback: any single node failure (including root) causes
# exactly 1 failure.  The client or parent node skips the failed gateway and
# promotes the next node in the group.
expected_fail=1
expected_ok=$(( NODE_COUNT - expected_fail ))

if (( ok_count == expected_ok && fail_count == expected_fail )); then
  echo
  echo "PASS: fault-tolerance test passed"
  echo "      ${ok_count}/${NODE_COUNT} nodes received data, ${fail_count} failed as expected"
  exit 0
else
  echo
  echo "FAIL: unexpected result"
  echo "      got  ok=${ok_count} fail=${fail_count}"
  echo "      want ok=${expected_ok} fail=${expected_fail}"
  exit 1
fi
