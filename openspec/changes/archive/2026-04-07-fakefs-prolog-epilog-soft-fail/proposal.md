## Why

Slurm prolog/epilog hook failures can propagate non-zero exits and cause node drain, which reduces cluster availability. Operators also need failed dependency mount/cleanup paths to preserve `/tmp/dependency` for diagnosis while recording durable error logs.

## What Changes

- Update fakefs dependency mount and cleanup hook behavior in Slurm contexts to always soft-fail (exit zero) after capturing errors.
- Ensure the cleanup script never deletes `/tmp/dependency` when any error path is triggered, preserving diagnostic artifacts for troubleshooting.
- Strengthen error logging expectations so failures are persisted with enough job/node context for triage.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `slurm-dependency-mount-hooks`: adjust prolog/epilog failure handling to avoid node drain, explicitly forbid cleanup-script deletion of `/tmp/dependency` on errors, and persist structured error logs.

## Impact

- Affected scripts: `scripts/dependency_mount_fakefs.sh`, `scripts/dependency_mount_cleanup_fakefs.sh`.
- Affected behavior: Slurm prolog/epilog exit codes, cleanup semantics on error, and hook log output.
- Operational impact: lower risk of accidental node drain, improved post-failure diagnostics.
