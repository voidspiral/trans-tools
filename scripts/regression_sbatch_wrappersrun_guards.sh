#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass() {
  echo "[PASS] $*"
}

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

assert_contains() {
  local text="$1"
  local want="$2"
  local label="$3"
  if [[ "${text}" == *"${want}"* ]]; then
    pass "${label}"
  else
    fail "${label}: missing '${want}'"
  fi
}

# Guard 1: no-umount diagnostic must use bin/trans-tools (or WRAPPERSRUN_TRANS_TOOLS_BIN override).
diag_text="$(python3 - <<'PY'
from pathlib import Path
print(Path("/home/code/trans-tools/scripts/run_sbatch_no_umount_diagnostic.sh").read_text())
PY
)"
assert_contains "${diag_text}" 'TRANS_TOOLS_BIN="${WRAPPERSRUN_TRANS_TOOLS_BIN:-${PROJECT_DIR}/bin/trans-tools}"' "diagnostic uses bin/trans-tools default"

# Guard 2: wrappersrun must fail clearly when -n/--ntasks value is missing.
set +e
out_n="$(WRAPPERSRUN_ENABLE_DEPS=false WRAPPERSRUN_LAUNCHER=mpirun "${PROJECT_DIR}/scripts/wrappersrun.sh" -n 2>&1)"
rc_n=$?
set -e
[[ "${rc_n}" -eq 2 ]] || fail "wrappersrun -n missing value exit code expected 2, got ${rc_n}"
assert_contains "${out_n}" "missing value for -n" "wrappersrun -n missing value message"

set +e
out_ntasks="$(WRAPPERSRUN_ENABLE_DEPS=false WRAPPERSRUN_LAUNCHER=mpirun "${PROJECT_DIR}/scripts/wrappersrun.sh" --ntasks 2>&1)"
rc_ntasks=$?
set -e
[[ "${rc_ntasks}" -eq 2 ]] || fail "wrappersrun --ntasks missing value exit code expected 2, got ${rc_ntasks}"
assert_contains "${out_ntasks}" "missing value for --ntasks" "wrappersrun --ntasks missing value message"

# Guard 3: sbatch runner must force project working directory and export project root.
runner_text="$(python3 - <<'PY'
from pathlib import Path
print(Path("/home/code/trans-tools/scripts/run_sbatch_wrappersrun_cases.sh").read_text())
PY
)"
assert_contains "${runner_text}" '--chdir "${PROJECT_DIR}"' "runner sets sbatch --chdir"
assert_contains "${runner_text}" '--export=ALL,WRAPPERSRUN_PROJECT_DIR="${PROJECT_DIR}"' "runner exports WRAPPERSRUN_PROJECT_DIR"

echo "All wrappersrun/sbatch guard regressions passed."
