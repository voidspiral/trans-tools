## MODIFIED Requirements

### Requirement: Each matrix case SHALL verify dependency and mount lifecycle evidence
Every matrix case SHALL validate deps invocation, fakefs runtime mount visibility, runtime dependency source provenance, and post-job cleanup.

#### Scenario: Runtime fakefs visibility check
- **WHEN** the case reaches `STAGE=pre-epilog-mount-check`
- **THEN** `df -h` SHALL include `fakefs` entries mounted under `/vol8/`
- **AND** `findmnt -t fuse.fakefs` SHALL include matching `/vol8/` mount targets

#### Scenario: Runtime dependency source is fakefs-backed staging
- **WHEN** the matrix case executes the MPI runtime path after dependency staging
- **THEN** runtime evidence SHALL prove that required dependency libraries are resolved from `/tmp/dependencies/.fakefs/...`
- **AND** logs SHALL include a provenance marker showing the loaded dependency source is not the original `/vol8` file payload

#### Scenario: Post-epilog cleanup check
- **WHEN** the job exits and epilog has completed
- **THEN** validation SHALL confirm that prior `/vol8/` fakefs mount targets are no longer present in `findmnt -t fuse.fakefs`

## ADDED Requirements

### Requirement: Matrix validation entrypoint SHALL cover salloc split-flow when supported
The consolidated wrappersrun matrix validation SHALL include `salloc --no-shell` followed by `srun --jobid=<jid> scripts/wrappersrun.sh ...` coverage, or SHALL explicitly `SKIP` that segment with a logged reason when the local Slurm environment does not support it.

#### Scenario: Positive salloc split-flow is exercised or skipped with reason
- **WHEN** the matrix validation runner executes to completion
- **THEN** logs SHALL either include successful salloc split-flow stage markers or a `SKIP` line explaining why salloc split-flow is unavailable
- **AND** when the positive path runs, it SHALL satisfy the same dependency and mount lifecycle assertions as sbatch matrix cases

#### Scenario: Negative salloc split-flow without node targeting
- **WHEN** the salloc split-flow negative case runs in a supported environment
- **THEN** wrappersrun SHALL exit with status 1 without launching MPI
- **AND** output SHALL include a readable node-resolution failure message
