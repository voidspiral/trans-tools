#!/usr/bin/env bash
# 依赖挂载脚本（基于 fakefs）
# 逻辑：
#   1. 依赖 *_so.tar 放在 STORAGE_DIR（默认 /tmp/dependencies）
#   2. 从文件名恢复目录（如 zvol8zhomezuserzapp_so.tar -> /vol8/home/user/app）
#   3. upperdir 解压 tar；lowerdir=业务目录；mountpoint=业务目录（同路径挂载）
#
# Slurm Prolog: when SLURM_JOB_ID is set, handled failures exit 0 by default so the
# node is not drained; errors go to ${STORAGE_DIR}/hook-errors.log and syslog
# (logger -t slurm-fakefs-hook). Set SLURM_HOOK_SOFT_FAIL=0 to force strict non-zero
# exits under Slurm (debug only; may cause Prolog errors / node drain). Without
# SLURM_JOB_ID, behavior stays fail-fast unless SLURM_HOOK_SOFT_FAIL=1 (for tests).
# Troubleshooting: error paths keep dependency storage content for postmortem analysis.

set -euo pipefail

FAKEFS_BIN="${FAKEFS_BIN:-fakefs}"
MOUNT_TIMEOUT_SEC="${FAKEFS_MOUNT_TIMEOUT_SEC:-15}"
STRICT_MODE="${FAKEFS_STRICT_MODE:-1}"
AGENT_DEBUG_LOG_PATH="${AGENT_DEBUG_LOG_PATH:-}"

usage() {
  cat <<EOF
用法:
  $0 [STORAGE_DIR]
  $0 -h|--help

未指定 STORAGE_DIR：Slurm 用 DEPENDENCY_STORAGE_DIR，否则 /tmp/dependencies。
EOF
}

slurm_hook_soft_fail() {
  [[ "${SLURM_HOOK_SOFT_FAIL:-}" == "0" ]] && return 1
  [[ -n "${SLURM_JOB_ID:-}" ]] && return 0
  [[ "${SLURM_HOOK_SOFT_FAIL:-}" == "1" ]] && return 0
  return 1
}

log_hook_error() {
  local reason="$1"
  local msg="$2"
  local ts line logf
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')"
  line="ERROR reason=${reason} time=${ts} job=${SLURM_JOB_ID:-} node=${SLURMD_NODENAME:-$(hostname 2>/dev/null || echo unknown)} msg=${msg}"
  echo "${line}" >&2
  logf="${STORAGE_DIR:-}/hook-errors.log"
  if [[ -n "${STORAGE_DIR:-}" ]]; then
    mkdir -p "${STORAGE_DIR}" 2>/dev/null || true
    echo "${line}" >> "${logf}" 2>/dev/null || true
  fi
  if command -v logger >/dev/null 2>&1; then
    logger -t slurm-fakefs-hook -- "${line}" 2>/dev/null || true
  fi
}

soft_fail_or_exit() {
  local code="$1"
  local reason="$2"
  local msg="$3"
  if slurm_hook_soft_fail; then
    log_hook_error "${reason}" "${msg}"
    exit 0
  fi
  exit "${code}"
}

_hook_err_trap() {
  local ec=$?
  trap - ERR
  log_hook_error "ERR" "unexpected failure exit_code=${ec}"
  exit 0
}

debug_log() {
  local hypothesis_id="$1"
  local location="$2"
  local message="$3"
  local data_json="${4:-{}}"
  printf '{"id":"log_%s","timestamp":%s,"runId":"mount-script","hypothesisId":"%s","location":"%s","message":"%s","data":%s}\n' \
    "$(date +%s%N)" "$(date +%s%3N)" "${hypothesis_id}" "${location}" "${message}" "${data_json}" >> "${DEBUG_LOG_PATH}"
}

agent_debug_log() {
  [[ -z "${AGENT_DEBUG_LOG_PATH}" ]] && return 0
  local hypothesis_id="$1"
  local location="$2"
  local message="$3"
  local data_json="${4:-{}}"
  mkdir -p "$(dirname "${AGENT_DEBUG_LOG_PATH}")" 2>/dev/null || true
  printf '{"id":"log_%s","timestamp":%s,"runId":"prolog-env-debug","hypothesisId":"%s","location":"%s","message":"%s","data":%s}\n' \
    "$(date +%s%N)" "$(date +%s%3N)" "${hypothesis_id}" "${location}" "${message}" "${data_json}" >> "${AGENT_DEBUG_LOG_PATH}"
}

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

