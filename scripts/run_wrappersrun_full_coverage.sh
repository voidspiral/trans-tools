#!/bin/bash
# Wrappersrun extended validation: matrix + vol8 fixture provenance + salloc split-flow + error paths.
set -euo pipefail

SBATCH_CASE_MAX_SEC="${SBATCH_CASE_MAX_SEC:-25}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${PROJECT_DIR}/logs"
mkdir -p "${LOG_DIR}"

if ! command -v timeout >/dev/null 2>&1; then
  echo "ERROR: timeout(1) is required (SBATCH_CASE_MAX_SEC=${SBATCH_CASE_MAX_SEC})" >&2
  exit 1
fi

chmod +x "${PROJECT_DIR}/scripts/wrappersrun_fixture_patch_deps_tar.sh" 2>/dev/null || true
chmod +x "${PROJECT_DIR}/scripts/mock_trans_tools_deps_fail.sh" 2>/dev/null || true

echo "[full-coverage] building vol8 fixture (baseline on /vol8, staged bytes via post-deps tar patch)"
bash "${PROJECT_DIR}/scripts/build_wrappersrun_vol8_fixture.sh"

export WRAPPERSRUN_MATRIX_PROVENANCE=true
echo "[full-coverage] running srun matrix with WRAPPERSRUN_MATRIX_PROVENANCE=true"
bash "${PROJECT_DIR}/scripts/run_sbatch_wrappersrun_srun_matrix.sh"

validate_fixture_log() {
  local out_file="$1"
  awk '/STAGE=wrappersrun/ {found=1} END {exit(found?0:1)}' "${out_file}" || return 1
  awk '/STAGE=pre-epilog-mount-check/ {found=1} END {exit(found?0:1)}' "${out_file}" || return 1
  awk '/STAGE=mpi-finished/ {found=1} END {exit(found?0:1)}' "${out_file}" || return 1
  awk '/WRAPPER_FIXTURE_MARKER=WR_FIXTURE_MARKER_FAKEFS_STAGED/ {found=1} END {exit(found?0:1)}' "${out_file}" || return 1
  awk '/STAGE=pre-epilog-mount-check/,/STAGE=mpi-finished/ { if ($0 ~ /\.fakefs/) { found=1 } } END { exit(found ? 0 : 1) }' "${out_file}" || return 1
}

echo "[full-coverage] submitting dedicated vol8 fixture provenance sbatch"
export WRAPPERSRUN_FAKEFS_DIRECT_MODE=0
export FAKEFS_DIRECT_MODE=0
set +e
job_id="$(timeout "${SBATCH_CASE_MAX_SEC}" sbatch --wait --parsable --chdir "${PROJECT_DIR}" \
  --export=ALL,WRAPPERSRUN_PROJECT_DIR="${PROJECT_DIR}",WRAPPERSRUN_FAKEFS_DIRECT_MODE=0,FAKEFS_DIRECT_MODE=0 \
  "${PROJECT_DIR}/scripts/sbatch_wrappersrun_case_vol8_fixture_provenance.sh")"
rc=$?
set -e
if [[ "${rc}" -eq 124 ]]; then
  echo "ERROR: sbatch timeout for vol8 fixture case" >&2
  exit 124
fi
if [[ "${rc}" -ne 0 ]]; then
  echo "ERROR: sbatch failed for vol8 fixture case (rc=${rc} out=${job_id})" >&2
  exit "${rc}"
fi

fx_out="${LOG_DIR}/wrappersrun-vol8-fixture-${job_id}.out"
if [[ ! -f "${fx_out}" ]]; then
  echo "ERROR: missing ${fx_out}" >&2
  exit 1
fi
if awk '/CASE_RESULT=SKIP/ {found=1} END {exit(found?0:1)}' "${fx_out}"; then
  echo "[SKIP] vol8 fixture case (fixture_binary_missing?)"
else
  if ! validate_fixture_log "${fx_out}"; then
    echo "ERROR: vol8 fixture log validation failed: ${fx_out}" >&2
    exit 1
  fi
fi

assert_contains() {
  local hay="$1"
  local needle="$2"
  local label="$3"
  if [[ "${hay}" != *"${needle}"* ]]; then
    echo "ERROR: ${label}: expected substring missing: ${needle}" >&2
    exit 1
  fi
}

echo "[full-coverage] direct wrappersrun without node resolution (expect exit 1)"
set +e
out_miss="$(env -u SLURM_NODELIST -u SLURM_JOB_NODELIST -u WRAPPERSRUN_DEPS_NODES \
  bash "${PROJECT_DIR}/scripts/wrappersrun.sh" -N1 -n1 /bin/true 2>&1)"
rc_miss=$?
set -e
[[ "${rc_miss}" -eq 1 ]] || {
  echo "ERROR: expected exit 1 for missing deps nodes, got ${rc_miss}" >&2
  exit 1
}
assert_contains "${out_miss}" "missing nodes for deps" "direct no-nodes"

