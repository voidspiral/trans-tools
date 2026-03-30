## 1. Mount script (prolog)

- [x] 1.1 Add Slurm soft-fail detection (`SLURM_JOB_ID` non-empty, optional `SLURM_HOOK_SOFT_FAIL`) and document it in the script header.
- [x] 1.2 Implement centralized `log_hook_error` (file under `STORAGE_DIR` or `logger` fallback) with ERROR severity, reason code, job id, node name.
- [x] 1.3 In Slurm soft-fail mode: replace or trap failures so missing `fakefs`, `set -e` command failures, tar/mount errors, and `FAKEFS_STRICT_MODE` aggregate failure all log and exit `0`.
- [x] 1.4 Preserve non-Slurm strict exit behavior for missing `fakefs` and strict aggregate failure when `SLURM_JOB_ID` is unset (unless documented override env is set).

## 2. Cleanup script (epilog)

- [x] 2.1 In Slurm context: invalid CLI and dangerous `purge_storage_dir` cases log and exit `0` instead of non-zero.
- [x] 2.2 In Slurm context: unmount / `rm -rf` failures are logged; final exit status is `0`.
- [x] 2.3 Keep non-Slurm behavior for invalid CLI or dangerous paths as non-zero where appropriate.

## 3. Verification and docs

- [x] 3.1 Add or extend shell tests / manual checklist: run under fake `SLURM_JOB_ID` with missing `fakefs` and assert exit `0` plus log line.
- [x] 3.2 Document recommended `Prolog` / `Epilog` lines and log file locations for operators (README or script comments in English per project rules).