is_fakefs_mounted() {
  local mp="$1"
  mount | awk -v m="$mp" '($1=="fakefs" || $1=="fakeFS" || $5=="fuse.fakefs" || $5=="fuse.fakeFS") && $3==m {found=1} END{exit(found?0:1)}'
}

mount_fstype_at() {
  local mp="$1"
  findmnt -T "${mp}" -n -o FSTYPE 2>/dev/null || echo unknown
}

STORAGE_DIR_CLI=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "[ERROR] 未知选项: $1" >&2
      usage >&2
      soft_fail_or_exit 1 "BAD_CLI" "unknown option: $1"
      ;;
    *)
      if [[ -n "${STORAGE_DIR_CLI}" ]]; then
        echo "[ERROR] 多余的目录参数: $1" >&2
        soft_fail_or_exit 1 "BAD_CLI" "extra directory argument: $1"
      fi
      STORAGE_DIR_CLI="$1"
      shift
      ;;
  esac
done

if [[ -n "${STORAGE_DIR_CLI}" ]]; then
  STORAGE_DIR="${STORAGE_DIR_CLI}"
elif [[ -n "${SLURM_JOB_ID:-}" ]]; then
  STORAGE_DIR="${DEPENDENCY_STORAGE_DIR:-/tmp/dependencies}"
else
  STORAGE_DIR="/tmp/dependencies"
fi

if slurm_hook_soft_fail; then
  trap '_hook_err_trap' ERR
fi

if ! command -v "${FAKEFS_BIN}" >/dev/null 2>&1; then
  echo "[ERROR] 未找到 fakefs 可执行文件：${FAKEFS_BIN}"
  echo "       请确保已构建并将其加入 PATH，或通过 FAKEFS_BIN 覆盖路径。"
  soft_fail_or_exit 1 "MISSING_FAKEFS" "fakefs not found: ${FAKEFS_BIN}"
fi

DEBUG_LOG_PATH="${STORAGE_DIR}/debug.log"
BASE_DIR="${FAKEFS_STATE_DIR:-${STORAGE_DIR}/.fakefs}"

echo "[INFO] 使用依赖存放目录: ${STORAGE_DIR}"

if [[ ! -d "${STORAGE_DIR}" ]]; then
  echo "[WARN] 目录不存在: ${STORAGE_DIR}"
  exit 0
fi

