#!/bin/bash
# Default --keep-storage so shared /tmp/dependencies tars survive across jobs (multi-case tests).
# Full removal: export SLURM_PURGE_DEPENDENCY_STORAGE=1 before the job or in slurm.conf.
set -euo pipefail
export SLURM_HOOK_SOFT_FAIL=1
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export FAKEFS_BIN="${FAKEFS_BIN:-/usr/local/bin/fakefs}"
epilog_args=()
if [[ "${SLURM_PURGE_DEPENDENCY_STORAGE:-}" != "1" ]]; then
  epilog_args+=(--keep-storage)
fi
exec /home/code/trans-tools/scripts/dependency_mount_cleanup_fakefs.sh "${epilog_args[@]}" "$@"
