## Why

When `dependency_mount_fakefs.sh` and `dependency_mount_cleanup_fakefs.sh` are wired as Slurm `Prolog` / `Epilog`, any non-zero exit (including `set -e` failures and strict-mode failures) can cause Slurm to treat the node or job setup as failed and drain or block scheduling. Operators need mounts to be best-effort: failures must be visible in logs without failing the hook.

## What Changes

- Ensure both scripts always exit `0` when invoked as Slurm prolog/epilog, after recording failures to a consistent log location.
- Replace or gate paths that currently `exit 1` (missing `fakefs` binary, strict mode aggregate failure, invalid CLI) so they log at error level and still exit `0` in Slurm hook context (or via an explicit env flag such as `SLURM_HOOK_SOFT_FAIL=1`).
- Document recommended Slurm `Prolog` / `Epilog` usage, log path conventions, and how to opt into strict failure for non-Slurm interactive runs if still desired.

## Capabilities

### New Capabilities

- `slurm-dependency-mount-hooks`: Behavioral contract for fakefs dependency mount and cleanup scripts when used as Slurm node hooks: no hook may cause node drain due to exit status; errors are logged in a predictable way.

### Modified Capabilities

- (none — no existing specs under `openspec/specs/`)

## Impact

- `scripts/dependency_mount_fakefs.sh`
- `scripts/dependency_mount_cleanup_fakefs.sh`
- Optional: small wrapper scripts or README notes for cluster operators configuring `slurm.conf`
