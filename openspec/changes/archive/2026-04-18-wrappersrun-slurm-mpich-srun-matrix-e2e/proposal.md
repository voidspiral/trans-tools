## Why

The current wrappersrun validation covers only a small set of sbatch scenarios, which is insufficient to catch regressions in common `srun` argument combinations used in daily operations. We need a deterministic single-node Slurm+MPICH E2E suite to prove dependency distribution, Prolog mount visibility, and Epilog cleanup behavior across high-frequency launch patterns.

## What Changes

- Add a test capability that validates `scripts/wrappersrun.sh` against a matrix of high-frequency `srun` options (partition, reservation, cpu limits, time limits, nodelist, output/chdir).
- Define consistent assertions for each case: wrappersrun launch success, `trans-tools deps` invocation, MPI completion, and expected stage markers.
- Add lifecycle checks that validate fakefs mount presence during Prolog/runtime (`df -h` and `findmnt -t fuse.fakefs`) and fakefs cleanup after Epilog.
- Introduce skip semantics for environment-dependent options (for example reservation/partition not available on local Slurm) so unsupported features do not create false failures.
- Standardize case-to-job log mapping and failure diagnostics for quick triage on single-node development setups.

## Capabilities

### New Capabilities
- `wrappersrun-srun-matrix-e2e-test`: Validate wrappersrun command passthrough and fakefs lifecycle correctness under common `srun` parameter combinations on local single-node Slurm+MPICH.

### Modified Capabilities
- `sbatch-wrappersrun-test`: Extend the existing sbatch wrappersrun validation contract to include matrix orchestration and stronger marker-based assertions.
- `slurm-prolog-fakefs-e2e-test`: Extend lifecycle assertions to explicitly cover Prolog mount-to-dependency correspondence and Epilog cleanup guarantees.

## Impact

- Affected scripts: `scripts/wrappersrun.sh`, `scripts/run_sbatch_wrappersrun_cases.sh`, and additional matrix case scripts under `scripts/`.
- Affected test logs and diagnostics under `logs/`.
- Requires local Slurm+MPICH test environment with fakefs available and MPI test binary dependencies under `/vol8`.
- No public API changes; this is test coverage and validation behavior enhancement.
