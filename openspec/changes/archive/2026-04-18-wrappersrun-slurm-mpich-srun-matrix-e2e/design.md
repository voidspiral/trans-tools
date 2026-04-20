## Context

`scripts/wrappersrun.sh` wraps `srun`, injects dependency distribution (`trans-tools deps`), and relies on Slurm Prolog/Epilog hooks to expose and clean fakefs mounts for `/vol8` dependency paths used by the MPI test binary. Current validation covers only a few sbatch scenarios and does not provide broad confidence that common `srun` options are passed through correctly while mount lifecycle guarantees remain intact.

The target environment is a local single-node Slurm+MPICH setup. This environment is functionally representative for wrapper behavior and hook sequencing, but not a performance or multi-node benchmark. The design must keep deterministic evidence (`df -h`, `findmnt`, stage markers) and make unsupported scheduler features (for example unavailable reservation names) explicit skips, not failures.

## Goals / Non-Goals

**Goals:**
- Define a repeatable `srun` parameter matrix for high-frequency operational options and validate wrappersrun passthrough correctness.
- Validate fakefs lifecycle with explicit evidence points:
  - Prolog/runtime stage: fakefs mount exists and maps to `/vol8/...` dependency directories.
  - Post-job/Epilog stage: fakefs mount entries are cleaned.
- Standardize per-case output and diagnostics so failures are actionable from logs alone.
- Keep compatibility with existing sbatch validation entrypoints and marker conventions.

**Non-Goals:**
- Performance benchmarking, stress testing, or throughput tuning.
- Multi-node topology verification.
- Changes to cluster-wide scheduling policy or Slurm deployment architecture.
- Introducing new runtime dependencies beyond existing Slurm/MPICH/fakefs/trans-tools tooling.

## Decisions

### 1) Use a matrix runner with isolated sbatch case scripts
- **Decision:** Add a dedicated matrix orchestrator script (for example `run_sbatch_wrappersrun_srun_matrix.sh`) that submits multiple single-purpose sbatch case scripts.
- **Rationale:** Keeps each parameter combination easy to diagnose and allows selective skip/failure handling per case without collapsing all scenarios into one job script.
- **Alternatives considered:**
  - One monolithic sbatch script with internal loops: simpler file count, but harder debugging and weaker per-case traceability.
  - Direct `srun` from the host shell: faster iteration, but weaker reproducibility and less aligned with existing sbatch-based validation flow.

### 2) Encode high-frequency `srun` coverage as capability-level requirements
- **Decision:** Capture required parameter categories in spec requirements (resource sizing, partition/reservation, time/failure control, node selection, output/chdir behavior) instead of ad-hoc script comments.
- **Rationale:** Moves test expectations into OpenSpec contract so future script changes remain reviewable against formal requirements.
- **Alternatives considered:**
  - Keep parameter list only in shell docs: lower ceremony but easy to drift from actual acceptance criteria.

### 3) Two-phase mount assertions with strict markers
- **Decision:** Require explicit stage markers and paired checks:
  - Pre-epilog marker with `df -h` and `findmnt -t fuse.fakefs`.
  - Post-epilog check proving fakefs unmounted for case mountpoints.
- **Rationale:** Separating existence and cleanup checks prevents false positives where mounts either never appear or never clear.
- **Alternatives considered:**
  - Only check runtime mount presence: misses cleanup regressions.
  - Only check final cleanup: misses prolog/path mapping regressions.

### 4) Environment capability detection and skip semantics
- **Decision:** For environment-bound flags (for example partition/reservation), detect availability before submission or at case start and mark as `SKIP` with reason in logs.
- **Rationale:** Local test environments vary; unsupported scheduler features should not block unrelated validation.
- **Alternatives considered:**
  - Hard fail unsupported features: improves strictness but causes noisy false failures in dev setups.

### 5) Reuse existing marker/timeout patterns
- **Decision:** Extend existing marker checks and timeout guards in current sbatch runners rather than replacing them.
- **Rationale:** Preserves known-good operational behavior and reduces migration risk.
- **Alternatives considered:**
  - Rebuild from scratch: clean slate but unnecessary risk and duplicate logic.

## Risks / Trade-offs

- **[Risk] Local Slurm config drift causes flaky partition/reservation cases** -> **Mitigation:** preflight checks and explicit skip reasons captured in case logs.
- **[Risk] Epilog timing races lead to intermittent cleanup observations** -> **Mitigation:** bounded retry window for post-job `findmnt/df` verification before declaring failure.
- **[Risk] Matrix expansion increases runtime** -> **Mitigation:** enforce per-case timeout and keep default matrix focused on high-frequency flags only.
- **[Risk] Log verbosity makes triage harder** -> **Mitigation:** standardize concise stage markers and stable case-to-job naming.

## Migration Plan

1. Add/extend OpenSpec specs for matrix coverage and lifecycle assertions.
2. Implement matrix runner and case scripts with shared markers and assertion helpers.
3. Integrate matrix entrypoint into existing validation workflow while preserving current case scripts.
4. Run in local single-node Slurm+MPICH environment; verify success, skip, and failure paths.
5. Keep rollback simple: disable new matrix entrypoint and revert to existing case runner if regressions appear.

## Open Questions

- Which partition and reservation names are considered canonical in the local CI/dev environment?
- Should skipped environment-dependent cases be treated as warning-only or fail if skip ratio exceeds a threshold?
- Do we require an additional negative test (intentional bad `srun` parameter) to validate wrappersrun failure propagation semantics?
