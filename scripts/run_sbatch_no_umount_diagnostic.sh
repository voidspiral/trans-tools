#!/bin/bash
# Local single-node no-umount diagnostic entrypoint.
# Test assumption: management node and login node are the same local machine.
# Real HPC deployments run scheduler/login/compute on separate nodes; this diagnostic is for
# fakefs mount visibility + cleanup recovery workflow, not production rollout validation.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLURM_CONF="/etc/slurm/slurm.conf"
SLURM_BACKUP="/tmp/slurm.conf.backup.no_umount.$(date +%s)"
LOG_DIR="${PROJECT_DIR}/logs"
SBATCH_CASE_MAX_SEC="${SBATCH_CASE_MAX_SEC:-15}"
TRANS_TOOLS_BIN="${WRAPPERSRUN_TRANS_TOOLS_BIN:-${PROJECT_DIR}/bin/trans-tools}"
MPI_BIN="${WRAPPERSRUN_MPI_BIN:-${PROJECT_DIR}/bin/mpi_test}"
FALLBACK_MPI_BIN="${PROJECT_DIR}/test_mpi_app/mpi_test"

cleanup_and_restore() {
  if [[ -f "${SLURM_BACKUP}" ]]; then
    cp "${SLURM_BACKUP}" "${SLURM_CONF}"
    scontrol reconfigure >/dev/null 2>&1 || true
  fi
}
trap cleanup_and_restore EXIT

if [[ ! -x "${MPI_BIN}" && -x "${FALLBACK_MPI_BIN}" ]]; then
  echo "WARN: ${MPI_BIN} not found, fallback to ${FALLBACK_MPI_BIN}" >&2
  MPI_BIN="${FALLBACK_MPI_BIN}"
fi
if [[ ! -x "${MPI_BIN}" ]]; then
  echo "ERROR: ${MPI_BIN} not found or not executable" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}" /tmp/dependencies
chmod -R a+rwx /tmp/dependencies 2>/dev/null || true

if ! command -v timeout >/dev/null 2>&1; then
  echo "ERROR: timeout(1) is required" >&2
  exit 1
fi
if [[ ! -x "${TRANS_TOOLS_BIN}" ]]; then
  echo "ERROR: ${TRANS_TOOLS_BIN} not found or not executable" >&2
  echo "Hint: run 'make build' or set WRAPPERSRUN_TRANS_TOOLS_BIN" >&2
  exit 1
fi

cp "${SLURM_CONF}" "${SLURM_BACKUP}"
python3 - <<'PY'
from pathlib import Path
p = Path("/etc/slurm/slurm.conf")
s = p.read_text()
lines = []
for line in s.splitlines():
    if line.strip().startswith("Epilog="):
        lines.append("# " + line if not line.lstrip().startswith("#") else line)
    else:
        lines.append(line)
p.write_text("\n".join(lines) + "\n")
PY

scontrol reconfigure
prolog_line="$(scontrol show config | awk '/^Prolog[[:space:]]*=/{print}')"
epilog_line="$(scontrol show config | awk '/^Epilog[[:space:]]*=/{print}')"
echo "${prolog_line}"
echo "${epilog_line}"
if [[ "${epilog_line}" != *"(null)"* ]]; then
  echo "ERROR: Epilog is not disabled in diagnostic mode" >&2
  exit 1
fi

if ! ss -tlnp 2>/dev/null | grep -q ':2007'; then
  nohup "${PROJECT_DIR}/bin/agent" -port 2007 --insecure >/tmp/agent-2007.log 2>&1 &
  sleep 1
fi

"${TRANS_TOOLS_BIN}" deps \
  --program "${MPI_BIN}" \
  --nodes DESKTOP-N3EHMFF \
  --dest /tmp/dependencies \
  --min-size-mb 0 \
  --filter-prefix /vol8 \
  --port 2007 \
  --insecure \
  --width 50 \
  --buffer 2M

set +e
job_id="$(timeout "${SBATCH_CASE_MAX_SEC}" sbatch --wait --parsable --time=00:00:15 \
  --output="${LOG_DIR}/no-umount-diagnostic-%j.out" \
  --error="${LOG_DIR}/no-umount-diagnostic-%j.err" \
  --wrap="bash -lc 'set -euo pipefail; echo STAGE=runtime-mount-check; df -h; findmnt -t fuse.fakefs || true; WRAPPERSRUN_DEPS_DEST=/tmp/dependencies WRAPPERSRUN_DEPS_MIN_SIZE_MB=0 WRAPPERSRUN_DEPS_FILTER_PREFIX=/vol8 WRAPPERSRUN_LAUNCHER=mpirun \"${PROJECT_DIR}/scripts/wrappersrun.sh\" -n 2 \"${MPI_BIN}\"; echo STAGE=mpi-finished'")"
rc=$?
set -e
if [[ "${rc}" -eq 124 ]]; then
  echo "ERROR: diagnostic sbatch exceeded ${SBATCH_CASE_MAX_SEC}s timeout" >&2
  exit 124
fi
if [[ "${rc}" -ne 0 ]]; then
  echo "ERROR: diagnostic sbatch failed rc=${rc}, job=${job_id}" >&2
  exit "${rc}"
fi

out_file="${LOG_DIR}/no-umount-diagnostic-${job_id}.out"
if [[ ! -f "${out_file}" ]]; then
  echo "ERROR: missing diagnostic output log ${out_file}" >&2
  exit 1
fi

awk '/STAGE=runtime-mount-check/ {found=1} END {exit(found?0:1)}' "${out_file}" || { echo "ERROR: missing runtime-mount-check marker" >&2; exit 1; }
awk '/fakefs/ && $NF ~ /^\/vol8\// {found=1} END {exit(found?0:1)}' "${out_file}" || { echo "ERROR: no /vol8 fakefs mount found in df output" >&2; exit 1; }
awk '/MPI Test completed successfully!/ {found=1} END {exit(found?0:1)}' "${out_file}" || { echo "ERROR: missing MPI success marker" >&2; exit 1; }
awk '/STAGE=mpi-finished/ {found=1} END {exit(found?0:1)}' "${out_file}" || { echo "ERROR: missing mpi-finished marker" >&2; exit 1; }

findmnt -t fuse.fakefs | awk '$1 ~ /^\/vol8\// {found=1} END {exit(found?0:1)}' || { echo "ERROR: expected /vol8 fakefs mounts to remain before manual cleanup" >&2; exit 1; }

bash "${PROJECT_DIR}/scripts/dependency_mount_cleanup_fakefs.sh" --keep-storage
for _ in 1 2 3; do
  if ! findmnt -t fuse.fakefs | awk '$1 ~ /^\/vol8\// {found=1} END {exit(found?0:1)}'; then
    break
  fi
  sleep 1
done
findmnt -t fuse.fakefs | awk '$1 ~ /^\/vol8\// {found=1} END {exit(found?1:0)}' || { echo "ERROR: /vol8 fakefs mounts still present after cleanup" >&2; exit 1; }
df -h | awk '/fakefs/ && $NF ~ /^\/vol8\// {found=1} END {exit(found?1:0)}' || { echo "ERROR: /vol8 fakefs still visible in df after cleanup" >&2; exit 1; }
sinfo | awk 'NR>1 && $5 ~ /drain/ {bad=1} END {exit(bad?1:0)}' || { echo "ERROR: node is drained after diagnostic run" >&2; exit 1; }

echo "No-umount diagnostic validation passed. Job: ${job_id}"
