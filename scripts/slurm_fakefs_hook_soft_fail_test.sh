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
unset SLURM_HOOK_SOFT_FAIL
mkdir -p "${DEPENDENCY_STORAGE_DIR}"
echo "retain-me" > "${DEPENDENCY_STORAGE_DIR}/retain.marker"

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
if ! grep -q "job=softfail-test-job" "${DEPENDENCY_STORAGE_DIR}/hook-errors.log"; then
  echo "FAIL: missing SLURM_JOB_ID correlation field in prolog log line" >&2
  exit 1
fi
if [[ ! -f "${DEPENDENCY_STORAGE_DIR}/retain.marker" ]]; then
  echo "FAIL: prolog error should not remove dependency storage marker" >&2
  exit 1
fi

# Epilog: force an unmount error path; cleanup must exit 0, log ERROR, and keep storage.
mkdir -p "${DEPENDENCY_STORAGE_DIR}/.fakefs"
cat > "${DEPENDENCY_STORAGE_DIR}/.fakefs/fail.state" <<EOF
MOUNTPOINT=${TMP}/not-mounted-path
EOF
if bash "${ROOT_DIR}/scripts/dependency_mount_cleanup_fakefs.sh" --remove-dirs; then
  :
else
  echo "FAIL: epilog expected exit 0 under SLURM_JOB_ID during unmount failure" >&2
  exit 1
fi
if ! grep -q "ERROR reason=UNMOUNT" "${DEPENDENCY_STORAGE_DIR}/hook-errors.log"; then
  echo "FAIL: missing UNMOUNT line in hook-errors.log" >&2
  exit 1
fi
if ! grep -q "node=test-node" "${DEPENDENCY_STORAGE_DIR}/hook-errors.log"; then
  echo "FAIL: missing node correlation field in epilog log line" >&2
  exit 1
fi
if [[ ! -d "${DEPENDENCY_STORAGE_DIR}" ]]; then
  echo "FAIL: epilog error path must not delete dependency storage dir" >&2
  exit 1
fi
if [[ ! -f "${DEPENDENCY_STORAGE_DIR}/retain.marker" ]]; then
  echo "FAIL: epilog error path must retain marker under dependency storage" >&2
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

# Slurm + SLURM_HOOK_SOFT_FAIL=0: strict override (missing fakefs must exit non-zero)
export SLURM_JOB_ID="strict-override-job"
export SLURM_HOOK_SOFT_FAIL="0"
export DEPENDENCY_STORAGE_DIR="${TMP}/deps-strict"
mkdir -p "${DEPENDENCY_STORAGE_DIR}"
export FAKEFS_BIN="${TMP}/nonexistent-fakefs-2"
set +e
bash "${ROOT_DIR}/scripts/dependency_mount_fakefs.sh" >/dev/null 2>&1
rc_strict=$?
set -e
if [[ "${rc_strict}" -eq 0 ]]; then
  echo "FAIL: expected non-zero when SLURM_JOB_ID set but SLURM_HOOK_SOFT_FAIL=0 and fakefs missing" >&2
  exit 1
fi

echo "OK: slurm_fakefs_hook_soft_fail_test"
