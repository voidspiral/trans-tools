## Context

`scripts/wrappersrun.sh` is an operational wrapper that combines dependency staging (`trans-tools deps`) with Slurm launch (`exec srun`) and fakefs mount lifecycle managed by Prolog/Epilog hooks. Existing matrix and lifecycle tests show the workflow runs, but they do not provide strong runtime provenance evidence that dependency resolution has been overridden from simulated Lustre (`/vol8`) to fakefs-backed local staging (`/tmp/dependencies/.fakefs/...`).

The current test surface also under-covers operator workflows where allocation and launch are split (`salloc --no-shell` followed by `srun --jobid`), and does not fully specify behavior for `WRAPPERSRUN_SRUN_MPI` injection or strict exit code propagation in failure branches.

This change is limited to a local single-node Slurm + MPICH environment. `/vol8` is used as a Lustre simulation path, and node exclusivity means concurrent `/tmp/dependencies` contention is intentionally out of scope.

## Goals / Non-Goals

**Goals:**
- Provide reproducible runtime evidence that libraries consumed by the test binary come from fakefs-backed local paths, not raw `/vol8` files.
- Cover the `salloc --no-shell` plus later `srun --jobid` operational mode, including a negative path when required node targeting information is absent.
- Specify and validate `WRAPPERSRUN_SRUN_MPI` passthrough semantics in srun-only execution.
- Specify and validate failure propagation guarantees for `trans-tools deps` failure, `srun` failure, and missing `trans-tools` binary diagnostics.
- Add a nearby operator document `scripts/WRAPPERSRUN.md` to reduce usage ambiguity and speed troubleshooting.

**Non-Goals:**
- `WRAPPERSRUN_LAUNCHER=mpirun` branch coverage.
- Multi-node or concurrent stress scenarios.
- OpenMPI-specific compatibility behavior.
- Performance benchmarking or throughput optimization.

## Decisions

1. **Use dual-library fingerprinting for fakefs override evidence.**
   - Decision: Construct two distinguishable library payloads (simulated Lustre-side and staged copy), then assert runtime fingerprint output maps to fakefs-backed staged payload.
   - Rationale: Mount presence (`df`/`findmnt`) alone cannot prove actual loader source selection.
   - Alternative considered: rely only on `ldd` path output. Rejected because some environments and link modes can make source confirmation ambiguous; runtime fingerprinting is stronger.

2. **Model split allocation flow using `salloc --no-shell` + `srun --jobid`.**
   - Decision: Add explicit cases where allocation is created first and wrapper launch is separate, mirroring operations workflows.
   - Rationale: This path changes how node identity is known at launch time and can expose missing-node-resolution regressions.
   - Alternative considered: interactive shell-based `salloc`. Rejected for automation fragility and CI non-determinism.

3. **Assert node-targeting failure behavior explicitly.**
   - Decision: Introduce negative assertions for missing `WRAPPERSRUN_DEPS_NODES` without explicit nodelist in both direct `srun` and `salloc`-split flows.
   - Rationale: This is a common operational misconfiguration and should fail fast with readable diagnostics.
   - Alternative considered: only positive-path tests. Rejected because error behavior is part of the contract.

4. **Validate `WRAPPERSRUN_SRUN_MPI` via observable launch behavior.**
   - Decision: Check that configured `--mpi=<value>` is effectively applied in launch command behavior and/or logs.
   - Rationale: Environment-driven injection is sensitive to argument ordering and silent regressions.
   - Alternative considered: unit-level parser checks only. Rejected because the requirement is end-to-end behavior.

5. **Codify failure propagation with dedicated fault-injection paths.**
   - Decision: Use controlled fault injection (mock or invalid `WRAPPERSRUN_TRANS_TOOLS_BIN`) to assert:
     - deps failure prevents srun launch and returns non-zero,
     - srun failure exit code is passed through unchanged,
     - missing binary yields readable error output.
   - Rationale: Exit semantics are critical for scheduler automation and incident triage.
   - Alternative considered: infer from existing generic failures. Rejected because branch intent is not explicit.

6. **Publish operator-facing nearby documentation.**
   - Decision: Add `scripts/WRAPPERSRUN.md` with lifecycle overview, invocation patterns, and diagnostics checklist.
   - Rationale: Wrapper behavior spans deps, scheduler hooks, and runtime; colocated docs reduce operational mistakes.
   - Alternative considered: update only root README. Rejected because proximity to script improves discoverability.

## Risks / Trade-offs

- **[Risk] Test fixture complexity for dual-library fingerprinting** -> **Mitigation:** keep fixture builder deterministic and isolate helper logic in reusable scripts.
- **[Risk] `salloc --no-shell` availability/behavior differs across local Slurm setups** -> **Mitigation:** add explicit environment precheck and emit SKIP with reason when unsupported.
- **[Risk] Runtime source assertions may be sensitive to linker/runtime environment** -> **Mitigation:** combine mount checks with explicit runtime fingerprint markers rather than path-only checks.
- **[Risk] More E2E cases increase execution time and flakiness surface** -> **Mitigation:** retain timeout guards, stable markers, and selective skip semantics for capability-gated cases.

## Migration Plan

1. Add proposal-aligned spec deltas and new capability spec to define expected behavior before implementation work.
2. Implement/extend sbatch and salloc test scaffolding, including runtime provenance assertions and negative-path checks.
3. Integrate new cases into existing wrappersrun matrix entrypoints and Makefile/README references as required.
4. Add `scripts/WRAPPERSRUN.md` and align wording with implemented behavior and environment variables.
5. Run local validation targets, collect marker evidence, and confirm all new/modified requirements pass.
6. If regression is detected, rollback by disabling new cases via runner gating while preserving previously passing baseline suite.

## Open Questions

- Should `WRAPPERSRUN_SRUN_MPI` validation enforce a specific allowed value set, or only verify passthrough behavior for arbitrary values?
- For missing-node-resolution diagnostics, is exact message text contractual, or should specs require only stable key phrases plus non-zero exit?
- Should fakefs provenance evidence be required in every matrix case or only in dedicated provenance-focused cases to balance runtime cost?
