#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "用法: $0 <node> <mpi_test绝对路径> <LD_LIBRARY_PATH目录>"
  echo "示例: $0 cn33 /vol8/home/test651/mj/trans-tools/bin/mpi_test /tmp/local/overlay/vol8_test_libs_merged"
  exit 2
fi

NODE="$1"
MPI_BIN="$2"
TEST_LD_PATH="$3"

if [[ ! -x "${MPI_BIN}" ]]; then
  echo "[ERROR] 可执行文件不存在或不可执行: ${MPI_BIN}"
  exit 1
fi

echo "[INFO] 节点: ${NODE}"
echo "[INFO] 程序: ${MPI_BIN}"
echo "[INFO] 测试 LD_LIBRARY_PATH: ${TEST_LD_PATH}"
echo "[INFO] 开始 srun 验证..."
echo
echo "===== probe-1: --export=ALL,LD_LIBRARY_PATH ====="
srun -w "${NODE}" -N1 -n1 --export=ALL,LD_LIBRARY_PATH="${TEST_LD_PATH}" \
  bash -c '
    set -euo pipefail
    echo "hostname=$(hostname)"
    echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-<empty>}"
  '

echo
echo "===== probe-2: --export=NONE,LD_LIBRARY_PATH ====="
srun -w "${NODE}" -N1 -n1 --export=NONE,LD_LIBRARY_PATH="${TEST_LD_PATH}" \
  bash -c '
    set -euo pipefail
    echo "hostname=$(hostname)"
    echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-<empty>}"
  '

echo
echo "===== probe-3: custom var passthrough check ====="
srun -w "${NODE}" -N1 -n1 --export=ALL,TT_TEST_SENTINEL=tt_ok_123,LD_LIBRARY_PATH="${TEST_LD_PATH}" \
  bash -c '
    set -euo pipefail
    echo "hostname=$(hostname)"
    echo "TT_TEST_SENTINEL=${TT_TEST_SENTINEL:-<empty>}"
    echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-<empty>}"
  '

echo
echo "===== probe-4: ldd with explicit env prefix ====="
srun -w "${NODE}" -N1 -n1 --export=ALL \
  bash -c '
    set -euo pipefail
    echo "hostname=$(hostname)"
    LD_LIBRARY_PATH="'"${TEST_LD_PATH}"'" ldd "'"${MPI_BIN}"'" || true
  '

echo
echo "===== probe-5: mount/backend evidence for resolved lib ====="
srun -w "${NODE}" -N1 -n1 --export=ALL \
  bash -c '
    set -euo pipefail
    target_lib="$(LD_LIBRARY_PATH="'"${TEST_LD_PATH}"'" ldd "'"${MPI_BIN}"'" 2>/dev/null | awk '"'"'/liblarge\.so/ {print $3; exit}'"'"')"
    echo "hostname=$(hostname)"
    echo "resolved_lib=${target_lib:-<empty>}"
    if [[ -n "${target_lib:-}" && -e "${target_lib}" ]]; then
      echo "--- findmnt -T resolved lib ---"
      findmnt -T "${target_lib}" -o TARGET,SOURCE,FSTYPE,OPTIONS || true
      echo "--- stat resolved lib ---"
      stat -c "dev=%d inode=%i path=%n" "${target_lib}" || true
    fi
    echo "--- findmnt -T /vol8/test_libs ---"
    findmnt -T /vol8/test_libs -o TARGET,SOURCE,FSTYPE,OPTIONS || true
  '

echo
echo "===== probe-6: ELF search priority evidence ====="
srun -w "${NODE}" -N1 -n1 --export=ALL \
  bash -c '
    set -euo pipefail
    echo "hostname=$(hostname)"
    echo "--- readelf: RUNPATH/RPATH ---"
    readelf -d "'"${MPI_BIN}"'" 2>/dev/null | rg "RPATH|RUNPATH|NEEDED" || true
    echo "--- expected path contains liblarge.so? ---"
    ls -l "'"${TEST_LD_PATH}"'/liblarge.so" 2>/dev/null || echo "missing: '"${TEST_LD_PATH}"'/liblarge.so"
    echo "--- loader resolution with explicit env ---"
    LD_LIBRARY_PATH="'"${TEST_LD_PATH}"'" ldd "'"${MPI_BIN}"'" 2>/dev/null | rg "liblarge\\.so|libm\\.so|libc\\.so" || true
  '

echo
echo "[INFO] 判定标准:"
echo "1) probe-1/2 中 LD_LIBRARY_PATH 应等于传入目录；否则说明被系统/插件重写或过滤"
echo "2) probe-3 中 TT_TEST_SENTINEL 若能传递但 LD_LIBRARY_PATH 不能，说明 LD_LIBRARY_PATH 被单独限制"
echo "3) probe-4 若命中目标目录，说明二进制本身可用，问题仅在 srun 环境注入链路"
echo "4) probe-5 若 /vol8/test_libs 的 FSTYPE 是 fuse.syncFS（或你预期的本地层），则 ldd 显示 /vol8 路径也属于本地覆盖视图"
echo "5) probe-6 若 TEST_LD_PATH 中缺少同名 so，或 ELF 存在强制 RPATH/RUNPATH 指向 /vol8，则会继续命中共享路径"
