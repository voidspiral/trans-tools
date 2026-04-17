## ADDED Requirements

### Requirement: Degraded slurm.conf without Epilog keeps fakefs mounts observable
When `slurm.conf` does not configure an Epilog cleanup script, the test flow SHALL still verify that fakefs mounts are created at expected fabricated dependency paths during job runtime.

#### Scenario: Runtime mount visibility under no-umount configuration
- **WHEN** Prolog is configured to run `dependency_mount_fakefs.sh` and Epilog is intentionally unset or commented in `slurm.conf`
- **THEN** a submitted sbatch test job SHALL complete dependency mount setup without Prolog failure
- **AND** `df -h` captured during the job SHALL contain `fakefs` filesystem entries mapped to `/vol8/test_libs*` paths
- **AND** `findmnt -t fuse.fakefs` captured during the job SHALL list those same mount points

### Requirement: Test includes mandatory manual cleanup after no-umount run
Because automatic unmount is disabled in this mode, the validation procedure SHALL enforce an explicit cleanup stage.

#### Scenario: Manual cleanup restores clean mount state
- **WHEN** the no-umount sbatch scenario has finished collecting runtime mount evidence
- **THEN** the procedure SHALL run `scripts/dependency_mount_cleanup_fakefs.sh`
- **AND** post-cleanup `findmnt -t fuse.fakefs` SHALL return no entries
- **AND** `sinfo` SHALL show the node in a non-drained recoverable state
