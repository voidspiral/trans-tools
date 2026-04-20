#!/bin/bash
# Local single-node Slurm validation entrypoint.
# Test assumption: management node and login node are the same local machine.
# In production HPC clusters, scheduler/login/compute roles are split across multiple nodes,
# so treat this script as functional validation only, not a topology/performance benchmark.
set -euo pipefail

# sbatch default export propagates submitter WRAPPERSRUN_* into jobs and overrides case defaults.
unset WRAPPERSRUN_DEPS_WIDTH WRAPPERSRUN_DEPS_BUFFER WRAPPERSRUN_DEPS_PORT \
  WRAPPERSRUN_DEPS_AUTO_CLEAN WRAPPERSRUN_DEPS_INSECURE \
  WRAPPERSRUN_DEPS_NODES WRAPPERSRUN_DEPS_PROGRAM \
  WRAPPERSRUN_FAKEFS_DIRECT_MODE WRAPPERSRUN_LAUNCHER \
  WRAPPERSRUN_SRUN_MPI WRAPPERSRUN_TRANS_TOOLS_BIN WRAPPERSRUN_ENABLE_DEPS \
  WRAPPERSRUN_DEPS_DEST WRAPPERSRUN_DEPS_MIN_SIZE_MB WRAPPERSRUN_DEPS_FILTER_PREFIX \
  WRAPPERSRUN_MPI_APP_DIR WRAPPERSRUN_MPI_BIN || true

SBATCH_CASE_MAX_SEC="${SBATCH_CASE_MAX_SEC:-15}"
WRAPPERSRUN_INCLUDE_MATRIX="${WRAPPERSRUN_INCLUDE_MATRIX:-false}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${PROJECT_DIR}/logs"
mkdir -p "${LOG_DIR}"

if ! command -v timeout >/dev/null 2>&1; then
  echo "ERROR: timeout(1) is required to enforce SBATCH_CASE_MAX_SEC=${SBATCH_CASE_MAX_SEC}" >&2
  exit 1
fi

cases=(
  "scripts/sbatch_wrappersrun_test.sh"
  "scripts/sbatch_wrappersrun_case_nodelist.sh"
  "scripts/sbatch_wrappersrun_case_custom_deps.sh"
)

submitted=()

for case_script in "${cases[@]}"; do
  mkdir -p /tmp/dependencies
  chmod -R a+rwx /tmp/dependencies 2>/dev/null || chmod 777 /tmp/dependencies || true
  abs_case="${PROJECT_DIR}/${case_script}"
  if [[ ! -f "${abs_case}" ]]; then
    echo "missing case script: ${abs_case}" >&2
    exit 1
  fi
  wrappers_calls="$(awk '/^[[:space:]]*"\$\{PROJECT_DIR\}\/scripts\/wrappersrun\.sh"/ {count++} END {print count+0}' "${abs_case}")"
  if [[ "${wrappers_calls}" -ne 1 ]]; then
    echo "invalid wrappersrun invocation count in ${case_script}: ${wrappers_calls} (expected 1)" >&2
    exit 1
  fi
  echo "Submitting ${case_script} (sbatch --wait capped at ${SBATCH_CASE_MAX_SEC}s wall-clock)"
  set +e
  job_id="$(timeout "${SBATCH_CASE_MAX_SEC}" sbatch --wait --parsable --chdir "${PROJECT_DIR}" --export=ALL,WRAPPERSRUN_PROJECT_DIR="${PROJECT_DIR}" "${abs_case}")"
  rc=$?
  set -e
  if [[ "${rc}" -eq 124 ]]; then
    echo "DEBUG: sbatch --wait for ${case_script} exceeded ${SBATCH_CASE_MAX_SEC}s (timeout exit 124). Check squeue, sacct, slurmd.log, and ${LOG_DIR}/*.out" >&2
    exit 124
  fi
  if [[ "${rc}" -ne 0 ]]; then
    echo "DEBUG: sbatch failed for ${case_script} (exit ${rc}). Parsed job id line: ${job_id}" >&2
    exit "${rc}"
  fi
  submitted+=("${job_id}:${case_script}")
done

echo
echo "All sbatch cases completed:"
for item in "${submitted[@]}"; do
  echo "  ${item}"
done

echo
echo "Validating output markers..."
for item in "${submitted[@]}"; do
  job_id="${item%%:*}"
  case_script="${item#*:}"
  case "${case_script}" in
    scripts/sbatch_wrappersrun_test.sh) out_prefix="wrappersrun-test" ;;
    scripts/sbatch_wrappersrun_case_nodelist.sh) out_prefix="wrappersrun-case-nodelist" ;;
    scripts/sbatch_wrappersrun_case_custom_deps.sh) out_prefix="wrappersrun-case-custom" ;;
    *)
      echo "unknown case script when resolving output prefix: ${case_script}" >&2
      exit 1
      ;;
  esac
  out_file="${LOG_DIR}/${out_prefix}-${job_id}.out"
  if [[ -z "${out_file}" ]]; then
    echo "missing output log for job ${job_id} (${case_script}) under ${LOG_DIR}" >&2
    exit 1
  fi
  if [[ ! -f "${out_file}" ]]; then
    echo "missing output log file ${out_file} for job ${job_id} (${case_script})" >&2
    exit 1
  fi
  awk '/STAGE=wrappersrun/ {found=1} END {exit(found?0:1)}' "${out_file}" || { echo "missing wrappersrun marker in ${out_file}" >&2; exit 1; }
  awk '/STAGE=pre-epilog-mount-check/ {stage=1; next} stage && /fakefs/ && $NF ~ /^\/vol8\// {found=1} END {exit(found?0:1)}' "${out_file}" || { echo "missing pre-epilog fakefs mount under /vol8 in ${out_file}" >&2; exit 1; }
  awk '/STAGE=mpi-finished/ {found=1} END {exit(found?0:1)}' "${out_file}" || { echo "missing mpi marker in ${out_file}" >&2; exit 1; }
  awk '/Step 1: Analyze program dependencies|Analyze program dependencies/ {found=1} END {exit(found?0:1)}' "${out_file}" || { echo "missing trans-tools deps marker in ${out_file}" >&2; exit 1; }
  awk '/MPI Test completed successfully!/ {found=1} END {exit(found?0:1)}' "${out_file}" || { echo "missing MPI success marker in ${out_file}" >&2; exit 1; }
done

echo "All case logs contain expected wrappersrun/mpi markers."

if [[ "${WRAPPERSRUN_INCLUDE_MATRIX}" == "true" ]]; then
  echo
  echo "Running optional wrappersrun srun matrix suite..."
  bash "${PROJECT_DIR}/scripts/run_sbatch_wrappersrun_srun_matrix.sh"
fi
