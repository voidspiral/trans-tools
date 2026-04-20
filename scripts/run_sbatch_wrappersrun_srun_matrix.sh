#!/bin/bash
# Local single-node Slurm wrappersrun matrix validation.
set -euo pipefail

SBATCH_CASE_MAX_SEC="${SBATCH_CASE_MAX_SEC:-20}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${PROJECT_DIR}/logs"
mkdir -p "${LOG_DIR}"

if ! command -v timeout >/dev/null 2>&1; then
  echo "ERROR: timeout(1) is required to enforce SBATCH_CASE_MAX_SEC=${SBATCH_CASE_MAX_SEC}" >&2
  exit 1
fi

wrappersrun_ensure_agent() {
  local agent_bin="${PROJECT_DIR}/bin/agent"
  [[ -x "${agent_bin}" ]] || {
    echo "ERROR: ${agent_bin} missing; run make build-agent" >&2
    return 1
  }
  if ss -tlnp 2>/dev/null | grep -q ':2007'; then
    return 0
  fi
  echo "[matrix] starting local trans-tools agent on port 2007 (insecure)"
  nohup "${agent_bin}" -port 2007 --insecure >>"${LOG_DIR}/wrappersrun-agent-2007.log" 2>&1 &
  local i
  for i in $(seq 1 80); do
    if ss -tlnp 2>/dev/null | grep -q ':2007'; then
      return 0
    fi
    sleep 0.1
  done
  echo "ERROR: agent did not bind TCP 2007 (see ${LOG_DIR}/wrappersrun-agent-2007.log)" >&2
  return 1
}

wrappersrun_ensure_agent

prov_flag="$(echo "${WRAPPERSRUN_MATRIX_PROVENANCE:-}" | tr '[:upper:]' '[:lower:]')"
if [[ "${prov_flag}" == "1" || "${prov_flag}" == "true" || "${prov_flag}" == "yes" ]]; then
  export WRAPPERSRUN_FAKEFS_DIRECT_MODE=0
  export FAKEFS_DIRECT_MODE=0
fi

cases=(
  "scripts/sbatch_wrappersrun_case_matrix_resources.sh:wrappersrun-matrix-resources"
  "scripts/sbatch_wrappersrun_case_matrix_partition.sh:wrappersrun-matrix-partition"
  "scripts/sbatch_wrappersrun_case_matrix_reservation.sh:wrappersrun-matrix-reservation"
  "scripts/sbatch_wrappersrun_case_matrix_nodelist_long.sh:wrappersrun-matrix-nodelist"
  "scripts/sbatch_wrappersrun_case_matrix_time_output_chdir.sh:wrappersrun-matrix-time-io"
)

submitted=()

extract_vol8_targets() {
  local out_file="$1"
  awk '
    /STAGE=pre-epilog-mount-check/ { stage=1; next }
    stage && /^\/vol8\// { print $1; next }
    stage && /fakefs/ && $NF ~ /^\/vol8\// { print $NF; next }
    /STAGE=mpi-finished/ { stage=0 }
  ' "${out_file}" | awk '!seen[$0]++'
}

matrix_provenance_enabled() {
  local v
  v="$(echo "${WRAPPERSRUN_MATRIX_PROVENANCE:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "${v}" == "1" || "${v}" == "true" || "${v}" == "yes" ]]
}

assert_log_fakefs_staging_snippet() {
  local out_file="$1"
  awk '
    /STAGE=pre-epilog-mount-check/,/STAGE=mpi-finished/ {
      if ($0 ~ /\.fakefs/) { found=1 }
    }
    END { exit(found ? 0 : 1) }
  ' "${out_file}"
}

