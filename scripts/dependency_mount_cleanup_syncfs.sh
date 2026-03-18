#!/usr/bin/env bash
# 基于 syncFS 的依赖挂载清理脚本
#
# 目标：
#   - 卸载由 dependency_mount_syncfs.sh 创建的 syncFS 挂载点
#   - 清理 /tmp/local/syncfs 下的 upper 目录内容（可选地删除整个目录）
#
# 用法：
#   # 只卸载并清空 upper 内容
#   sudo ./dependency_mount_cleanup_syncfs.sh
#
#   # 卸载并删除 /tmp/local/syncfs 下的所有 upper 目录
#   sudo ./dependency_mount_cleanup_syncfs.sh --remove-dirs

set -euo pipefail

REMOVE_DIRS=0
if [[ "${1:-}" == "--remove-dirs" ]]; then
  REMOVE_DIRS=1
fi

echo "[INFO] 开始清理 syncFS 挂载"

# 步骤1：卸载挂载点为 /vol8/... 或 /tmp/local/syncfs/... 的 syncFS/FUSE 挂载
# 说明：
#   - 在不同发行版上，类型可能显示为 'fuse.syncFS'、'fuse' 或其他 FUSE 相关类型；
#   - 这里通过挂载点前缀进行过滤，避免误卸载无关 FUSE 挂载。

echo "[INFO] 卸载 /vol8 下的 syncFS/FUSE 挂载点（不卸载 /vol8 本身）"
mount | awk '$3 ~ "^/vol8/" {print $3}' | while read -r mp; do
  mp="${mp%% }"
  [[ -z "${mp}" || "${mp}" == "/vol8" ]] && continue
  echo "[INFO] umount -l ${mp}"
  if umount -l "${mp}" 2>/dev/null; then
    echo "[INFO] 卸载成功: ${mp}"
  else
    echo "[WARN] 卸载失败: ${mp}"
  fi
done

echo "[INFO] 卸载 /tmp/local/syncfs 下的挂载点"
mount | awk '$3 ~ "^/tmp/local/syncfs" {print $3}' | while read -r mp; do
  [[ -z "${mp}" ]] && continue
  echo "[INFO] umount -l ${mp}"
  if umount -l "${mp}" 2>/dev/null; then
    echo "[INFO] 卸载成功: ${mp}"
  else
    echo "[WARN] 卸载失败: ${mp}"
  fi
done

# 步骤2：兜底卸载剩余以 syncfs 目录为前缀的 FUSE 挂载（防止残留）
echo "[INFO] 兜底卸载可能残留的 FUSE 挂载（按挂载点前缀过滤）"
mount | awk '$3 ~ "^/vol8/" || $3 ~ "^/tmp/local/syncfs"' | while read -r line; do
  mp="$(echo "${line}" | awk "{print \$3}")"
  [[ -z "${mp}" ]] && continue
  echo "[INFO] (兜底) umount -l ${mp}"
  umount -l "${mp}" 2>/dev/null || true
done

# 步骤3：清理 upper 内容
BASE_DIR="/tmp/local/syncfs"
if [[ -d "${BASE_DIR}" ]]; then
  echo "[INFO] 清理 ${BASE_DIR} 下的 upper 内容"
  bash -c 'rm -rf /tmp/local/syncfs/*_upper/*' 2>/dev/null || true
fi

# 步骤4：按需删除整个 syncfs 目录
if [[ "${REMOVE_DIRS}" -eq 1 && -d "${BASE_DIR}" ]]; then
  echo "[INFO] 删除 ${BASE_DIR} 下的所有目录"
  bash -c 'rm -rf /tmp/local/syncfs/*' 2>/dev/null || true
fi

echo "[INFO] 清理完成（syncFS 模式）"

