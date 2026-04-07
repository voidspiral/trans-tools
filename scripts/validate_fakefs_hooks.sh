#!/usr/bin/env bash
# Validates fakefs Slurm hook scripts: bash syntax, regression test, and shellcheck when available.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS=(
  "${ROOT_DIR}/scripts/dependency_mount_fakefs.sh"
  "${ROOT_DIR}/scripts/dependency_mount_cleanup_fakefs.sh"
  "${ROOT_DIR}/scripts/slurm_fakefs_hook_soft_fail_test.sh"
  "${ROOT_DIR}/scripts/e2e_fakefs_mount_test.sh"
)

for f in "${SCRIPTS[@]}"; do
  bash -n "${f}"
done

bash "${ROOT_DIR}/scripts/slurm_fakefs_hook_soft_fail_test.sh"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${SCRIPTS[@]}"
else
  echo "WARN: shellcheck not on PATH; skipped static analysis. Install shellcheck for full validation (e.g. apt install shellcheck)." >&2
fi

echo "OK: validate_fakefs_hooks"
