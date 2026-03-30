## Context

`scripts/dependency_mount_fakefs.sh` and `scripts/dependency_mount_cleanup_fakefs.sh` are intended for Slurm `Prolog` / `Epilog`. Today they use `set -euo pipefail`, return `exit 1` when `fakefs` is missing, when `FAKEFS_STRICT_MODE=1` and any mount step fails, and the cleanup script returns non-zero for invalid CLI or dangerous `purge_storage_dir` paths. Slurm interprets prolog/epilog failure as a serious condition and may mark nodes `DRAIN` or fail job allocation.

Chinese log strings are acceptable for human operators; normative behavior is exit status and log routing.

## Goals / Non-Goals

**Goals:**

- In Slurm hook context, both scripts SHALL exit `0` after logging any failure, so hooks never trigger drain solely due to script exit code.
- Failures SHALL be written to a single, documented log file (reuse `${STORAGE_DIR}/debug.log` and/or a dedicated `${STORAGE_DIR}/hook-errors.log`, or `slurmd` journal via `logger`) with timestamp, job id, node name, and error summary.
- Preserve optional strict behavior for manual or CI invocation when not running under Slurm.

**Non-Goals:**

- Changing Slurm cluster-wide `PrologFlags` / `Epilog` timeout behavior beyond what these scripts return.
- Guaranteeing successful mounts when dependencies are broken (only observability and non-failing hook).

## Decisions

1. **Detect Slurm hook context**  
   Use `SLURM_JOB_ID` (and optionally `SLURM_HOOK_SOFT_FAIL=1` override) to enable “soft fail” mode: on any error path, log and `exit 0`. Outside Slurm, default remains fail-fast for missing `fakefs` and strict mode unless operators set an explicit env var.

2. **Central error logging helper**  
   Add a small `log_hook_error()` that appends one line (or JSON line) to `${STORAGE_DIR}/hook-errors.log` and mirrors to stderr so `slurmd` captures it if configured. Avoid relying only on `echo` without a file when `STORAGE_DIR` is missing—in that case use `logger -t slurm-fakefs-hook`.

3. **`set -e` vs soft fail**  
   Either: (a) replace `set -e` with explicit `|| log_error` on critical commands in hook mode, or (b) keep `set -e` and add a top-level `trap` on ERR that logs and exits `0` in Slurm soft-fail mode. Prefer **trap + explicit checks** for mount loop clarity.

4. **Cleanup script**  
   Invalid CLI and “dangerous directory” cases: in Slurm context, log and `exit 0` instead of `exit 2` / `return 1` from `purge_storage_dir` that propagates. Non-Slurm interactive use keeps non-zero for misuse.

5. **STRICT_MODE**  
   When `FAKEFS_STRICT_MODE=1` and Slurm soft-fail is active, log aggregate failure and still `exit 0`.

## Risks / Trade-offs

- **[Risk] Silent mount failure** → Jobs run without intended overlays; mitigation: loud ERROR lines in `hook-errors.log` and optional metric hook later.  
- **[Risk] Operators expect non-zero in automation** → Document `SLURM_HOOK_SOFT_FAIL=0` or absence of `SLURM_JOB_ID` for strict behavior.  
- **[Risk] `trap` masks bugs** → Limit trap to Slurm soft-fail mode only; add a unit test or shellcheck + manual `sbatch` verification task.

## Migration Plan

1. Deploy updated scripts to shared path referenced by `Prolog` / `Epilog`.  
2. `scontrol reconfigure` on controller; restart not required if only scripts change.  
3. Submit test job; confirm node stays `IDLE` on induced failure (e.g. temporarily rename `fakefs`) and `hook-errors.log` receives an entry.  
4. Rollback: revert script version on shared storage.

## Open Questions

- Whether to standardize log path as `/var/log/slurm/fakefs-hook.log` (root-writable) vs `${DEPENDENCY_STORAGE_DIR}` when that directory is job-local and removed at epilog.
