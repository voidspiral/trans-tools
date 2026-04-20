## Context

The current Slurm fakefs validation path focuses on the normal Prolog+Epilog lifecycle where mounts are created before job execution and removed in Epilog. Field debugging often happens when `slurm.conf` is partially configured (for example, Prolog is present but Epilog is absent), and operators need deterministic evidence that fakefs dependency overlays were mounted at expected `/vol8/...` paths.

The test environment is a single-node Slurm setup with fabricated dependency libraries under `/vol8/test_libs*`, fakefs mounted by `dependency_mount_fakefs.sh`, and sbatch-based wrappersrun test scripts. The degraded-mode test must intentionally skip automatic unmount while still keeping the cluster recoverable through explicit manual cleanup.

## Goals / Non-Goals

**Goals:**
- Validate a degraded Slurm configuration where Epilog/unmount is not configured.
- Provide runtime proof that fakefs mounts are active and mapped to fabricated dependency paths using `df -h` and `findmnt -t fuse.fakefs`.
- Define a safe teardown workflow that restores a clean node after diagnostics.
- Keep the new scenario compatible with current wrappersrun-driven sbatch test structure.

**Non-Goals:**
- Redesign fakefs mount internals or dependency packaging logic.
- Permanently change production `slurm.conf` behavior.
- Replace existing normal-mode Prolog+Epilog E2E tests.

## Decisions

1. **Add a dedicated degraded-mode test scenario instead of changing existing normal-mode cases**
   - Rationale: Normal mode and no-umount mode validate different operational guarantees. Keeping separate scenarios avoids conflating expected residual mount behavior with normal cleanup assertions.
   - Alternative considered: Reusing current cases with a flag toggle. Rejected because it increases ambiguity in pass/fail criteria and complicates post-check expectations.

2. **Use temporary `slurm.conf` Epilog disablement as the test trigger**
   - Rationale: This most closely matches real misconfiguration incidents and validates behavior at the scheduler integration layer, not just script-level mocking.
   - Alternative considered: Simulating Epilog skip inside wrapper scripts. Rejected because Slurm daemon behavior and node state side effects would not be exercised.

3. **Treat `df -h` + `findmnt -t fuse.fakefs` as mandatory runtime observability checks**
   - Rationale: Operators commonly inspect these commands first during incidents; embedding them in test expectations creates direct diagnostic value.
   - Alternative considered: Checking only script log markers. Rejected because marker-only checks do not prove mount table state.

4. **Require explicit manual cleanup stage and recovery assertions**
   - Rationale: No-Epilog mode intentionally leaves mounts behind; test completion must include deterministic cleanup via `dependency_mount_cleanup_fakefs.sh` and node-state verification.
   - Alternative considered: Leaving residual mounts for later manual intervention. Rejected due to test contamination risk.

## Risks / Trade-offs

- **[Risk] Residual fakefs mounts affect subsequent tests** -> **Mitigation:** Add required teardown step that runs cleanup script and verifies empty `findmnt -t fuse.fakefs`.
- **[Risk] Temporary `slurm.conf` edits can leave cluster in degraded mode** -> **Mitigation:** Document backup/restore procedure and mandatory `scontrol reconfigure`/service restart checks.
- **[Risk] Operators may confuse degraded-mode expected outcomes with normal-mode success criteria** -> **Mitigation:** Separate test naming and explicit acceptance criteria for "mounts expected to remain before manual cleanup".
- **[Risk] Job time budgets may be exceeded while collecting diagnostics** -> **Mitigation:** Keep the sbatch wait timeout guard (15s) and collect concise mount evidence only.
