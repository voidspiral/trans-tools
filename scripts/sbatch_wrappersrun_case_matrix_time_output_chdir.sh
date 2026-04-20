#!/bin/bash
#SBATCH --job-name=wrappersrun-matrix-time-io
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --time=00:00:20
#SBATCH --output=logs/wrappersrun-matrix-time-io-%j.out
#SBATCH --error=logs/wrappersrun-matrix-time-io-%j.err
set -euo pipefail

if [[ -n "${WRAPPERSRUN_PROJECT_DIR:-}" ]]; then
  COMMON_SCRIPT="${WRAPPERSRUN_PROJECT_DIR}/scripts/sbatch_wrappersrun_case_common.sh"
elif [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
  COMMON_SCRIPT="${SLURM_SUBMIT_DIR}/scripts/sbatch_wrappersrun_case_common.sh"
else
  COMMON_SCRIPT="/home/code/trans-tools/scripts/sbatch_wrappersrun_case_common.sh"
fi
source "${COMMON_SCRIPT}"

CASE_TAG="CASE matrix-time-io"
PROJECT_DIR="$(resolve_project_dir)"
mkdir -p "${PROJECT_DIR}/logs"
MPI_BIN="$(resolve_mpi_bin "${PROJECT_DIR}")"
setup_case_env

runtime_log="${PROJECT_DIR}/logs/matrix-time-io-srun-${SLURM_JOB_ID:-manual}.log"

echo "[${CASE_TAG}] [$(date '+%F %T')] STAGE=deps-precheck runtime_log=${runtime_log}"
ls -la /tmp/dependencies || true
stage_mount_check "${CASE_TAG}"

echo "[${CASE_TAG}] [$(date '+%F %T')] STAGE=wrappersrun"
"${PROJECT_DIR}/scripts/wrappersrun.sh" -n 2 -t 00:00:10 -o "${runtime_log}" --chdir "${PROJECT_DIR}" "${MPI_BIN}"
echo "[${CASE_TAG}] [$(date '+%F %T')] STAGE=runtime-log-check path=${runtime_log}"
if [[ -f "${runtime_log}" ]]; then
  cat "${runtime_log}"
fi
stage_pre_epilog_check "${CASE_TAG}"
echo "[${CASE_TAG}] [$(date '+%F %T')] STAGE=mpi-finished"
