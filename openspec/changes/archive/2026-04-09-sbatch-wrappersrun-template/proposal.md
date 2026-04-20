## Why

`wrappersrun.sh` wraps `srun` to deliver dependencies via `trans-tools deps` before launching MPI workloads. Its argument parsing logic (extracting nodelist, program, and forwarding all srun args) is critical — a parsing bug silently breaks dependency delivery or misidentifies the user program. Today there are zero automated tests for this script, making regressions invisible until a production sbatch job fails.

## What Changes

- Add `scripts/wrappersrun_test.sh`: a comprehensive test suite covering unit tests for all pure parsing functions and integration tests with mock `trans-tools` + `srun` binaries.
- Unit tests validate `to_bool`, `sanitize_nodes_expr`, `extract_nodelist_from_srun`, and `extract_program_from_srun` across diverse MPI sbatch submission patterns.
- Integration tests verify that a single `wrappersrun.sh` invocation produces exactly one `trans-tools deps` call and one `srun exec`, with correct argument forwarding.
- Add `validate-wrappersrun` Makefile target for CI integration.

## Capabilities

### New Capabilities
- `sbatch-wrappersrun-test`: Automated test suite that validates `wrappersrun.sh` argument parsing correctness and end-to-end behavior for MPI sbatch submission patterns.

### Modified Capabilities

(none)

## Impact

- New file: `scripts/wrappersrun_test.sh` (91 test cases)
- Modified: `Makefile` (new `validate-wrappersrun` target)
- No changes to `wrappersrun.sh` itself or any other existing code.
