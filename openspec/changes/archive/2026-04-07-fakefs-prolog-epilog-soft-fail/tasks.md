## 1. Hook Error-Handling Refactor

- [x] 1.1 Add shared Slurm-context soft-fail handling in `scripts/dependency_mount_fakefs.sh` and `scripts/dependency_mount_cleanup_fakefs.sh` so handled hook errors return exit code `0`.
- [x] 1.2 Ensure cleanup-script error branches never delete `/tmp/dependency`, while preserving existing success-path cleanup behavior.
- [x] 1.3 Normalize error logging output to include severity, reason code, and Slurm job/node context fields.

## 2. Test Coverage

- [x] 2.1 Update `scripts/e2e_fakefs_mount_test.sh` to validate prolog mount failures still exit `0` and retain `/tmp/dependency`.
- [x] 2.2 Update `scripts/slurm_fakefs_hook_soft_fail_test.sh` (and related cleanup tests) to validate epilog error paths never delete `/tmp/dependency` and persist error logs.
- [x] 2.3 Add assertions that log files contain required correlation fields (`ERROR`, reason code, `SLURM_JOB_ID`) for both prolog and epilog failure scenarios.

## 3. Validation and Rollout Readiness

- [x] 3.1 Run shellcheck and targeted hook tests to confirm no regression in non-Slurm strict behavior (`make validate-fakefs-hooks` or `bash scripts/validate_fakefs_hooks.sh`; installs `shellcheck` for full static analysis when offline tooling is unavailable).
- [x] 3.2 Document operator troubleshooting notes for preserved `/tmp/dependency` artifacts and log locations in script headers or runbook notes.
