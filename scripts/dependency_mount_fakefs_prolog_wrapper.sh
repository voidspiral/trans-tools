#!/bin/bash
set -euo pipefail
export SLURM_HOOK_SOFT_FAIL=1
# Slurm prolog/epilog often run with a minimal PATH; fakefs is under /usr/local/bin.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export FAKEFS_BIN="${FAKEFS_BIN:-/usr/local/bin/fakefs}"
exec /home/code/trans-tools/scripts/dependency_mount_fakefs.sh "$@"
