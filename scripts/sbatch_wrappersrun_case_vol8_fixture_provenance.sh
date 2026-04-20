#!/bin/bash
#SBATCH --job-name=wrappersrun-vol8-fixture
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --time=00:00:20
#SBATCH --output=logs/wrappersrun-vol8-fixture-%j.out
#SBATCH --error=logs/wrappersrun-vol8-fixture-%j.err
set -euo pipefail

if [[ -n "${WRAPPERSRUN_PROJECT_DIR:-}" ]]; then
  COMMON_SCRIPT="${WRAPPERSRUN_PROJECT_DIR}/scripts/sbatch_wrappersrun_case_common.sh"
elif [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
  COMMON_SCRIPT="${SLURM_SUBMIT_DIR}/scripts/sbatch_wrappersrun_case_common.sh"
else
  COMMON_SCRIPT="/home/code/trans-tools/scripts/sbatch_wrappersrun_case_common.sh"
fi
source "${COMMON_SCRIPT}"

CASE_TAG="CASE vol8-fixture-provenance"
PROJECT_DIR="$(resolve_project_dir)"
mkdir -p "${PROJECT_DIR}/logs"
dep_store="${WRAPPERSRUN_DEPS_DEST:-/tmp/dependencies}"
if [[ -x "${PROJECT_DIR}/scripts/dependency_mount_cleanup_fakefs.sh" ]]; then
  env -u SLURM_JOB_ID -u SLURM_JOBID SLURM_HOOK_SOFT_FAIL=1 \
    bash "${PROJECT_DIR}/scripts/dependency_mount_cleanup_fakefs.sh" --keep-storage "${dep_store}" 2>/dev/null || true
fi
rm -f "${dep_store}"/*_so.tar 2>/dev/null || true
setup_case_env

export WRAPPERSRUN_MPI_BIN="${PROJECT_DIR}/bin/wrappersrun_fixture_prog"
export WRAPPERSRUN_FIXTURE_STAGED_SO="${PROJECT_DIR}/build/wr_fixture/libwr_fixture_staged.so"
export WRAPPERSRUN_POST_DEPS_HOOK="bash ${PROJECT_DIR}/scripts/wrappersrun_fixture_patch_deps_tar.sh && FAKEFS_DIRECT_MODE=0 bash ${PROJECT_DIR}/scripts/dependency_mount_fakefs.sh ${dep_store}"
export WRAPPERSRUN_FAKEFS_DIRECT_MODE=0
export WRAPPERSRUN_PROVENANCE_UPPER="${dep_store}/.fakefs/vol8_wr_run_fixture_lib_upper"
if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
  export LD_LIBRARY_PATH="${WRAPPERSRUN_PROVENANCE_UPPER}:${LD_LIBRARY_PATH}"
else
  export LD_LIBRARY_PATH="${WRAPPERSRUN_PROVENANCE_UPPER}"
fi

if [[ ! -x "${WRAPPERSRUN_MPI_BIN}" ]]; then
  echo "[${CASE_TAG}] [$(date '+%F %T')] CASE_RESULT=SKIP reason=fixture_binary_missing" >&2
  exit 0
fi

echo "[${CASE_TAG}] [$(date '+%F %T')] STAGE=deps-precheck"
ls -la /tmp/dependencies || true
stage_mount_check "${CASE_TAG}"

echo "[${CASE_TAG}] [$(date '+%F %T')] STAGE=wrappersrun"
"${PROJECT_DIR}/scripts/wrappersrun.sh" -N 1 -n 2 -c 1 --kill-on-bad-exit=1 "${WRAPPERSRUN_MPI_BIN}"
stage_pre_epilog_check "${CASE_TAG}"
echo "[${CASE_TAG}] [$(date '+%F %T')] STAGE=mpi-finished"
