## Context

`wrappersrun.sh` is a srun-compatible wrapper that delivers dependencies to compute nodes via `trans-tools deps` before launching the actual srun command. It contains several pure parsing functions (`to_bool`, `sanitize_nodes_expr`, `extract_nodelist_from_srun`, `extract_program_from_srun`) and an execution flow that resolves nodes, builds the deps command, and `exec`s srun.

There are no existing tests for this script. The repository's shell test convention is plain bash scripts under `scripts/` (e.g. `slurm_fakefs_hook_soft_fail_test.sh`) with pass/fail assertions and a Makefile target for CI.

## Goals / Non-Goals

**Goals:**
- Unit-test every pure parsing function in `wrappersrun.sh` against typical MPI srun argument patterns.
- Integration-test the full script with mock `trans-tools` and `srun` binaries to verify correct argument forwarding and single-invocation guarantees.
- Follow the existing test convention (plain bash, no external framework).
- Integrate into the Makefile as `validate-wrappersrun`.

**Non-Goals:**
- Testing actual Slurm cluster behavior (requires a live cluster).
- Modifying `wrappersrun.sh` itself.
- Introducing a test framework (bats, shunit2, etc.).

## Decisions

### 1. Function Extraction via awk

Pure functions are sourced from `wrappersrun.sh` using `awk '/^to_bool\(\)/,/^enable_deps=/'` to extract the function definition block without executing the script's top-level logic.

**Alternative considered:** Copying functions into the test file — rejected because it would diverge from the source and miss regressions.

### 2. Mock Binaries for Integration Tests

Mock `trans-tools` and `srun` scripts are created in a temp directory and placed first on `PATH`. Each mock logs its received arguments to a file, enabling assertions on exact argument content.

**Alternative considered:** Stubbing via shell functions — rejected because `wrappersrun.sh` uses `exec srun` which replaces the process; only a real executable on PATH works.

### 3. Subshell Isolation per Integration Test

Each integration test runs `wrappersrun.sh` in a subshell that unsets all `WRAPPERSRUN_*` and `SLURM_*` variables, then exports only the test-specific env via a `VAR=val ... -- srun-args` calling convention.

**Alternative considered:** Global env manipulation with cleanup — rejected because it is error-prone with `set -e` and cross-test contamination.

### 4. Counter Arithmetic with `$((x + 1))` instead of `((x++))`

Pass/fail counters use `var=$((var + 1))` to avoid `((0))` returning exit code 1 under `set -e`.

### 5. Script Location: `scripts/wrappersrun_test.sh`

Co-located with `wrappersrun.sh` and following the existing pattern (`slurm_fakefs_hook_soft_fail_test.sh`).

## Risks / Trade-offs

- [awk extraction is anchored to function name boundaries] → If function names change, the extraction breaks. Mitigation: test itself would fail loudly.
- [Mock srun does not actually launch MPI processes] → Integration tests verify argument forwarding, not MPI runtime behavior. Mitigation: this is by design; cluster-level E2E testing is a separate concern.
- [No assertion on trans-tools deps ordering relative to srun] → The test verifies both are called, but not strict ordering. Mitigation: `wrappersrun.sh` uses `exec srun` which structurally guarantees deps runs first.
