## Why

The target runtime workflow is: Slurm with Prolog/Epilog enabled in `slurm.conf`, and jobs launched via `wrappersrun.sh` where `wrappersrun.sh` calls `trans-tools deps` before `srun`. At execution time, Slurm runs Prolog/Epilog around the step. We need an integration test on local single-node Slurm + MPI to prove this workflow is stable and that sbatch can reliably invoke `wrappersrun.sh`. The MPI test application directory for this change is `/home/code/trans-tools/test_mpi_app`.

## What Changes

- Keep Slurm configured with active Prolog/Epilog in `/etc/slurm/slurm.conf`.
- Validate one full integration flow: `sbatch` -> `wrappersrun.sh` -> `trans-tools deps` -> `srun`(MPI), with Prolog/Epilog executed by Slurm.
- Add a multi-case sbatch test suite where each test case calls `wrappersrun.sh` exactly once, to verify sbatch integration robustness across different argument/env combinations.
- Ensure single-node local Slurm + MPI environment remains the execution platform for this test suite.
- Treat `/vol8` as a fabricated shared-storage root for local testing: create fake dependency directories under `/vol8`, generate fake `.so` files from `test_mpi_app`, and compile `test_mpi_app/mpi_test` only after those `/vol8` dependencies are in place.

## Capabilities

### New Capabilities
- `slurm-prolog-fakefs-e2e-test`: End-to-end validation of sbatch + wrappersrun + deps + srun(MPI) with Slurm Prolog/Epilog enabled on single-node environment.
- `sbatch-single-wrappersrun-cases`: Multiple sbatch integration cases, each invoking `wrappersrun.sh` once, to verify correct and stable dispatch behavior.

### Modified Capabilities

(none — existing specs for `slurm-dependency-mount-hooks` and `sbatch-wrappersrun-test` are not changing requirements, only being exercised in integration)

## Impact

- Modified config: `/etc/slurm/slurm.conf` (uncomment Prolog/Epilog lines)
- Modified scripts: `scripts/sbatch_wrappersrun_test.sh` plus additional sbatch case scripts (single wrappersrun invocation per case)
- Test application directory: `/home/code/trans-tools/test_mpi_app`
- Local fake shared storage: `/vol8` (generated dependency layout from `test_mpi_app` before compile)
- Dependencies: requires `fakefs` binary in PATH, `agent` running on `:2007`, munge + slurmctld + slurmd running
- Verification: wrappersrun invocation count, deps delivery evidence, MPI success output, and successful sbatch completion for each case
