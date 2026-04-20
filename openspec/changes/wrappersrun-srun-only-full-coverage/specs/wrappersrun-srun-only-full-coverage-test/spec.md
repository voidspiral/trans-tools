## ADDED Requirements

### Requirement: Wrappersrun SHALL prove fakefs-over-Lustre dependency override in srun-only mode
The validation suite SHALL provide runtime evidence that dependencies for the MPI test program are loaded from fakefs-backed local staging under `/tmp/dependencies/.fakefs/...` instead of the original simulated Lustre path under `/vol8/...`.

#### Scenario: Runtime loader source resolves to fakefs-backed staged dependency
- **WHEN** a case prepares distinguishable library variants under `/vol8` and staged dependency roots, then launches `scripts/wrappersrun.sh` with `exec srun`
- **THEN** runtime evidence SHALL include a marker proving the loaded library fingerprint corresponds to the staged variant
- **AND** the captured source path evidence SHALL point to `/tmp/dependencies/.fakefs/...` rather than raw `/vol8` files

### Requirement: Wrappersrun SHALL support split allocation launch with salloc
The suite SHALL validate the operational path where allocation is acquired first and wrapper launch occurs later via `srun --jobid=<jid>`.

#### Scenario: salloc allocation then wrappersrun launch succeeds
- **WHEN** the environment supports `salloc --no-shell` and an allocation is created before launching wrappersrun with `srun --jobid=<jid>`
- **THEN** wrappersrun SHALL complete dependency distribution and run the MPI program successfully
- **AND** logs SHALL include stable stage markers for dependency, runtime mount visibility, and MPI completion

#### Scenario: salloc split flow fails fast when node targeting is missing
- **WHEN** wrappersrun is launched against an allocation without `WRAPPERSRUN_DEPS_NODES` and without explicit `-w/--nodelist`
- **THEN** wrappersrun SHALL exit with status 1
- **AND** output SHALL include a readable message indicating node list resolution is required

### Requirement: Direct srun wrappersrun launch SHALL fail clearly when dependency node resolution is absent
When wrappersrun cannot infer a dependency distribution target node list for direct srun launches, it SHALL fail with deterministic error semantics.

#### Scenario: Direct srun random allocation without deps node list
- **WHEN** wrappersrun is launched directly by srun without `WRAPPERSRUN_DEPS_NODES` and without explicit nodelist arguments
- **THEN** wrappersrun SHALL return exit code 1
- **AND** error output SHALL include a readable node-resolution failure reason

### Requirement: Wrappersrun SHALL apply WRAPPERSRUN_SRUN_MPI in srun-only execution
The wrapper SHALL propagate `WRAPPERSRUN_SRUN_MPI` into the effective `srun` invocation as `--mpi=<value>`.

#### Scenario: srun launch reflects configured MPI mode
- **WHEN** `WRAPPERSRUN_SRUN_MPI` is set before launching wrappersrun in srun-only mode
- **THEN** the effective launch behavior/log evidence SHALL show `--mpi=<value>` is applied
- **AND** MPI job execution SHALL remain successful under supported modes

### Requirement: Wrappersrun SHALL preserve failure propagation semantics
Failure branches in dependency preparation and job launch SHALL produce deterministic exit and diagnostics behavior.

#### Scenario: trans-tools deps failure blocks srun launch
- **WHEN** `trans-tools deps` returns non-zero in wrappersrun pre-launch stage
- **THEN** wrappersrun SHALL return non-zero
- **AND** wrappersrun SHALL NOT start `srun`

#### Scenario: srun failure exit code is passed through unchanged
- **WHEN** dependency preparation succeeds but `srun` returns a non-zero exit code
- **THEN** wrappersrun SHALL exit with the same non-zero status code
- **AND** logs SHALL preserve the launch-stage failure context

#### Scenario: missing trans-tools binary emits readable diagnostic
- **WHEN** `WRAPPERSRUN_TRANS_TOOLS_BIN` points to a missing binary
- **THEN** wrappersrun SHALL fail before launch
- **AND** output SHALL contain a readable missing-binary error message

### Requirement: Wrappersrun documentation SHALL exist next to script entrypoint
Operator-facing usage and troubleshooting guidance SHALL be available as a nearby document.

#### Scenario: Nearby documentation file is present and references core workflow
- **WHEN** repository documentation checks run for wrappersrun assets
- **THEN** `scripts/WRAPPERSRUN.md` SHALL exist
- **AND** it SHALL describe dependency distribution, fakefs lifecycle, and supported srun-only invocation patterns
