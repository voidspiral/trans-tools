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

BASE_DIR="/tmp/local/syncfs"
mkdir -p "${BASE_DIR}"

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

  upper_dir="${BASE_DIR}/${overlay_name}_upper"
  mkdir -p "${upper_dir}"

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
  #   - lowerdir：原始目录（通常是 Lustre 路径，如 /vol8/...）
  #   - upperdir：本地缓存目录
  #   - mountpoint：直接使用原始目录，实现对业务的透明覆盖
  echo "[INFO] 使用 syncFS 挂载: lowerdir=${directory}, upperdir=${upper_dir}, mountpoint=${directory}"

  # 直接尝试挂载；若失败且提示已挂载，可以由调用方决定是否先手工卸载再重试。
  if ! "${SYNCFS_BIN}" -o "lowerdir=${directory},upperdir=${upper_dir}" "${directory}"; then
    echo "[ERROR] syncFS 挂载失败: ${directory}"
    continue
  fi

  echo "[INFO] ✓ syncFS 挂载成功: ${directory}"
done

echo "[INFO] 所有 tar 处理完成（syncFS 模式）"

