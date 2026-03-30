#!/usr/bin/env bash
# Verifies dependency_mount_fakefs.sh and dependency_mount_cleanup_fakefs.sh exit 0
# under Slurm-like env when operations would otherwise fail, and write hook-errors.log.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

export SLURM_JOB_ID="softfail-test-job"
export SLURMD_NODENAME="test-node"
export DEPENDENCY_STORAGE_DIR="${TMP}/deps"
mkdir -p "${DEPENDENCY_STORAGE_DIR}"

# Prolog: missing fakefs must exit 0 and log ERROR to hook-errors.log
export PATH="/usr/bin:/bin"
export FAKEFS_BIN="${TMP}/nonexistent-fakefs"
if bash "${ROOT_DIR}/scripts/dependency_mount_fakefs.sh"; then
  :
else
  echo "FAIL: prolog expected exit 0 under SLURM_JOB_ID with missing fakefs" >&2
  exit 1
fi
if ! grep -q "ERROR reason=MISSING_FAKEFS" "${DEPENDENCY_STORAGE_DIR}/hook-errors.log"; then
  echo "FAIL: missing MISSING_FAKEFS line in hook-errors.log" >&2
  cat "${DEPENDENCY_STORAGE_DIR}/hook-errors.log" 2>/dev/null || true
  exit 1
fi

# Epilog: invalid flag must exit 0 and append BAD_CLI
export SLURM_HOOK_SOFT_FAIL=""
if bash "${ROOT_DIR}/scripts/dependency_mount_cleanup_fakefs.sh" --not-a-real-flag; then
  :
else
  echo "FAIL: epilog expected exit 0 under SLURM_JOB_ID with bad CLI" >&2
  exit 1
fi
if ! grep -q "ERROR reason=BAD_CLI" "${DEPENDENCY_STORAGE_DIR}/hook-errors.log"; then
  echo "FAIL: missing BAD_CLI line in hook-errors.log" >&2
  exit 1
fi

# Non-Slurm: missing fakefs should still fail (exit 1)
unset SLURM_JOB_ID
unset SLURM_HOOK_SOFT_FAIL
export FAKEFS_BIN="${TMP}/nonexistent-fakefs"
set +e
bash "${ROOT_DIR}/scripts/dependency_mount_fakefs.sh" 2>/dev/null
rc=$?
set -e
if [[ "${rc}" -eq 0 ]]; then
  echo "FAIL: prolog expected non-zero without SLURM_JOB_ID when fakefs missing" >&2
  exit 1
fi

echo "OK: slurm_fakefs_hook_soft_fail_test"