shopt -s nullglob
tar_files=( "${STORAGE_DIR}"/*_so.tar )
shopt -u nullglob

if (( ${#tar_files[@]} == 0 )); then
  echo "[INFO] 未找到 *_so.tar 文件，退出"
  agent_debug_log "H3" "dependency_mount_fakefs.sh:no_tar" "no tar files found" "{\"storageDir\":\"${STORAGE_DIR}\",\"ldLibraryPath\":\"${LD_LIBRARY_PATH:-}\"}"
  exit 0
fi

agent_debug_log "H1" "dependency_mount_fakefs.sh:entry" "prolog script entry env snapshot" "{\"uid\":\"$(id -u)\",\"user\":\"$(id -un 2>/dev/null || echo unknown)\",\"slurmJobId\":\"${SLURM_JOB_ID:-}\",\"slurmStepId\":\"${SLURM_STEP_ID:-}\",\"slurmNode\":\"${SLURMD_NODENAME:-}\",\"ldLibraryPath\":\"${LD_LIBRARY_PATH:-}\",\"storageDir\":\"${STORAGE_DIR}\"}"

mkdir -p "${BASE_DIR}"
overall_failed=0

for tar_path in "${tar_files[@]}"; do
  tar_name="$(basename "${tar_path}")"
  base="${tar_name%_so.tar}"
  directory="${base//z//}"

  echo "[INFO] 处理 tar: ${tar_name} -> 业务路径: ${directory}"
  debug_log "H1" "dependency_mount_fakefs.sh:directory" "resolved lower target" "{\"directory\":\"${directory}\"}"
  agent_debug_log "H2" "dependency_mount_fakefs.sh:tar_mapping" "resolved tar to lowerdir" "{\"tar\":\"${tar_name}\",\"directory\":\"${directory}\"}"

  if [[ -z "${directory}" || "${directory}" != /* ]]; then
    echo "[ERROR] 无法从 ${tar_name} 推导合法目录，跳过"
    overall_failed=1
    continue
  fi

  # 由业务路径生成的唯一键，仅用于 .state 与 fakefs upper 工作目录的文件名
  path_key="${directory#/}"
  path_key="${path_key//\//_}"
  state_file="${BASE_DIR}/${path_key}.state"
  lower_dir="${directory}"
  mountpoint="${directory}"
  upper_dir="${BASE_DIR}/${path_key}_upper"
  mkdir -p "${upper_dir}"

  if is_fakefs_mounted "${mountpoint}"; then
    echo "[INFO] 检测到业务路径已挂载 fakefs，先卸载: ${mountpoint}"
    unmount_one "${mountpoint}"
  elif mountpoint -q "${mountpoint}" 2>/dev/null; then
    existing_fstype="$(mount_fstype_at "${mountpoint}")"
    if [[ "${existing_fstype}" == "fuse.fakefs" || "${existing_fstype}" == "fuse.fakeFS" ]]; then
      echo "[INFO] 检测到业务路径存在 fakefs 挂载，尝试卸载: ${mountpoint}"
      umount -l "${mountpoint}" 2>/dev/null || true
    else
      echo "[ERROR] 业务路径已存在非 fakefs 挂载（${existing_fstype}），拒绝卸载: ${mountpoint}"
      overall_failed=1
      continue
    fi
  fi

  echo "[INFO] 清理 upperdir: ${upper_dir}"
  rm -rf "${upper_dir:?}/"* 2>/dev/null || true

  if [[ ! -f "${tar_path}" ]]; then
    echo "[ERROR] tar 文件不存在: ${tar_path}"
    overall_failed=1
    continue
  fi

  echo "[INFO] 解压 tar: ${tar_path} -> ${upper_dir}"
  if ! tar xf "${tar_path}" -C "${upper_dir}"; then
    echo "[ERROR] 解压失败: ${tar_path}"
    overall_failed=1
    continue
  fi

  inner_path="${directory#/}"
  if [[ -d "${upper_dir}/${inner_path}" ]]; then
    echo "[INFO] 展平 tar 内路径: ${inner_path} -> upper 根目录"
    if mv "${upper_dir}/${inner_path}/"* "${upper_dir}/" 2>/dev/null; then
      :
    else
      echo "[WARN] 展平时移动文件失败（可能目录为空），继续"
    fi
    rm -rf "${upper_dir:?}/${inner_path}"

    parent="${upper_dir}/$(dirname "${inner_path}")"
    while [[ -d "${parent}" && "${parent}" != "${upper_dir}" ]] && [[ -z "$(ls -A "${parent}" 2>/dev/null)" ]]; do
      rmdir "${parent}" 2>/dev/null || true
      parent="$(dirname "${parent}")"
    done
  fi

  echo "[INFO] fakefs: lowerdir=${lower_dir}, upperdir=${upper_dir}, mountpoint=${mountpoint}"
  if command -v timeout >/dev/null 2>&1; then
    if timeout "${MOUNT_TIMEOUT_SEC}" "${FAKEFS_BIN}" -l "${lower_dir}" -u "${upper_dir}" "${mountpoint}"; then
      :
    else
      rc=$?
      echo "[ERROR] fakefs 挂载失败或超时（rc=${rc}）: ${mountpoint}"
      overall_failed=1
      continue
    fi
  else
    if "${FAKEFS_BIN}" -l "${lower_dir}" -u "${upper_dir}" "${mountpoint}"; then
      :
    else
      rc=$?
      echo "[ERROR] fakefs 挂载失败（rc=${rc}）: ${mountpoint}"
      overall_failed=1
      continue
    fi
  fi

  mnt_fstype="$(findmnt -T "${mountpoint}" -n -o FSTYPE 2>/dev/null || echo unknown)"
  debug_log "H4" "dependency_mount_fakefs.sh:after_fakefs_mount" "mountpoint fstype" "{\"mountpoint\":\"${mountpoint}\",\"fstype\":\"${mnt_fstype}\"}"
  agent_debug_log "H4" "dependency_mount_fakefs.sh:after_mount" "mount result and visibility" "{\"mountpoint\":\"${mountpoint}\",\"lowerDir\":\"${lower_dir}\",\"fstype\":\"${mnt_fstype}\"}"

  cat > "${state_file}" <<EOF
LOWERDIR=${lower_dir}
MOUNTPOINT=${mountpoint}
UPPER_DIR=${upper_dir}
TAR_PATH=${tar_path}
EOF

  echo "[INFO] ✓ 完成: ${mountpoint}（lowerdir=${lower_dir}, upperdir=${upper_dir}）"
done

echo "[INFO] 所有 tar 处理完成（fakefs 模式）"
if [[ "${STRICT_MODE}" == "1" && "${overall_failed}" -ne 0 ]]; then
  echo "[ERROR] 存在失败项，严格模式返回非 0"
  if slurm_hook_soft_fail; then
    log_hook_error "STRICT_AGGREGATE" "one or more mount steps failed (FAKEFS_STRICT_MODE=1)"
    exit 0
  fi
  exit 1
fi
