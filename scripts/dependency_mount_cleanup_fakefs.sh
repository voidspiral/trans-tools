#!/bin/bash
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
#
# Slurm Epilog: same soft-fail rules as dependency_mount_fakefs.sh. Errors go to
# ${STORAGE_DIR}/hook-errors.log and syslog. With SLURM_JOB_ID set, soft-fail is the
# default (exit 0 on handled errors). SLURM_HOOK_SOFT_FAIL=0 forces strict non-zero
# exits (debug only; may cause Epilog errors / node drain).
# Troubleshooting rule: if any cleanup error occurs, do not delete STORAGE_DIR
# (for example /tmp/dependency) so diagnostics remain available.

set -u
set -o pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

slurm_hook_soft_fail() {
  [[ "${SLURM_HOOK_SOFT_FAIL:-}" == "0" ]] && return 1
  [[ -n "${SLURM_JOB_ID:-${SLURM_JOBID:-}}" ]] && return 0
  [[ -n "${SLURMD_NODENAME:-}" ]] && return 0
  [[ -n "${SLURM_JOB_PARTITION:-}" ]] && return 0
  [[ "$(id -un 2>/dev/null || echo unknown)" == "slurm" ]] && return 0
  [[ "${SLURM_HOOK_SOFT_FAIL:-}" == "1" ]] && return 0
  return 1
}

log_hook_error() {
  local reason="$1"
  local msg="$2"
  local ts line logf
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')"
  line="ERROR reason=${reason} time=${ts} job=${SLURM_JOB_ID:-${SLURM_JOBID:-}} node=${SLURMD_NODENAME:-$(hostname 2>/dev/null || echo unknown)} msg=${msg}"
  echo "${line}" >&2
  logf="${STORAGE_DIR:-/tmp/dependencies}/hook-errors.log"
  mkdir -p "$(dirname "${logf}")" 2>/dev/null || true
  echo "${line}" >> "${logf}" 2>/dev/null || true
  if command -v logger >/dev/null 2>&1; then
    logger -t slurm-fakefs-hook -- "${line}" 2>/dev/null || true
  fi
}

HOOK_ERROR_SEEN=0

record_hook_error() {
  local reason="$1"
  local msg="$2"
  HOOK_ERROR_SEEN=1
  log_hook_error "${reason}" "${msg}"
}

REMOVE_DIRS=0
KEEP_STORAGE=0
STORAGE_DIR_CLI=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove-dirs)
      REMOVE_DIRS=1
      shift
      ;;
    --keep-storage)
      KEEP_STORAGE=1
      shift
      ;;
    -h|--help)
      echo "用法: $0 [--remove-dirs] [--keep-storage] [STORAGE_DIR]"
      exit 0
      ;;
    -*)
      echo "[ERROR] 未知选项: $1" >&2
      if [[ -n "${SLURM_JOB_ID:-}" ]]; then
        STORAGE_DIR="${DEPENDENCY_STORAGE_DIR:-/tmp/dependencies}"
      else
        STORAGE_DIR="${STORAGE_DIR_CLI:-/tmp/dependencies}"
      fi
      record_hook_error "BAD_CLI" "unknown option: $1"
      if slurm_hook_soft_fail; then exit 0; fi
      exit 2
      ;;
    *)
      if [[ -n "${STORAGE_DIR_CLI}" ]]; then
        echo "[ERROR] 多余的目录参数: $1" >&2
        if [[ -n "${SLURM_JOB_ID:-}" ]]; then
          STORAGE_DIR="${DEPENDENCY_STORAGE_DIR:-/tmp/dependencies}"
        else
          STORAGE_DIR="${STORAGE_DIR_CLI}"
        fi
        record_hook_error "BAD_CLI" "extra directory argument: $1"
        if slurm_hook_soft_fail; then exit 0; fi
        exit 2
      fi
      STORAGE_DIR_CLI="$1"
      shift
      ;;
  esac
done

if [[ -n "${SLURM_JOB_ID:-}" ]]; then
  STORAGE_DIR="${DEPENDENCY_STORAGE_DIR:-/tmp/dependencies}"
else
  STORAGE_DIR="${STORAGE_DIR_CLI:-/tmp/dependencies}"
