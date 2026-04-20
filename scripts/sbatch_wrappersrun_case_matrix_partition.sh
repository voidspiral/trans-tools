#!/bin/bash
#SBATCH --job-name=wrappersrun-matrix-partition
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --time=00:00:20
#SBATCH --output=logs/wrappersrun-matrix-partition-%j.out
#SBATCH --error=logs/wrappersrun-matrix-partition-%j.err
set -euo pipefail

if [[ -n "${WRAPPERSRUN_PROJECT_DIR:-}" ]]; then
  COMMON_SCRIPT="${WRAPPERSRUN_PROJECT_DIR}/scripts/sbatch_wrappersrun_case_common.sh"
elif [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
  COMMON_SCRIPT="${SLURM_SUBMIT_DIR}/scripts/sbatch_wrappersrun_case_common.sh"
else
  COMMON_SCRIPT="/home/code/trans-tools/scripts/sbatch_wrappersrun_case_common.sh"
fi
source "${COMMON_SCRIPT}"

CASE_TAG="CASE matrix-partition"
PROJECT_DIR="$(resolve_project_dir)"
mkdir -p "${PROJECT_DIR}/logs"
MPI_BIN="$(resolve_mpi_bin "${PROJECT_DIR}")"
setup_case_env

partition_name="${WRAPPERSRUN_TEST_PARTITION:-}"
if [[ -z "${partition_name}" ]]; then
  partition_name="$(sinfo -h -o "%P" 2>/dev/null | awk 'NR==1 {gsub(/\*/, "", $1); print $1}')"
fi
if [[ -z "${partition_name}" ]]; then
  case_skip "${CASE_TAG}" "partition_not_available"
fi

echo "[${CASE_TAG}] [$(date '+%F %T')] STAGE=deps-precheck partition=${partition_name}"
ls -la /tmp/dependencies || true
stage_mount_check "${CASE_TAG}"

echo "[${CASE_TAG}] [$(date '+%F %T')] STAGE=wrappersrun"
"${PROJECT_DIR}/scripts/wrappersrun.sh" -n 2 -p "${partition_name}" "${MPI_BIN}"
stage_pre_epilog_check "${CASE_TAG}"
echo "[${CASE_TAG}] [$(date '+%F %T')] STAGE=mpi-finished"
