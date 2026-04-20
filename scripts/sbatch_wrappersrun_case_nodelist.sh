#!/bin/bash
# Local single-node sbatch case (explicit nodelist path).
# Test assumption: management node and login node are the same local machine.
# Real HPC deployments run scheduler/login/compute on separate nodes; this case validates
# nodelist parameter wiring in wrappersrun, not multi-node scheduling behavior.
#SBATCH --job-name=wrappersrun-case-nodelist
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --time=00:00:15
#SBATCH --output=logs/wrappersrun-case-nodelist-%j.out
#SBATCH --error=logs/wrappersrun-case-nodelist-%j.err

set -euo pipefail

if [[ -n "${WRAPPERSRUN_PROJECT_DIR:-}" && -x "${WRAPPERSRUN_PROJECT_DIR}/scripts/wrappersrun.sh" ]]; then
  PROJECT_DIR="${WRAPPERSRUN_PROJECT_DIR}"
elif [[ -n "${SLURM_SUBMIT_DIR:-}" && -x "${SLURM_SUBMIT_DIR}/scripts/wrappersrun.sh" ]]; then
  PROJECT_DIR="${SLURM_SUBMIT_DIR}"
else
  PROJECT_DIR="/home/code/trans-tools"
fi
if [[ -n "${WRAPPERSRUN_MPI_APP_DIR:-}" ]]; then
  MPI_BIN="${WRAPPERSRUN_MPI_APP_DIR}/mpi_test"
elif [[ -n "${WRAPPERSRUN_MPI_BIN:-}" ]]; then
  MPI_BIN="${WRAPPERSRUN_MPI_BIN}"
else
  MPI_BIN="${PROJECT_DIR}/bin/mpi_test"
fi
FALLBACK_MPI_BIN="/home/code/trans-tools/test_mpi_app/mpi_test"

if [[ ! -x "${MPI_BIN}" && -x "${FALLBACK_MPI_BIN}" ]]; then
  echo "WARN: ${MPI_BIN} not found, fallback to ${FALLBACK_MPI_BIN}" >&2
  MPI_BIN="${FALLBACK_MPI_BIN}"
fi
if [[ ! -x "${MPI_BIN}" ]]; then
  echo "ERROR: ${MPI_BIN} not found or not executable" >&2
  echo 'Expected default: ${PROJECT_DIR}/bin/mpi_test (or set WRAPPERSRUN_MPI_BIN / WRAPPERSRUN_MPI_APP_DIR)' >&2
  exit 1
fi

mkdir -p "${PROJECT_DIR}/logs"
echo "[CASE nodelist] [$(date '+%F %T')] STAGE=deps-precheck"
ls -la /tmp/dependencies || true

export WRAPPERSRUN_DEPS_DEST=/tmp/dependencies
export WRAPPERSRUN_DEPS_MIN_SIZE_MB=0
export WRAPPERSRUN_DEPS_FILTER_PREFIX=/vol8
export WRAPPERSRUN_LAUNCHER=mpirun
export WRAPPERSRUN_DEPS_NODES="${SLURM_NODELIST:-${SLURM_JOB_NODELIST:-DESKTOP-N3EHMFF}}"

echo "[CASE nodelist] [$(date '+%F %T')] STAGE=mount-check"
df -h
findmnt -t fuse.fakefs || true

echo "[CASE nodelist] [$(date '+%F %T')] STAGE=wrappersrun"
"${PROJECT_DIR}/scripts/wrappersrun.sh" -n 2 -w "${WRAPPERSRUN_DEPS_NODES}" "${MPI_BIN}"
echo "[CASE nodelist] [$(date '+%F %T')] STAGE=pre-epilog-mount-check"
df -h
findmnt -t fuse.fakefs || true
echo "[CASE nodelist] [$(date '+%F %T')] STAGE=mpi-finished"
