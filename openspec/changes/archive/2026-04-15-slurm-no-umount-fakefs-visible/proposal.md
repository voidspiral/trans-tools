## Why

Current Slurm E2E validation assumes both Prolog and Epilog are configured, but production troubleshooting often starts from partial `slurm.conf` states where Epilog (unmount/cleanup) is missing. We need a dedicated test case that proves fakefs mounts are observable during job runtime in this degraded configuration and can be diagnosed quickly via `df -h`.

## What Changes

- Add a new Slurm test capability for the "no umount script configured" configuration.
- Define a test flow that keeps Prolog mount enabled while Epilog cleanup is intentionally absent.
- Require runtime verification that `df -h` shows fakefs entries mapped to fabricated `/vol8/...` dependency paths.
- Add explicit setup/teardown steps so the test is reproducible and does not leave the cluster in a broken state after diagnostics.

## Capabilities

### New Capabilities
- `slurm-no-umount-fakefs-visible`: Validate fakefs mount visibility and dependency-path mapping when Slurm Epilog cleanup is not configured.

### Modified Capabilities
- `slurm-prolog-fakefs-e2e-test`: Add a degraded-mode scenario that validates mount visibility (`df -h`/`findmnt`) when Epilog is intentionally disabled and documents manual cleanup expectations.

## Impact

- Affected artifacts: new change specs and tasks for Slurm degraded-mode testing.
- Affected runtime config: temporary edits to `/etc/slurm/slurm.conf` for test mode.
- Affected scripts/tests: sbatch test scripts and validation runner may gain a mode flag or dedicated test script.
- Operational impact: requires explicit post-test cleanup (`dependency_mount_cleanup_fakefs.sh`) to avoid persistent fakefs mounts.
