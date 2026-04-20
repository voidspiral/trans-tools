## ADDED Requirements

### Requirement: Wrappersrun SHALL support high-frequency srun option matrix on single-node Slurm+MPICH
The test suite SHALL execute `scripts/wrappersrun.sh` through sbatch cases that cover high-frequency `srun` option categories: task sizing, CPU limits, partition, reservation (if available), time limit, kill-on-bad-exit, nodelist forms, output, and working directory.

#### Scenario: Matrix case executes with supported option set
- **WHEN** a matrix case uses a supported `srun` option combination in the local Slurm environment
- **THEN** wrappersrun SHALL invoke `srun` successfully with those options preserved
- **AND** the case log SHALL include `STAGE=wrappersrun` and `STAGE=mpi-finished`

#### Scenario: Environment-dependent option is unavailable
- **WHEN** a case requires an unavailable partition or reservation in the local Slurm environment
- **THEN** the case SHALL be marked `SKIP` with an explicit reason in logs
- **AND** the matrix runner SHALL continue executing remaining cases

### Requirement: Each matrix case SHALL verify dependency and mount lifecycle evidence
Every matrix case SHALL validate deps invocation, fakefs runtime mount visibility, and post-job cleanup.

#### Scenario: Runtime fakefs visibility check
- **WHEN** the case reaches `STAGE=pre-epilog-mount-check`
- **THEN** `df -h` SHALL include `fakefs` entries mounted under `/vol8/`
- **AND** `findmnt -t fuse.fakefs` SHALL include matching `/vol8/` mount targets

#### Scenario: Post-epilog cleanup check
- **WHEN** the job exits and epilog has completed
- **THEN** validation SHALL confirm that prior `/vol8/` fakefs mount targets are no longer present in `findmnt -t fuse.fakefs`