fi

set -e

if slurm_hook_soft_fail; then
  trap 'ec=$?; trap - ERR; log_hook_error "ERR" "unexpected failure exit_code=${ec}"; exit 0' ERR
fi

BASE_DIR="${FAKEFS_STATE_DIR:-${STORAGE_DIR}/.fakefs}"

echo "[INFO] 开始清理 fakefs 挂载"

unmount_one() {
  local mp="$1"
  local failed=1
  [[ -z "${mp}" ]] && return 0
  if command -v fusermount3 >/dev/null 2>&1; then
    echo "[INFO] fusermount3 -u ${mp}"
    if fusermount3 -u "${mp}" 2>/dev/null; then
      failed=0
    else
      echo "[WARN] fusermount3 卸载失败，尝试 umount -l: ${mp}"
      if umount -l "${mp}" 2>/dev/null; then failed=0; fi
    fi
  else
    echo "[INFO] umount -l ${mp}"
    if umount -l "${mp}" 2>/dev/null; then failed=0; fi
  fi
  if [[ "${failed}" -eq 1 ]]; then
    record_hook_error "UNMOUNT" "failed to unmount ${mp}"
  fi
  # Always return 0 so set -e does not abort the epilog mid-loop; strict exit is decided at script end.
  return 0
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
  if [[ "${HOOK_ERROR_SEEN}" -eq 1 ]]; then
    echo "[WARN] Skip deleting dependency storage because cleanup errors were recorded: ${STORAGE_DIR}"
    return 0
  fi
  if [[ -z "${STORAGE_DIR}" || "${STORAGE_DIR}" == "/" || "${STORAGE_DIR}" == "/tmp" ]]; then
    echo "[ERROR] 拒绝删除危险目录: ${STORAGE_DIR}"
    record_hook_error "PURGE_STORAGE" "refused dangerous STORAGE_DIR=${STORAGE_DIR}"
    return 0
  fi
  if [[ ! -e "${STORAGE_DIR}" ]]; then
    return 0
  fi
  echo "[INFO] 删除依赖存放目录: ${STORAGE_DIR}"
  if ! rm -rf "${STORAGE_DIR}"; then
    echo "[ERROR] rm -rf failed: ${STORAGE_DIR}"
    record_hook_error "PURGE_STORAGE" "rm -rf failed for ${STORAGE_DIR}"
    return 0
  fi
  return 0
}

if [[ ! -d "${BASE_DIR}" ]]; then
  echo "[INFO] 状态目录不存在: ${BASE_DIR}，跳过按 state 卸载"
  unmount_storage_dir_if_mounted
  purge_storage_dir
  if [[ "${HOOK_ERROR_SEEN}" -eq 1 ]] && ! slurm_hook_soft_fail; then
    exit 1
  fi
  echo "[INFO] 清理完成（fakefs 模式）"
  exit 0
fi

shopt -s nullglob
state_files=( "${BASE_DIR}"/*.state )
shopt -u nullglob

echo "[INFO] 卸载 fakefs 挂载点（按 state 文件）"
for sf in "${state_files[@]}"; do
  unset MOUNTPOINT DIRECTORY LOWERDIR UPPER_DIR TAR_PATH
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
rm -rf "${BASE_DIR}"/*_upper/* 2>/dev/null || {
  record_hook_error "RM_UPPER" "failed to clean upper dirs under ${BASE_DIR}"
}
rm -f "${BASE_DIR}"/*.state 2>/dev/null || {
  record_hook_error "RM_STATE" "failed to remove state files under ${BASE_DIR}"
}

if [[ "${REMOVE_DIRS}" -eq 1 && -d "${BASE_DIR}" ]]; then
  echo "[INFO] 删除 ${BASE_DIR} 下的所有目录"
  rm -rf "${BASE_DIR:?}/"* 2>/dev/null || {
    record_hook_error "RM_BASE" "failed remove-dirs under ${BASE_DIR}"
  }
fi

unmount_storage_dir_if_mounted
purge_storage_dir

if [[ "${HOOK_ERROR_SEEN}" -eq 1 ]] && ! slurm_hook_soft_fail; then
  exit 1
fi

echo "[INFO] 清理完成（fakefs 模式）"
