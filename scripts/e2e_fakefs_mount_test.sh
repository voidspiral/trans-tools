#!/usr/bin/env bash
# e2e test: verify dependency_mount_fakefs.sh
#
# This is a local smoke test that fakes a /vol8/lower directory.
# It does NOT require Lustre; it only validates:
#   - fakefs mount works (lower + extracted upper visible)
#   - running mount script twice is idempotent (mode 1)
#
# Run:
#   sudo bash scripts/e2e_fakefs_mount_test.sh --mode 1
#   sudo bash scripts/e2e_fakefs_mount_test.sh --mode 2
#   sudo bash scripts/e2e_fakefs_mount_test.sh --mode 3
#
# Modes:
#   1: mount -> verify -> mount again (idempotency) -> cleanup(unmount) & remove dirs
#   2: mount -> verify -> DO NOT cleanup(unmount)
#   3: DO NOT mount -> only verify (expects it is already mounted)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LOWER_DIR="/vol8/test_libs"
STORAGE_DIR="/tmp/dependencies"
FAKEFS_STATE_DIR="${STORAGE_DIR}/.fakefs"
# 方案A：挂载点即业务原路径
MNT_DIR="${LOWER_DIR}"
MKDEPS_DIR="/tmp/mkdeps"

TAR_NAME="zvol8ztest_libs_so.tar"
TAR_PATH="${STORAGE_DIR}/${TAR_NAME}"

FAKEFS_BIN="${FAKEFS_BIN:-fakefs}"
MODE="${MODE:-2}"

usage() {
  echo "Usage: sudo bash scripts/e2e_fakefs_mount_test.sh [--mode 1|2|3]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --mode=*)
      MODE="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown arg: $1"
      usage
      exit 2
      ;;
  esac
done

if [[ "${MODE}" != "1" && "${MODE}" != "2" && "${MODE}" != "3" ]]; then
  echo "[ERROR] Invalid --mode: ${MODE}"
  usage
  exit 2
fi

cleanup_tmp() {
  rm -rf "${MKDEPS_DIR}" 2>/dev/null || true
}
trap cleanup_tmp EXIT

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "[ERROR] This test must run as root (need FUSE mount)."
    exit 1
  fi
}

require_bin() {
  if ! command -v "${FAKEFS_BIN}" >/dev/null 2>&1; then
    echo "[ERROR] fakefs binary not found: ${FAKEFS_BIN}"
    exit 1
  fi
}

cleanup_all() {
  # Remove generated tar/temps here. Unmount/cleanup is controlled by MODE.
  rm -f "${TAR_PATH}" 2>/dev/null || true
}

verify_prolog_soft_fail_retains_storage() {
  local probe_dir="/tmp/dependency-softfail-probe-$$"
  local sentinel="${probe_dir}/retain-on-error.marker"
  local hook_log="${probe_dir}/hook-errors.log"
  rm -rf "${probe_dir}" 2>/dev/null || true
  mkdir -p "${probe_dir}"
  echo "retain-me" > "${sentinel}"

  set +e
  SLURM_JOB_ID="e2e-softfail-job" \
  SLURMD_NODENAME="e2e-softfail-node" \
  DEPENDENCY_STORAGE_DIR="${probe_dir}" \
  FAKEFS_BIN="${probe_dir}/missing-fakefs" \
  PATH="/usr/bin:/bin" \
    bash "${ROOT_DIR}/scripts/dependency_mount_fakefs.sh" >/dev/null 2>&1
  local rc=$?
  set -e

  if [[ "${rc}" -ne 0 ]]; then
    echo "[ERROR] Expected soft-fail exit 0 for missing fakefs under Slurm context."
    rm -rf "${probe_dir}" 2>/dev/null || true
    exit 1
  fi
  if [[ ! -f "${sentinel}" ]]; then
    echo "[ERROR] Expected dependency storage marker to be retained on error."
    rm -rf "${probe_dir}" 2>/dev/null || true
    exit 1
  fi
  if [[ ! -f "${hook_log}" ]] || ! grep -q "ERROR reason=MISSING_FAKEFS" "${hook_log}"; then
    echo "[ERROR] Expected MISSING_FAKEFS entry in hook log: ${hook_log}"
    rm -rf "${probe_dir}" 2>/dev/null || true
    exit 1
  fi
  rm -rf "${probe_dir}" 2>/dev/null || true
}

verify_prolog_soft_fail_retains_storage
require_root

if [[ "${MODE}" == "3" ]]; then
  echo "[INFO] MODE=3: skip mount and preparation. Only verify."
  echo "[INFO] df -h check (mount visibility)"
  df -h "${MNT_DIR}" || df -h

  echo "[INFO] Verify mount content..."
  cat "${MNT_DIR}/low"
  cat "${MNT_DIR}/libfake.so"

  echo "[INFO] OK"
  exit 0
fi

if [[ "${MODE}" == "1" ]]; then
  echo "[INFO] MODE=1: best-effort cleanup before start (unmount + remove dirs)..."
  sudo -E bash "${ROOT_DIR}/scripts/dependency_mount_cleanup_fakefs.sh" --remove-dirs "${STORAGE_DIR}" 2>/dev/null || true
fi

echo "[INFO] Clean previous tar (best-effort)..."
cleanup_all
rm -f "${STORAGE_DIR}"/*_so.tar 2>/dev/null || true

echo "[INFO] Prepare directories..."
mkdir -p "${LOWER_DIR}"
mkdir -p "${STORAGE_DIR}"

echo "[INFO] Create lower content..."
echo "lower-original-v1" > "${LOWER_DIR}/low"

echo "[INFO] Create upper content tar..."
rm -rf "${MKDEPS_DIR}"
mkdir -p "${MKDEPS_DIR}/vol8/test_libs"
echo "upper-from-tar" > "${MKDEPS_DIR}/vol8/test_libs/libfake.so"
tar -cf "${TAR_PATH}" -C "${MKDEPS_DIR}" "vol8/test_libs/libfake.so"

echo "[INFO] Check fakefs binary..."
require_bin

echo "[INFO] Mount (first run)..."
sudo -E env FAKEFS_BIN="${FAKEFS_BIN}" bash "${ROOT_DIR}/scripts/dependency_mount_fakefs.sh" "${STORAGE_DIR}"

echo "[INFO] df -h check (mount visibility)"
df -h "${MNT_DIR}" || df -h

echo "[INFO] Verify mount content..."
cat "${MNT_DIR}/low"
cat "${MNT_DIR}/libfake.so"

if [[ "${MODE}" == "1" ]]; then
  echo "[INFO] Mount again (idempotency test)..."
  sudo -E env FAKEFS_BIN="${FAKEFS_BIN}" bash "${ROOT_DIR}/scripts/dependency_mount_fakefs.sh" "${STORAGE_DIR}"
  echo "[INFO] Verify after remount..."
  cat "${MNT_DIR}/libfake.so"

  echo "[INFO] Cleanup (unmount + remove dirs)..."
  sudo -E bash "${ROOT_DIR}/scripts/dependency_mount_cleanup_fakefs.sh" --remove-dirs "${STORAGE_DIR}"
fi

echo "[INFO] OK"