echo "[full-coverage] trans-tools deps failure must not launch MPI (mock exit 77)"
set +e
out_deps="$(WRAPPERSRUN_TRANS_TOOLS_BIN="${PROJECT_DIR}/scripts/mock_trans_tools_deps_fail.sh" \
  WRAPPERSRUN_DEPS_NODES="$(hostname)" \
  bash "${PROJECT_DIR}/scripts/wrappersrun.sh" -w "$(hostname)" -N1 -n1 "$(command -v true)" 2>&1)"
rc_deps=$?
set -e
[[ "${rc_deps}" -eq 77 ]] || {
  echo "ERROR: expected mock deps rc 77, got ${rc_deps}" >&2
  exit 1
}
assert_contains "${out_deps}" "mock_trans_tools_deps_fail" "deps failure marker"
if echo "${out_deps}" | grep -q "MPI Test completed successfully!"; then
  echo "ERROR: deps failure case must not reach MPI success" >&2
  exit 1
fi

echo "[full-coverage] srun non-zero exit passthrough (expect 44)"
set +e
out_run="$(WRAPPERSRUN_ENABLE_DEPS=false bash "${PROJECT_DIR}/scripts/wrappersrun.sh" -N1 -n1 bash -c 'exit 44' 2>&1)"
rc_run=$?
set -e
[[ "${rc_run}" -eq 44 ]] || {
  echo "ERROR: expected srun passthrough exit 44, got ${rc_run}" >&2
  exit 1
}

echo "[full-coverage] missing WRAPPERSRUN_TRANS_TOOLS_BIN diagnostic"
set +e
out_bin="$(env -u SLURM_NODELIST -u SLURM_JOB_NODELIST \
  WRAPPERSRUN_TRANS_TOOLS_BIN="${PROJECT_DIR}/no-such-trans-tools-$$" \
  bash "${PROJECT_DIR}/scripts/wrappersrun.sh" -N1 -n1 /bin/true 2>&1)"
rc_bin=$?
set -e
[[ "${rc_bin}" -eq 1 ]] || {
  echo "ERROR: expected exit 1 for missing trans-tools, got ${rc_bin}" >&2
  exit 1
}
assert_contains "${out_bin}" "WRAPPERSRUN_TRANS_TOOLS_BIN" "missing trans-tools message"

echo "[full-coverage] WRAPPERSRUN_SRUN_MPI injection (fake srun argv capture)"
REAL_SRUN="$(command -v srun)"
FAKE_BINDIR="$(mktemp -d)"
cleanup_fake_srun() { rm -rf "${FAKE_BINDIR}"; }
trap cleanup_fake_srun EXIT
cat > "${FAKE_BINDIR}/srun" <<EOF
#!/bin/bash
if [[ "\$*" != *--mpi=pmi2* ]]; then
  echo "fake-srun: missing --mpi=pmi2 in: \$*" >&2
  exit 99
fi
exec "${REAL_SRUN}" "\$@"
EOF
chmod +x "${FAKE_BINDIR}/srun"
set +e
out_mpi="$(PATH="${FAKE_BINDIR}:${PATH}" WRAPPERSRUN_ENABLE_DEPS=false WRAPPERSRUN_SRUN_MPI=pmi2 \
  bash "${PROJECT_DIR}/scripts/wrappersrun.sh" -N1 -n1 "$(command -v true)" 2>&1)"
rc_mpi=$?
set -e
trap - EXIT
rm -rf "${FAKE_BINDIR}"
[[ "${rc_mpi}" -eq 0 ]] || {
  echo "ERROR: mpi injection probe failed rc=${rc_mpi} out=${out_mpi}" >&2
  exit 1
}

run_salloc_split_flow() {
  if ! command -v salloc >/dev/null 2>&1; then
    echo "[full-coverage] SKIP salloc-split-flow: salloc not found"
    return 0
  fi
  chmod +x "${PROJECT_DIR}/scripts/wrappersrun_salloc_split_driver.sh" 2>/dev/null || true
  export WRAPPERSRUN_PROJECT_DIR="${PROJECT_DIR}"
  set +e
  timeout 180 salloc --no-shell -N1 -n1 -t00:06:00 \
    bash "${PROJECT_DIR}/scripts/wrappersrun_salloc_split_driver.sh" 2>&1
  rc=$?
  set -e
  if [[ "${rc}" -eq 124 ]]; then
    echo "[full-coverage] SKIP salloc-split-flow: timed out (rc 124)"
    return 0
  fi
  if [[ "${rc}" -ne 0 ]]; then
    echo "ERROR: salloc split-flow failed rc=${rc}" >&2
    exit 1
  fi
}

run_salloc_split_flow

echo "[full-coverage] all stages completed."
