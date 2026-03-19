#!/usr/bin/env bash
# 基于 syncFS 的依赖挂载清理脚本
#
# 目标：
#   - 卸载由 dependency_mount_syncfs.sh 创建的 syncFS 挂载点
#   - 清理 syncFS upper 目录内容（可选地删除整个目录）
#
# 用法：
#   # 只卸载并清空 upper 内容
#   sudo ./dependency_mount_cleanup_syncfs.sh
#
#   # 卸载并删除状态目录下的所有 upper 目录
#   sudo ./dependency_mount_cleanup_syncfs.sh --remove-dirs

set -euo pipefail

REMOVE_DIRS=0
if [[ "${1:-}" == "--remove-dirs" ]]; then
  REMOVE_DIRS=1
  shift
fi

echo "[INFO] 开始清理 syncFS 挂载"

# 与挂载脚本保持一致：优先从 SLURM/环境变量获取依赖落盘目录，从而定位 .syncfs 状态目录。
if [[ -n "${SLURM_JOB_ID:-}" ]]; then
  STORAGE_DIR="${DEPENDENCY_STORAGE_DIR:-/tmp/dependencies}"
else
  STORAGE_DIR="${1:-/tmp/dependencies}"
fi
BASE_DIR="${SYNCFS_STATE_DIR:-${STORAGE_DIR}/.syncfs}"

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

# 步骤1：按 state 文件精确卸载（只卸载本脚本创建的挂载）
if [[ ! -d "${BASE_DIR}" ]]; then
  echo "[INFO] 状态目录不存在: ${BASE_DIR}，无需清理"
  exit 0
fi

shopt -s nullglob
state_files=( "${BASE_DIR}"/*.state )
shopt -u nullglob

echo "[INFO] 卸载 syncFS 挂载点（按 state 文件）"
for sf in "${state_files[@]}"; do
  # shellcheck disable=SC1090
  source "${sf}" 2>/dev/null || true
  if [[ -n "${DIRECTORY:-}" ]]; then
    unmount_one "${DIRECTORY}"
  fi
done

echo "[INFO] 卸载 lowerdir 别名(bind)挂载点（按 state 文件）"
for sf in "${state_files[@]}"; do
  # shellcheck disable=SC1090
  source "${sf}" 2>/dev/null || true
  if [[ -n "${LOWER_ALIAS:-}" ]]; then
    echo "[INFO] umount -l ${LOWER_ALIAS}"
    umount -l "${LOWER_ALIAS}" 2>/dev/null || true
  fi
done

# 步骤2：清理 upper 内容与 state 文件
echo "[INFO] 清理 ${BASE_DIR} 下的 upper 内容与 state 文件"
rm -rf "${BASE_DIR}"/*_upper/* 2>/dev/null || true
rm -f "${BASE_DIR}"/*.state 2>/dev/null || true

# 步骤4：按需删除整个状态目录
if [[ "${REMOVE_DIRS}" -eq 1 && -d "${BASE_DIR}" ]]; then
  echo "[INFO] 删除 ${BASE_DIR} 下的所有目录"
  rm -rf "${BASE_DIR:?}/"* 2>/dev/null || true
fi

echo "[INFO] 清理完成（syncFS 模式）"

