#!/bin/bash
# Executed under: salloc --no-shell ... bash scripts/wrappersrun_salloc_split_driver.sh
set -euo pipefail

PROJECT_DIR="${WRAPPERSRUN_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
jid="${SLURM_JOB_ID:-}"
if [[ -z "${jid}" ]]; then
  echo "[salloc-split-driver] ERROR missing SLURM_JOB_ID" >&2
  exit 1
fi

mpi_bin="${PROJECT_DIR}/bin/mpi_test"
if [[ ! -x "${mpi_bin}" ]]; then
  mpi_bin="${PROJECT_DIR}/test_mpi_app/mpi_test"
fi
if [[ ! -x "${mpi_bin}" ]]; then
  echo "[salloc-split-driver] SKIP mpi_test missing" >&2
  exit 0
fi

nodelist="${SLURM_JOB_NODELIST:-${SLURM_NODELIST:-}}"
if [[ -z "${nodelist}" ]]; then
  nodelist="$(hostname)"
fi

echo "[salloc-split-driver] [$(date '+%F %T')] STAGE=deps-precheck job=${jid} nodelist=${nodelist}"
ls -la /tmp/dependencies || true

echo "[salloc-split-driver] [$(date '+%F %T')] STAGE=wrappersrun-positive"
srun --jobid="${jid}" -N1 -n1 -D "${PROJECT_DIR}" \
  env WRAPPERSRUN_PROJECT_DIR="${PROJECT_DIR}" \
  WRAPPERSRUN_TRANS_TOOLS_BIN="${PROJECT_DIR}/bin/trans-tools" \
  WRAPPERSRUN_DEPS_DEST=/tmp/dependencies \
  WRAPPERSRUN_DEPS_MIN_SIZE_MB=0 \
  WRAPPERSRUN_DEPS_FILTER_PREFIX=/vol8 \
  WRAPPERSRUN_LAUNCHER=srun \
  WRAPPERSRUN_DEPS_NODES="${nodelist}" \
  bash -lc "set -euo pipefail; echo \"[salloc-split] [\$(date '+%F %T')] STAGE=deps-precheck\"; \
    ls -la /tmp/dependencies || true; \
    echo \"[salloc-split] [\$(date '+%F %T')] STAGE=wrappersrun\"; \
    \"${PROJECT_DIR}/scripts/wrappersrun.sh\" -N1 -n2 -c1 --kill-on-bad-exit=1 \"${mpi_bin}\"; \
    echo \"[salloc-split] [\$(date '+%F %T')] STAGE=pre-epilog-mount-check\"; df -h; findmnt -t fuse.fakefs || true; \
    echo \"[salloc-split] [\$(date '+%F %T')] STAGE=mpi-finished\""

echo "[salloc-split-driver] [$(date '+%F %T')] STAGE=wrappersrun-negative"
set +e
out_neg="$(srun --jobid="${jid}" -N1 -n1 -D "${PROJECT_DIR}" \
  env -u SLURM_NODELIST -u SLURM_JOB_NODELIST -u WRAPPERSRUN_DEPS_NODES \
  bash "${PROJECT_DIR}/scripts/wrappersrun.sh" -N1 -n1 "${mpi_bin}" 2>&1)"
rc_neg=$?
set -e
if [[ "${rc_neg}" -ne 1 ]]; then
  echo "[salloc-split-driver] ERROR expected exit 1, got ${rc_neg}: ${out_neg}" >&2
  exit 1
fi
if [[ "${out_neg}" != *"missing nodes for deps"* ]]; then
  echo "[salloc-split-driver] ERROR missing expected diagnostics" >&2
  exit 1
fi

echo "[salloc-split-driver] done"
