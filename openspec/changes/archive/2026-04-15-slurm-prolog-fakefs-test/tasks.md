## 1. Enable Prolog/Epilog in slurm.conf

- [x] 1.1 Uncomment `Prolog=/home/code/trans-tools/scripts/dependency_mount_fakefs.sh` in `/etc/slurm/slurm.conf`
- [x] 1.2 Uncomment `Epilog=/home/code/trans-tools/scripts/dependency_mount_cleanup_fakefs.sh` in `/etc/slurm/slurm.conf`
- [x] 1.3 Restart or reconfigure Slurm daemons (`scontrol reconfigure` or restart slurmctld/slurmd)
- [x] 1.4 Verify with `scontrol show config | grep -E 'Prolog|Epilog'` that scripts are configured

## 2. Environment Preparation

- [x] 2.1 Ensure munge is running (`munge -n | unmunge` returns SUCCESS)
- [x] 2.2 Ensure slurmctld and slurmd are running (`sinfo` shows node idle)
- [x] 2.3 Ensure agent is running on `:2007` (`/home/code/trans-tools/bin/agent -port 2007 --insecure &`)
- [x] 2.4 Ensure `fakefs` is in PATH (`which fakefs` returns `/usr/local/bin/fakefs`)
- [x] 2.5 Ensure `trans-tools` is in PATH (`which trans-tools` returns valid path)
- [x] 2.6 Create local fake `/vol8` roots for single-node test (`sudo mkdir -p /vol8/test_libs /vol8/test_libs_case2 /vol8/test_libs_case3`)
- [x] 2.7 Run `/home/code/test_mpi_app/scripts/generate_three_dep_libs.sh` to install fabricated `libdep{1,2,3}.so` under `/vol8/test_libs*`
- [x] 2.8 Rebuild MPI test binary in `/home/code/test_mpi_app` (`make clean && make`)
- [x] 2.9 Verify `/home/code/test_mpi_app/mpi_test` exists and `ldd /home/code/test_mpi_app/mpi_test | grep libdep` resolves to `/vol8/test_libs*`

## 3. Pre-populate Dependencies (Phase A)

- [x] 3.1 Clean any previous `/tmp/dependencies/` contents (`rm -rf /tmp/dependencies/*`)
- [x] 3.2 Run `trans-tools deps --program /home/code/test_mpi_app/mpi_test --nodes DESKTOP-N3EHMFF --dest /tmp/dependencies --min-size-mb 0 --filter-prefix /vol8 --port 2007 --insecure --width 50 --buffer 2M`
- [x] 3.3 Verify `*_so.tar` files exist in `/tmp/dependencies/` (`ls -la /tmp/dependencies/*_so.tar`)
- [x] 3.4 Verify tar filenames encode `/vol8/test_libs*` paths (e.g., `zvol8ztest_libs_so.tar`)

## 4. Implement Multi-case sbatch Tests (one wrappersrun call each)

- [x] 4.1 Update `scripts/sbatch_wrappersrun_test.sh` to use `MPI_HELLO="/home/code/test_mpi_app/mpi_test"`
- [x] 4.2 Add at least two additional sbatch case scripts with different args/env combinations
- [x] 4.3 Ensure each sbatch case script invokes `wrappersrun.sh` exactly once
- [x] 4.4 Add shared logging markers so each case shows wrappersrun stage, deps stage, and MPI stage
- [x] 4.5 Add a checker script (or Makefile target) to run all sbatch cases and aggregate pass/fail

## 5. Execute Multi-case E2E Tests (Phase B)

- [x] 5.1 Submit and wait each sbatch case to completion
- [x] 5.2 Verify every case exits with status 0
- [x] 5.3 Verify every case log has wrappersrun execution evidence
- [x] 5.4 Verify every case log has `trans-tools deps` execution evidence
- [x] 5.5 Verify every case log has MPI success output
- [x] 5.6 Verify every case script still contains exactly one wrappersrun invocation

## 6. Post-Job Verification

- [x] 6.1 Run `findmnt -t fuse.fakefs` — should return empty (epilog cleaned up mounts)
- [x] 6.2 Run `df -h | grep fakefs` — should return empty
- [x] 6.3 Run `sinfo` — node should be idle/not drained
- [x] 6.4 Check `/tmp/dependencies/hook-errors.log` for any prolog/epilog errors (should not exist or be empty)
- [x] 6.5 If any fakefs mounts persist, manually run `scripts/dependency_mount_cleanup_fakefs.sh` and investigate

## 7. Troubleshooting Checklist

- [ ] 7.1 If prolog reports "未找到 fakefs" — verify `fakefs` is in slurmd's PATH (may need full path in script or symlink)
- [ ] 7.2 If no `*_so.tar` found by prolog — verify Phase A completed and tars exist before sbatch submission
- [ ] 7.3 If MPI fails with "cannot open shared object" — check that fakefs mount succeeded and library files are visible at `/vol8/test_libs*`
- [ ] 7.4 If node drains — check `/var/log/slurm/slurmd.log` for prolog/epilog exit codes; verify soft-fail is working
- [ ] 7.5 If `srun` hangs — check MPI PMIx configuration; try `WRAPPERSRUN_LAUNCHER=mpirun` or site PMI-enabled Open MPI
