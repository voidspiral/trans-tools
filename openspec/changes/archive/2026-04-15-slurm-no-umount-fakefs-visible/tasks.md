## 1. Add no-umount diagnostic scenario definition

- [x] 1.1 Add a dedicated sbatch test scenario/script for "Prolog enabled, Epilog disabled" mode
- [x] 1.2 Capture and log `df -h` and `findmnt -t fuse.fakefs` outputs during runtime before MPI launch
- [x] 1.3 Ensure the scenario still uses fabricated `/vol8/test_libs*` dependency paths and wrappersrun invocation constraints

## 2. Slurm configuration toggle and safeguards

- [x] 2.1 Add test steps (or helper script) to backup current `/etc/slurm/slurm.conf` and disable/comment Epilog for the diagnostic run
- [x] 2.2 Reconfigure/restart Slurm safely for diagnostic mode and verify active Prolog/Epilog values with `scontrol show config`
- [x] 2.3 Restore original `slurm.conf` after test execution and verify configuration rollback is effective

## 3. Cleanup and recovery verification

- [x] 3.1 Add mandatory manual cleanup step running `scripts/dependency_mount_cleanup_fakefs.sh` after no-umount scenario
- [x] 3.2 Verify post-cleanup state (`findmnt -t fuse.fakefs` empty, `df -h | grep fakefs` empty)
- [x] 3.3 Verify node health after cleanup (`sinfo` non-drained) and collect troubleshooting logs on failure

## 4. Integrate with validation entrypoints and docs

- [x] 4.1 Integrate the no-umount diagnostic scenario into the existing validation runner/Make target flow
- [x] 4.2 Add explicit 15-second submission timeout expectations and debug guidance for timeout/failure paths
- [x] 4.3 Document when to use no-umount diagnostic mode versus normal Prolog+Epilog E2E mode
