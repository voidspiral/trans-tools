#!/usr/bin/env bash
# 依赖挂载脚本（基于 syncFS）
# 思路：
#   1. 依赖 *_so.tar 放在 STORAGE_DIR（默认 /tmp/dependencies）
#   2. 从文件名恢复目录（如 zvol8zhomezuserzapp_so.tar -> /vol8/home/user/app）
#   3. upperdir 解压 tar；lowerdir 直接使用该路径（/vol8/...）
#   4. syncFS 先挂到 /tmp 下独立 mountpoint，避免 lowerdir 与 mountpoint 同路径递归
#   5. 可选：最后 mount --bind（参数 --bind / --fuse-only，见 usage）
#
# SYNCFS_BIN、SYNCFS_STATE_DIR、SYNCFS_FUSE_MNT_BASE 可环境变量覆盖。

set -euo pipefail

SYNCFS_BIN="${SYNCFS_BIN:-syncFS}"
FUSE_MNT_BASE="${SYNCFS_FUSE_MNT_BASE:-/tmp}"

usage() {
  cat <<EOF
用法:
  $0 [--bind|--post-bind] [STORAGE_DIR]   默认：先 FUSE(/tmp 下)再 bind 到业务路径
  $0 --fuse-only|--no-bind [STORAGE_DIR]   仅 FUSE 路径，不 bind（见 state 中 FUSE_MNT）
  $0 -h|--help

未指定 STORAGE_DIR：Slurm 用 DEPENDENCY_STORAGE_DIR，否则 /tmp/dependencies。
EOF
}

if ! command -v "${SYNCFS_BIN}" >/dev/null 2>&1; then
  echo "[ERROR] 未找到 syncFS 可执行文件：${SYNCFS_BIN}"
  echo "       请确保已构建并将其加入 PATH，或通过 SYNCFS_BIN 覆盖路径。"
  exit 1
fi

POST_BIND=1
STORAGE_DIR_CLI=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --fuse-only|--no-bind)
      POST_BIND=0
      shift
      ;;
    --bind|--post-bind)
      POST_BIND=1
      shift
      ;;
    -*)
      echo "[ERROR] 未知选项: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "${STORAGE_DIR_CLI}" ]]; then
        echo "[ERROR] 多余的目录参数: $1" >&2
        exit 1
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

DEBUG_LOG_PATH="${STORAGE_DIR}/debug.log"

echo "[INFO] 使用依赖存放目录: ${STORAGE_DIR}"
echo "[INFO] FUSE 挂载根目录: ${FUSE_MNT_BASE}；模式: $([[ "${POST_BIND}" -eq 1 ]] && echo post-bind || echo fuse-only)"

if [[ ! -d "${STORAGE_DIR}" ]]; then
  echo "[WARN] 目录不存在: ${STORAGE_DIR}"
  exit 0
fi

