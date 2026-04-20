#!/bin/bash
set -euo pipefail

resolve_project_dir() {
  if [[ -n "${WRAPPERSRUN_PROJECT_DIR:-}" && -x "${WRAPPERSRUN_PROJECT_DIR}/scripts/wrappersrun.sh" ]]; then
    echo "${WRAPPERSRUN_PROJECT_DIR}"
    return
  fi
  if [[ -n "${SLURM_SUBMIT_DIR:-}" && -x "${SLURM_SUBMIT_DIR}/scripts/wrappersrun.sh" ]]; then
    echo "${SLURM_SUBMIT_DIR}"
    return
  fi
  echo "/home/code/trans-tools"
}

resolve_mpi_bin() {
  local project_dir="$1"
  local mpi_bin=""
  local fallback_mpi_bin="${project_dir}/test_mpi_app/mpi_test"
  if [[ -n "${WRAPPERSRUN_MPI_APP_DIR:-}" ]]; then
    mpi_bin="${WRAPPERSRUN_MPI_APP_DIR}/mpi_test"
  elif [[ -n "${WRAPPERSRUN_MPI_BIN:-}" ]]; then
    mpi_bin="${WRAPPERSRUN_MPI_BIN}"
  else
    mpi_bin="${project_dir}/bin/mpi_test"
  fi

  if [[ ! -x "${mpi_bin}" && -x "${fallback_mpi_bin}" ]]; then
    echo "WARN: ${mpi_bin} not found, fallback to ${fallback_mpi_bin}" >&2
    mpi_bin="${fallback_mpi_bin}"
  fi
  if [[ ! -x "${mpi_bin}" ]]; then
    echo "ERROR: ${mpi_bin} not found or not executable" >&2
    echo "Expected default: ${project_dir}/bin/mpi_test (or set WRAPPERSRUN_MPI_BIN / WRAPPERSRUN_MPI_APP_DIR)" >&2
    return 1
  fi
  echo "${mpi_bin}"
}

setup_case_env() {
  export WRAPPERSRUN_DEPS_DEST=/tmp/dependencies
  export WRAPPERSRUN_DEPS_MIN_SIZE_MB=0
  export WRAPPERSRUN_DEPS_FILTER_PREFIX=/vol8
  export WRAPPERSRUN_LAUNCHER=srun
  if [[ -n "${WRAPPERSRUN_TEST_SRUN_MPI:-}" ]]; then
    export WRAPPERSRUN_SRUN_MPI="${WRAPPERSRUN_TEST_SRUN_MPI}"
  fi
  local prov
  prov="$(echo "${WRAPPERSRUN_MATRIX_PROVENANCE:-}" | tr '[:upper:]' '[:lower:]')"
  if [[ "${prov}" == "1" || "${prov}" == "true" || "${prov}" == "yes" ]]; then
    local pd="${PROJECT_DIR:-$(resolve_project_dir)}"
    local dest="${WRAPPERSRUN_DEPS_DEST:-/tmp/dependencies}"
    if [[ -x "${pd}/scripts/dependency_mount_cleanup_fakefs.sh" ]]; then
      env -u SLURM_JOB_ID -u SLURM_JOBID SLURM_HOOK_SOFT_FAIL=1 \
        bash "${pd}/scripts/dependency_mount_cleanup_fakefs.sh" --keep-storage "${dest}" 2>/dev/null || true
    fi
    rm -f "${dest}"/*_so.tar 2>/dev/null || true
    local fx="${pd}/bin/wrappersrun_fixture_prog"
    if [[ -x "${fx}" ]]; then
      export WRAPPERSRUN_MPI_BIN="${fx}"
      export WRAPPERSRUN_FIXTURE_STAGED_SO="${pd}/build/wr_fixture/libwr_fixture_staged.so"
      export WRAPPERSRUN_POST_DEPS_HOOK="bash ${pd}/scripts/wrappersrun_fixture_patch_deps_tar.sh && FAKEFS_DIRECT_MODE=0 bash ${pd}/scripts/dependency_mount_fakefs.sh ${dest}"
      export WRAPPERSRUN_FAKEFS_DIRECT_MODE=0
      export WRAPPERSRUN_PROVENANCE_UPPER="${dest}/.fakefs/vol8_wr_run_fixture_lib_upper"
      if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
        export LD_LIBRARY_PATH="${WRAPPERSRUN_PROVENANCE_UPPER}:${LD_LIBRARY_PATH}"
      else
        export LD_LIBRARY_PATH="${WRAPPERSRUN_PROVENANCE_UPPER}"
      fi
    fi
  fi
}

stage_mount_check() {
  echo "[$1] [$(date '+%F %T')] STAGE=mount-check"
  df -h
  findmnt -t fuse.fakefs || true
}

stage_pre_epilog_check() {
  echo "[$1] [$(date '+%F %T')] STAGE=pre-epilog-mount-check"
  if [[ -n "${WRAPPERSRUN_PROVENANCE_UPPER:-}" ]]; then
    echo "[$1] [$(date '+%F %T')] STAGE=provenance-upper path=${WRAPPERSRUN_PROVENANCE_UPPER}"
  fi
  df -h
  findmnt -t fuse.fakefs || true
}

case_skip() {
  echo "[$1] [$(date '+%F %T')] CASE_RESULT=SKIP reason=$2"
  exit 0
}
