## Why

Archived changes validated the baseline `wrappersrun.sh` flow, but they do not yet prove that fakefs truly overrides Lustre-side libraries at runtime. The current E2E coverage also misses three high-frequency operations paths: post-allocation `salloc` usage, `WRAPPERSRUN_SRUN_MPI` injection semantics, and strict error propagation behavior.

## What Changes

- Add a fakefs-over-Lustre evidence case that prebuilds different library variants under `/vol8` and distributed dependency roots, then asserts runtime loading comes from `/tmp/dependencies/.fakefs/...`.
- Add `salloc --no-shell` E2E coverage where allocation is created first and `wrappersrun.sh` is launched separately via `srun --jobid=<jid> ...`.
- Add negative `salloc`/`srun` node-resolution assertions for missing `WRAPPERSRUN_DEPS_NODES` and missing explicit `-w/--nodelist` conditions.
- Add `WRAPPERSRUN_SRUN_MPI` injection assertions that verify effective `exec srun --mpi=<value>` behavior in srun-only mode.
- Add error-propagation assertions for three branches: `trans-tools deps` failure before launch, `srun` failure with original exit code passthrough, and missing `trans-tools` binary readable diagnostics.
- Add nearby documentation `scripts/WRAPPERSRUN.md` describing the dependency distribution + fakefs mount lifecycle, common invocation patterns, and troubleshooting quick checks.

## Capabilities

### New Capabilities

- `wrappersrun-srun-only-full-coverage-test`: Defines complete srun-only E2E validation requirements for fakefs override evidence, salloc path coverage, MPI option injection, and failure semantics.

### Modified Capabilities

- `wrappersrun-srun-matrix-e2e-test`: Extend runtime assertions to require proof that loaded dependencies originate from fakefs-backed `/tmp/dependencies/.fakefs` rather than original `/vol8` library files; integrate or gate `salloc --no-shell` split-flow cases in the consolidated matrix validation entrypoint.
- `slurm-prolog-fakefs-e2e-test`: Extend prolog/runtime evidence to require mount-to-library source linkage checks for mpi test dependencies.

## Impact

- Adds new sbatch/salloc-oriented test cases and assertion helpers around `scripts/wrappersrun.sh` validation flow.
- Extends matrix runner validation logic for source-of-truth runtime library origin checks.
- Adds `scripts/WRAPPERSRUN.md` as operational documentation near the wrapper script.
- No production API changes; scope is validation and documentation.
