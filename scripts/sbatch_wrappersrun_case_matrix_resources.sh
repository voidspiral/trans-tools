#!/bin/bash
#SBATCH --job-name=wrappersrun-matrix-resources
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --time=00:00:20
#SBATCH --output=logs/wrappersrun-matrix-resources-%j.out
#SBATCH --error=logs/wrappersrun-matrix-resources-%j.err
set -euo pipefail

if [[ -n "${WRAPPERSRUN_PROJECT_DIR:-}" ]]; then
  COMMON_SCRIPT="${WRAPPERSRUN_PROJECT_DIR}/scripts/sbatch_wrappersrun_case_common.sh"
elif [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
  COMMON_SCRIPT="${SLURM_SUBMIT_DIR}/scripts/sbatch_wrappersrun_case_common.sh"
else
  COMMON_SCRIPT="/home/code/trans-tools/scripts/sbatch_wrappersrun_case_common.sh"
fi
source "${COMMON_SCRIPT}"

CASE_TAG="CASE matrix-resources"
PROJECT_DIR="$(resolve_project_dir)"
mkdir -p "${PROJECT_DIR}/logs"
MPI_BIN="$(resolve_mpi_bin "${PROJECT_DIR}")"
setup_case_env

echo "[${CASE_TAG}] [$(date '+%F %T')] STAGE=deps-precheck"
ls -la /tmp/dependencies || true
stage_mount_check "${CASE_TAG}"

echo "[${CASE_TAG}] [$(date '+%F %T')] STAGE=wrappersrun"
"${PROJECT_DIR}/scripts/wrappersrun.sh" -N 1 -n 2 -c 1 --kill-on-bad-exit=1 "${MPI_BIN}"
stage_pre_epilog_check "${CASE_TAG}"
echo "[${CASE_TAG}] [$(date '+%F %T')] STAGE=mpi-finished"
