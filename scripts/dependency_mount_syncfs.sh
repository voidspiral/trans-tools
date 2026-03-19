#!/usr/bin/env bash
# 依赖挂载脚本（基于 syncFS）
# 使用思路：
#   1. dependency_client / trans-tools 等组件将依赖打包为 *_so.tar 上传到某个目录（默认 /tmp/dependencies）
#   2. 本脚本针对每个 *_so.tar：
#        - 从文件名恢复原始目录（例如 zvol8zhomezuserzapp_so.tar -> /vol8/home/user/app）
#        - 在本地创建 upperdir 并解压 tar 到 upperdir（必要时展平路径）
#        - 使用 syncFS 将 lowerdir=原目录、upperdir=本地 upperdir 挂载到“原目录”上
#   3. 与原先 overlay+bind 方案相比，不再使用 overlayfs，直接由 syncFS 提供联合视图
#
# 注意：
#   - 默认假定 syncFS 二进制名称为 syncFS，可通过 SYNCFS_BIN 环境变量覆盖
#   - 需要具备 FUSE 挂载权限（一般需要 root 或已配置 user_allow_other 等）

set -euo pipefail

SYNCFS_BIN="${SYNCFS_BIN:-syncFS}"

if ! command -v "${SYNCFS_BIN}" >/dev/null 2>&1; then
  echo "[ERROR] 未找到 syncFS 可执行文件：${SYNCFS_BIN}"
  echo "       请确保已构建并将其加入 PATH，或通过 SYNCFS_BIN 覆盖路径。"
  exit 1
fi

# 在 Slurm Prolog/TaskProlog 中优先使用 DEPENDENCY_STORAGE_DIR，否则允许通过第一个参数指定；
# 如果都没有，则退回到 /tmp/dependencies。
if [[ -n "${SLURM_JOB_ID:-}" ]]; then
  STORAGE_DIR="${DEPENDENCY_STORAGE_DIR:-/tmp/dependencies}"
else
  STORAGE_DIR="${1:-/tmp/dependencies}"
fi

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
  exit 0
fi

# syncFS 的 upperdir/状态目录默认与 Go 分发程序的远端落盘目录保持一致，
# 这样 server 节点收到 tar 后可直接执行挂载/卸载，不依赖额外目录约定。
# 可通过 SYNCFS_STATE_DIR 覆盖。
BASE_DIR="${SYNCFS_STATE_DIR:-${STORAGE_DIR}/.syncfs}"
mkdir -p "${BASE_DIR}"

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
  # 典型 mount 行形态：
  #   syncFS on /vol8/xxx type fuse.syncFS (rw,...)
  mount | awk -v m="$mp" '($1=="syncFS" || $5=="fuse.syncFS") && $3==m {found=1} END{exit(found?0:1)}'
}

for tar_path in "${tar_files[@]}"; do
  tar_name="$(basename "${tar_path}")"

  # 从 tar 文件名推导原始目录：
  #   /vol8/home/user/app -> zvol8zhomezuserzapp_so.tar
  #   反推：zvol8zhomezuserzapp_so.tar -> /vol8/home/user/app
  base="${tar_name%_so.tar}"
  directory="${base//z//}"

  echo "[INFO] 处理 tar: ${tar_name} -> 原始目录: ${directory}"

  if [[ -z "${directory}" || "${directory}" != /* ]]; then
    echo "[ERROR] 无法从 ${tar_name} 推导合法目录，跳过"
    continue
  fi

  overlay_name="${directory#/}"
  overlay_name="${overlay_name//\//_}"

  state_file="${BASE_DIR}/${overlay_name}.state"
  lower_alias="${BASE_DIR}/${overlay_name}_lower"
  upper_dir="${BASE_DIR}/${overlay_name}_upper"
  mkdir -p "${lower_alias}"
  mkdir -p "${upper_dir}"

  # 若该目录已挂载为 syncFS，先卸载（幂等）
  if is_syncfs_mounted "${directory}"; then
    echo "[INFO] 检测到已挂载 syncFS: ${directory}，先卸载"
    unmount_one "${directory}"
  fi

  # 为 lowerdir 创建“别名路径”：在挂载覆盖原目录后，syncFS 仍能通过别名访问原始 lower 内容。
  # 这一步是必须的，否则 mountpoint 覆盖后 lowerdir 会递归指向自己。
  echo "[INFO] 创建 lowerdir 别名(bind): ${directory} -> ${lower_alias}"
  if ! mountpoint -q "${lower_alias}"; then
    if ! mount --bind "${directory}" "${lower_alias}"; then
      echo "[ERROR] 创建 lowerdir 别名失败: ${lower_alias}"
      continue
    fi
  fi

  # 清理旧的 upper 内容（仅目录内容，不删除目录本身）
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

  # 若 tar 内带完整路径（如 vol8/test_libs/...），解压后 upper 会多出一层 vol8/test_libs，需展平到 upper 根
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

  # 使用 syncFS 进行挂载：
  #   - lowerdir：原始目录的别名路径（bind 后的路径，避免递归）
  #   - upperdir：本地缓存目录
  #   - mountpoint：直接覆盖原始目录，实现对业务路径透明
  echo "[INFO] 使用 syncFS 挂载: lowerdir=${lower_alias}, upperdir=${upper_dir}, mountpoint=${directory}"

  if ! "${SYNCFS_BIN}" -o "lowerdir=${lower_alias},upperdir=${upper_dir}" "${directory}"; then
    echo "[ERROR] syncFS 挂载失败: ${directory}"
    continue
  fi

  # 记录状态，供清理脚本精确卸载（避免误卸载系统其他挂载）
  cat > "${state_file}" <<EOF
DIRECTORY=${directory}
LOWER_ALIAS=${lower_alias}
UPPER_DIR=${upper_dir}
TAR_PATH=${tar_path}
EOF

  echo "[INFO] ✓ syncFS 挂载成功: ${directory}"
done

echo "[INFO] 所有 tar 处理完成（syncFS 模式）"

