#!/usr/bin/env bash
# 基于 fakefs 的依赖挂载清理脚本
#
# 目标：
#   - 卸载由 dependency_mount_fakefs.sh 创建的 FUSE 挂载点（mountpoint=业务目录）
#   - 清理 upper 目录内容（可选删除整个 .fakefs 状态目录）
#   - 若依赖存放目录 STORAGE_DIR 本身是挂载点，最后对其卸载（常见于 Slurm 下 bind 到每作业路径）
#
# 用法：
#   sudo ./dependency_mount_cleanup_fakefs.sh
#   sudo ./dependency_mount_cleanup_fakefs.sh --remove-dirs
#   sudo ./dependency_mount_cleanup_fakefs.sh --remove-dirs /path/to/dependencies
#
# 默认行为：
#   - 清理完成后会删除 STORAGE_DIR 本身（rm -rf）。
#   - 如需保留依赖目录用于调试，加 --keep-storage。

set -euo pipefail

REMOVE_DIRS=0
KEEP_STORAGE=0
if [[ "${1:-}" == "--remove-dirs" ]]; then
  REMOVE_DIRS=1
  shift
fi
if [[ "${1:-}" == "--keep-storage" ]]; then
  KEEP_STORAGE=1
  shift
fi

echo "[INFO] 开始清理 fakefs 挂载"

if [[ -n "${SLURM_JOB_ID:-}" ]]; then
  STORAGE_DIR="${DEPENDENCY_STORAGE_DIR:-/tmp/dependencies}"
else
  STORAGE_DIR="${1:-/tmp/dependencies}"
fi
BASE_DIR="${FAKEFS_STATE_DIR:-${STORAGE_DIR}/.fakefs}"

unmount_one() {
  local mp="$1"
  [[ -z "${mp}" ]] && return 0
  if command -v fusermount3 >/dev/null 2>&1; then
    echo "[INFO] fusermount3 -u ${mp}"
    fusermount3 -u "${mp}" 2>/dev/null || {
      echo "[WARN] fusermount3 卸载失败，尝试 umount -l: ${mp}"
      umount -l "${mp}" 2>/dev/null || true
    }
  else
    echo "[INFO] umount -l ${mp}"
    umount -l "${mp}" 2>/dev/null || true
  fi
}

unmount_storage_dir_if_mounted() {
  if mountpoint -q "${STORAGE_DIR}" 2>/dev/null; then
    echo "[INFO] 卸载依赖存放目录挂载: ${STORAGE_DIR}"
    unmount_one "${STORAGE_DIR}"
  fi
}

purge_storage_dir() {
  if [[ "${KEEP_STORAGE}" -eq 1 ]]; then
    echo "[INFO] 保留依赖存放目录（--keep-storage）: ${STORAGE_DIR}"
    return 0
  fi
  if [[ -z "${STORAGE_DIR}" || "${STORAGE_DIR}" == "/" || "${STORAGE_DIR}" == "/tmp" ]]; then
    echo "[ERROR] 拒绝删除危险目录: ${STORAGE_DIR}"
    return 1
  fi
  if [[ ! -e "${STORAGE_DIR}" ]]; then
    return 0
  fi
  echo "[INFO] 删除依赖存放目录: ${STORAGE_DIR}"
  rm -rf "${STORAGE_DIR}"
}

if [[ ! -d "${BASE_DIR}" ]]; then
  echo "[INFO] 状态目录不存在: ${BASE_DIR}，跳过按 state 卸载"
  unmount_storage_dir_if_mounted
  purge_storage_dir
  echo "[INFO] 清理完成（fakefs 模式）"
  exit 0
fi

shopt -s nullglob
state_files=( "${BASE_DIR}"/*.state )
shopt -u nullglob

echo "[INFO] 卸载 fakefs 挂载点（按 state 文件）"
for sf in "${state_files[@]}"; do
  # shellcheck disable=SC1090
  source "${sf}" 2>/dev/null || true
  if [[ -n "${MOUNTPOINT:-}" ]]; then
    unmount_one "${MOUNTPOINT}"
  elif [[ -n "${DIRECTORY:-}" ]]; then
    # 旧版 state：mountpoint 写在 DIRECTORY
    unmount_one "${DIRECTORY}"
  fi
done

echo "[INFO] 清理 ${BASE_DIR} 下的 upper 内容与 state 文件"
rm -rf "${BASE_DIR}"/*_upper/* 2>/dev/null || true
rm -f "${BASE_DIR}"/*.state 2>/dev/null || true

if [[ "${REMOVE_DIRS}" -eq 1 && -d "${BASE_DIR}" ]]; then
  echo "[INFO] 删除 ${BASE_DIR} 下的所有目录"
  rm -rf "${BASE_DIR:?}/"* 2>/dev/null || true
fi

unmount_storage_dir_if_mounted
purge_storage_dir

echo "[INFO] 清理完成（fakefs 模式）"