assert_marker_set() {
  local out_file="$1"
  awk '/STAGE=wrappersrun/ {found=1} END {exit(found?0:1)}' "${out_file}" || return 1
  awk '/STAGE=pre-epilog-mount-check/ {found=1} END {exit(found?0:1)}' "${out_file}" || return 1
  awk '/STAGE=mpi-finished/ {found=1} END {exit(found?0:1)}' "${out_file}" || return 1
  awk '/Step 1: Analyze program dependencies|Analyze program dependencies/ {found=1} END {exit(found?0:1)}' "${out_file}" || return 1
  if matrix_provenance_enabled; then
    awk '/WRAPPER_FIXTURE_MARKER=WR_FIXTURE_MARKER_FAKEFS_STAGED/ {found=1} END {exit(found?0:1)}' "${out_file}" || return 1
    awk '/STAGE=fixture-provenance/ {found=1} END {exit(found?0:1)}' "${out_file}" || return 1
  else
    awk '/MPI Test completed successfully!/ {found=1} END {exit(found?0:1)}' "${out_file}" || return 1
  fi
}

for item in "${cases[@]}"; do
  case_script="${item%%:*}"
  out_prefix="${item#*:}"
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

  echo "Submitting matrix case ${case_script} (sbatch --wait capped at ${SBATCH_CASE_MAX_SEC}s)"
  set +e
  job_id="$(timeout "${SBATCH_CASE_MAX_SEC}" sbatch --wait --parsable --chdir "${PROJECT_DIR}" --export=ALL,WRAPPERSRUN_PROJECT_DIR="${PROJECT_DIR}" "${abs_case}")"
  rc=$?
  set -e
  if [[ "${rc}" -eq 124 ]]; then
    echo "DEBUG: sbatch --wait timeout for ${case_script}. Try: squeue, sacct -j <jobid>, scontrol show job <jobid>, journalctl -u slurmd" >&2
    exit 124
  fi
  if [[ "${rc}" -ne 0 ]]; then
    echo "DEBUG: sbatch failed for ${case_script} (exit ${rc}, output=${job_id})" >&2
    exit "${rc}"
  fi
  submitted+=("${job_id}:${case_script}:${out_prefix}")
done

echo
echo "Matrix jobs completed:"
for item in "${submitted[@]}"; do
  echo "  ${item}"
done

echo
echo "Validating matrix logs and cleanup..."
for item in "${submitted[@]}"; do
  job_id="$(echo "${item}" | awk -F: '{print $1}')"
  case_script="$(echo "${item}" | awk -F: '{print $2}')"
  out_prefix="$(echo "${item}" | awk -F: '{print $3}')"
  out_file="${LOG_DIR}/${out_prefix}-${job_id}.out"
  if [[ ! -f "${out_file}" ]]; then
    echo "missing output log file ${out_file} for ${case_script}" >&2
    exit 1
  fi

  if awk '/CASE_RESULT=SKIP/ {found=1} END {exit(found?0:1)}' "${out_file}"; then
    echo "[SKIP] ${case_script} (${out_file})"
    continue
  fi

  if ! assert_marker_set "${out_file}"; then
    echo "missing required marker in ${out_file} (case=${case_script}). Triage: grep STAGE, sacct -j ${job_id}, scontrol show job ${job_id}" >&2
    exit 1
  fi

  awk '/STAGE=pre-epilog-mount-check/ {stage=1; next} stage && /fakefs/ && $NF ~ /^\/vol8\// {found=1} END {exit(found?0:1)}' "${out_file}" || {
    echo "missing fakefs mount under /vol8 in ${out_file}" >&2
    exit 1
  }

  if matrix_provenance_enabled; then
    if ! assert_log_fakefs_staging_snippet "${out_file}"; then
      echo "missing /tmp/dependencies/.fakefs evidence between pre-epilog and mpi-finished in ${out_file}" >&2
      exit 1
    fi
  fi

  mapfile -t targets < <(extract_vol8_targets "${out_file}")
  if [[ "${#targets[@]}" -eq 0 ]]; then
    echo "no /vol8 fakefs targets extracted from ${out_file}" >&2
    exit 1
  fi

  for target in "${targets[@]}"; do
    if findmnt -t fuse.fakefs -T "${target}" >/dev/null 2>&1; then
      echo "stale fakefs mount remains after epilog for ${target} (case=${case_script})" >&2
      exit 1
    fi
  done
  echo "[MATRIX] [$(date '+%F %T')] STAGE=post-epilog-cleanup-check case=${case_script} job_id=${job_id}" | tee -a "${out_file}"
done

echo "Wrappersrun srun matrix validation complete."
