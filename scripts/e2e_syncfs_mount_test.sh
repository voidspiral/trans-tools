#!/usr/bin/env bash
# e2e test: verify dependency_mount_syncfs.sh
#
# This is a local smoke test that fakes a /vol8/lower directory.
# It does NOT require Lustre; it only validates:
#   - syncFS mount works (lower + extracted upper visible)
#   - running mount script twice is idempotent (mode 1)
#
# Run:
#   sudo bash scripts/e2e_syncfs_mount_test.sh --mode 1
#   sudo bash scripts/e2e_syncfs_mount_test.sh --mode 2
#   sudo bash scripts/e2e_syncfs_mount_test.sh --mode 3
#
# Modes:
#   1: mount -> verify -> mount again (idempotency) -> cleanup(unmount) & remove dirs
#   2: mount -> verify -> DO NOT cleanup(unmount)
#   3: DO NOT mount -> only verify (expects it is already mounted)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LOWER_DIR="/vol8/test_libs"
STORAGE_DIR="/tmp/dependencies"
SYNCFS_STATE_DIR="${STORAGE_DIR}/.syncfs"
MKDEPS_DIR="/tmp/mkdeps"

TAR_NAME="zvol8ztest_libs_so.tar"
TAR_PATH="${STORAGE_DIR}/${TAR_NAME}"

SYNCFS_BIN="${SYNCFS_BIN:-${ROOT_DIR}/syncFS/syncFS}"
MODE="${MODE:-2}"

usage() {
  echo "Usage: sudo bash scripts/e2e_syncfs_mount_test.sh [--mode 1|2|3]"
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
    echo "[ERROR] This test must run as root (need FUSE mount + bind)."
    exit 1
  fi
}

require_bin() {
  if [[ ! -x "${SYNCFS_BIN}" ]]; then
    echo "[ERROR] syncFS binary not found/executable: ${SYNCFS_BIN}"
    echo "         Build it with: make -C ${ROOT_DIR}/syncFS"
    exit 1
  fi
}

cleanup_all() {
  # Remove generated tar/temps here. Unmount/cleanup is controlled by MODE.
  rm -f "${TAR_PATH}" 2>/dev/null || true
}

require_root

if [[ "${MODE}" == "3" ]]; then
  echo "[INFO] MODE=3: skip mount and preparation. Only verify."
  echo "[INFO] df -h check (mount visibility)"
  df -h "${LOWER_DIR}" || df -h

  echo "[INFO] Verify mount content..."
  cat "${LOWER_DIR}/low"
  cat "${LOWER_DIR}/libfake.so"

  echo "[INFO] OK"
  exit 0
fi

if [[ "${MODE}" == "1" ]]; then
  echo "[INFO] MODE=1: best-effort cleanup before start (unmount + remove dirs)..."
  sudo -E bash "${ROOT_DIR}/scripts/dependency_mount_cleanup_syncfs.sh" --remove-dirs "${STORAGE_DIR}" 2>/dev/null || true
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

echo "[INFO] Build syncFS (if needed)..."
make -C "${ROOT_DIR}/syncFS" >/dev/null
require_bin

echo "[INFO] Mount (first run)..."
sudo -E env SYNCFS_BIN="${SYNCFS_BIN}" bash "${ROOT_DIR}/scripts/dependency_mount_syncfs.sh" "${STORAGE_DIR}"

echo "[INFO] df -h check (mount visibility)"
df -h "${LOWER_DIR}" || df -h

echo "[INFO] Verify mount content..."
cat "${LOWER_DIR}/low"
cat "${LOWER_DIR}/libfake.so"

if [[ "${MODE}" == "1" ]]; then
  echo "[INFO] Mount again (idempotency test)..."
  sudo -E env SYNCFS_BIN="${SYNCFS_BIN}" bash "${ROOT_DIR}/scripts/dependency_mount_syncfs.sh" "${STORAGE_DIR}"
  echo "[INFO] Verify after remount..."
  cat "${LOWER_DIR}/libfake.so"

  echo "[INFO] Cleanup (unmount + remove dirs)..."
  sudo -E bash "${ROOT_DIR}/scripts/dependency_mount_cleanup_syncfs.sh" --remove-dirs "${STORAGE_DIR}"
fi

echo "[INFO] OK"

