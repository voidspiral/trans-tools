## 1. Fakefs-over-Lustre coverage evidence

- [x] 1.1 Add reusable fixture builder that creates differentiated dependency payloads for `/vol8` baseline and staged fakefs source.
- [x] 1.2 Add a dedicated wrappersrun sbatch case that launches MPI with the differentiated fixture and emits runtime provenance markers.
- [x] 1.3 Extend assertion helpers to validate that runtime-loaded dependencies map to `/tmp/dependencies/.fakefs/...` and not raw `/vol8` payloads.

## 2. Salloc split-flow coverage

- [x] 2.1 Add `salloc --no-shell` orchestration helper that acquires allocation IDs and runs wrappersrun through `srun --jobid=<jid>`.
- [x] 2.2 Add positive salloc split-flow case with stage markers for deps, runtime mount checks, and MPI completion.
- [x] 2.3 Add negative split-flow case that omits `WRAPPERSRUN_DEPS_NODES` and nodelist, asserting exit 1 and readable node-resolution error.

## 3. SRUN_MPI injection and error propagation

- [x] 3.1 Add srun-only case validating `WRAPPERSRUN_SRUN_MPI` produces effective `--mpi=<value>` launch behavior.
- [x] 3.2 Add fault-injection case for `trans-tools deps` failure and assert wrappersrun exits non-zero without starting srun.
- [x] 3.3 Add failure case asserting wrappersrun passes through non-zero `srun` exit code unchanged, plus missing `WRAPPERSRUN_TRANS_TOOLS_BIN` readable diagnostics.

## 4. Nearby wrappersrun README

- [x] 4.1 Create `scripts/WRAPPERSRUN.md` with lifecycle overview (`trans-tools deps` -> Prolog fakefs mount -> `exec srun` -> Epilog cleanup).
- [x] 4.2 Document three invocation patterns (direct srun, sbatch case execution, salloc split-flow) and required node-targeting variables.
- [x] 4.3 Add troubleshooting quick checks for mount visibility (`df -h`, `findmnt`) and provenance/error symptoms.

## 5. Integration and validation alignment

- [x] 5.1 Integrate new cases into wrappersrun matrix/suite runners with explicit SKIP behavior for unsupported local capabilities.
- [x] 5.2 Update top-level test entrypoints (Makefile/README references) to include new srun-only full-coverage validation paths.
- [x] 5.3 Execute local validation targets, collect stable markers, and confirm all new/modified spec requirements are satisfied.