shopt -s nullglob
tar_files=( "${STORAGE_DIR}"/*_so.tar )
shopt -u nullglob

if (( ${#tar_files[@]} == 0 )); then
  echo "[INFO] 未找到 *_so.tar 文件，退出"
  exit 0
fi

BASE_DIR="${SYNCFS_STATE_DIR:-${STORAGE_DIR}/.syncfs}"
mkdir -p "${BASE_DIR}"
mkdir -p "${FUSE_MNT_BASE}"

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

is_syncfs_mounted() {
  local mp="$1"
  mount | awk -v m="$mp" '($1=="syncFS" || $5=="fuse.syncFS") && $3==m {found=1} END{exit(found?0:1)}'
}

debug_log() {
  local hypothesis_id="$1"
  local location="$2"
  local message="$3"
  local data_json="${4:-{}}"
  printf '{"id":"log_%s","timestamp":%s,"runId":"mount-script","hypothesisId":"%s","location":"%s","message":"%s","data":%s}\n' \
    "$(date +%s%N)" "$(date +%s%3N)" "${hypothesis_id}" "${location}" "${message}" "${data_json}" >> "${DEBUG_LOG_PATH}"
}

post_bind_enabled() {
  [[ "${POST_BIND}" -eq 1 ]]
}

for tar_path in "${tar_files[@]}"; do
  tar_name="$(basename "${tar_path}")"

  base="${tar_name%_so.tar}"
  directory="${base//z//}"

  echo "[INFO] 处理 tar: ${tar_name} -> 业务路径(lowerdir): ${directory}"
  debug_log "H1" "dependency_mount_syncfs.sh:directory" "resolved lower target" "{\"directory\":\"${directory}\"}"

  if [[ -z "${directory}" || "${directory}" != /* ]]; then
    echo "[ERROR] 无法从 ${tar_name} 推导合法目录，跳过"
    continue
  fi

  overlay_name="${directory#/}"
  overlay_name="${overlay_name//\//_}"

  state_file="${BASE_DIR}/${overlay_name}.state"
  lower_dir="${directory}"
  fuse_mnt="${FUSE_MNT_BASE}/syncfs-${overlay_name}"
  upper_dir="${BASE_DIR}/${overlay_name}_upper"
  mkdir -p "${fuse_mnt}"
  mkdir -p "${upper_dir}"

  if post_bind_enabled; then
    if mountpoint -q "${directory}" 2>/dev/null; then
      echo "[INFO] 卸载业务路径上的挂载（含 bind 层）: ${directory}"
      umount -l "${directory}" 2>/dev/null || true
    fi
  fi

  if is_syncfs_mounted "${fuse_mnt}"; then
    echo "[INFO] 检测到已挂载 syncFS: ${fuse_mnt}，先卸载"
    debug_log "H2" "dependency_mount_syncfs.sh:pre_unmount" "fuse mountpoint already syncfs" "{\"fuseMnt\":\"${fuse_mnt}\"}"
    unmount_one "${fuse_mnt}"
  fi

  if is_syncfs_mounted "${directory}"; then
    echo "[INFO] 检测到业务路径上仍有 syncFS（旧模式），先卸载: ${directory}"
    unmount_one "${directory}"
  fi

  echo "[INFO] 清理 upperdir: ${upper_dir}"
  rm -rf "${upper_dir:?}/"* 2>/dev/null || true

  if [[ ! -f "${tar_path}" ]]; then
    echo "[ERROR] tar 文件不存在: ${tar_path}"
    continue
  fi

  echo "[INFO] 解压 tar: ${tar_path} -> ${upper_dir}"
  if ! tar xf "${tar_path}" -C "${upper_dir}"; then
    echo "[ERROR] 解压失败: ${tar_path}"
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

  echo "[INFO] syncFS: lowerdir=${lower_dir}, upperdir=${upper_dir}, mountpoint=${fuse_mnt}"

  if ! "${SYNCFS_BIN}" -o "lowerdir=${lower_dir},upperdir=${upper_dir}" "${fuse_mnt}"; then
    echo "[ERROR] syncFS 挂载失败: ${fuse_mnt}"
    continue
  fi

  mnt_fstype="$(findmnt -T "${fuse_mnt}" -n -o FSTYPE 2>/dev/null || echo unknown)"
  debug_log "H4" "dependency_mount_syncfs.sh:after_syncfs_mount" "fuse mount fstype" "{\"fuseMnt\":\"${fuse_mnt}\",\"fstype\":\"${mnt_fstype}\"}"

  if post_bind_enabled; then
    echo "[INFO] mount --bind（后置）: ${fuse_mnt} -> ${directory}"
    if ! mount --bind "${fuse_mnt}" "${directory}"; then
      echo "[ERROR] mount --bind 失败，正在卸载 FUSE: ${fuse_mnt}"
      unmount_one "${fuse_mnt}"
      continue
    fi
  fi

  cat > "${state_file}" <<EOF
LOWERDIR=${lower_dir}
FUSE_MNT=${fuse_mnt}
MOUNTPOINT=${directory}
POST_BIND=${POST_BIND}
UPPER_DIR=${upper_dir}
TAR_PATH=${tar_path}
EOF

  if post_bind_enabled; then
    echo "[INFO] ✓ 完成: ${directory}（lowerdir=${lower_dir}，经 bind <- ${fuse_mnt}）"
  else
    echo "[INFO] ✓ 完成: 请使用 FUSE 路径 ${fuse_mnt}（未 bind 到 ${directory}）"
  fi
done

echo "[INFO] 所有 tar 处理完成（syncFS 模式）"
