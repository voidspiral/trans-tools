## ADDED Requirements

### Requirement: wrappersrun works in integrated Slurm+MPI flow
The system SHALL support sbatch-driven execution where each job invokes `wrappersrun.sh`, runs `trans-tools deps`, then runs `srun` MPI under Slurm with Prolog/Epilog enabled.

#### Scenario: Single integrated case succeeds
- **WHEN** an sbatch job invokes `wrappersrun.sh` once with valid MPI arguments
- **THEN** the job SHALL complete with exit code 0
- **AND** logs SHALL contain evidence that deps stage ran before MPI stage
- **AND** logs SHALL contain expected MPI success output

### Requirement: Single-node test fabricates `/vol8` locally
In a single-node environment without shared storage, the test setup SHALL fabricate `/vol8` dependency directories and libraries locally using `test_mpi_app`.

#### Scenario: Local `/vol8` dependency roots are created
- **WHEN** an operator runs `/home/code/test_mpi_app/scripts/generate_three_dep_libs.sh`
- **THEN** `/vol8/test_libs`, `/vol8/test_libs_case2`, and `/vol8/test_libs_case3` SHALL exist locally with `libdep1.so`, `libdep2.so`, and `libdep3.so` in their expected directories

#### Scenario: MPI binary resolves fabricated `/vol8` libraries
- **WHEN** an operator rebuilds `/home/code/test_mpi_app/mpi_test` and runs `ldd /home/code/test_mpi_app/mpi_test`
- **THEN** `ldd` output SHALL resolve `libdep1.so`, `libdep2.so`, and `libdep3.so` under `/vol8/test_libs*`
- **AND** those resolved `.so` paths SHALL be the same dependency paths used later by `trans-tools deps` and prolog fakefs mounting in the E2E flow

### Requirement: slurm.conf enables Prolog and Epilog hooks
The Slurm configuration SHALL have Prolog and Epilog directives uncommented and pointing to the correct scripts.

#### Scenario: Prolog directive is active
- **WHEN** an operator inspects `/etc/slurm/slurm.conf`
- **THEN** the file SHALL contain an uncommented `Prolog=/home/code/trans-tools/scripts/dependency_mount_fakefs.sh` directive

#### Scenario: Epilog directive is active
- **WHEN** an operator inspects `/etc/slurm/slurm.conf`
- **THEN** the file SHALL contain an uncommented `Epilog=/home/code/trans-tools/scripts/dependency_mount_cleanup_fakefs.sh` directive

#### Scenario: Slurm daemons accept the configuration
- **WHEN** slurmctld and slurmd are restarted or reconfigured after the change
- **THEN** `scontrol show config | grep -E 'Prolog|Epilog'` SHALL show the configured script paths

### Requirement: Pre-populate dependencies via trans-tools deps
Before submitting the sbatch job, `trans-tools deps` SHALL be run to scan the MPI test binary and deliver dependency tars to the storage directory.

#### Scenario: Dependency tars exist before sbatch
- **WHEN** `trans-tools deps --program /home/code/test_mpi_app/mpi_test --nodes DESKTOP-N3EHMFF --dest /tmp/dependencies --min-size-mb 0 --filter-prefix /vol8 --port 2007 --insecure` completes
- **THEN** `/tmp/dependencies/` SHALL contain one or more `*_so.tar` files representing the `/vol8/test_libs*` library dependencies

### Requirement: Prolog mounts fakefs overlays at dependency paths
When the Slurm prolog executes `dependency_mount_fakefs.sh`, it SHALL mount fakefs overlays at the paths encoded in the `*_so.tar` filenames.

#### Scenario: fakefs mounts visible via findmnt inside the job
- **WHEN** an sbatch job runs on the node where prolog has executed and `/tmp/dependencies/` contains `*_so.tar` files
- **THEN** `findmnt -t fuse.fakefs` inside the job step SHALL list at least one mount point corresponding to a `/vol8/test_libs*` path
- **AND** `df -h` SHALL show the `fakefs` filesystem entries for those mount points

#### Scenario: Prolog soft-fails gracefully if no tars found
- **WHEN** prolog executes and `/tmp/dependencies/` contains no `*_so.tar` files
- **THEN** the prolog SHALL exit with status zero and log `[INFO] 未找到 *_so.tar 文件`

### Requirement: MPI test program executes with overlaid dependencies
The sbatch test job SHALL run the MPI test program from `/home/code/test_mpi_app/mpi_test` and the program SHALL succeed with fakefs-overlaid libraries.

#### Scenario: MPI program runs successfully
- **WHEN** the sbatch job executes `srun -n 2 /home/code/test_mpi_app/mpi_test` after prolog has mounted fakefs overlays
- **THEN** the job output SHALL contain `MPI Test completed successfully!`
- **AND** the job exit code SHALL be zero

#### Scenario: Dependency library calls succeed
- **WHEN** the MPI program invokes `dep1_ping()`, `dep2_ping()`, `dep3_ping()` via the overlaid shared libraries
- **THEN** no dynamic linker errors (e.g., `cannot open shared object file`) SHALL appear in the job output

### Requirement: Epilog cleans up fakefs mounts
After job completion, the Slurm epilog SHALL unmount all fakefs overlays and clean up state.

#### Scenario: No fakefs mounts remain after job ends
- **WHEN** the sbatch job completes and epilog has executed
- **THEN** `findmnt -t fuse.fakefs` SHALL return no entries for the previously mounted `/vol8/test_libs*` paths

#### Scenario: Epilog soft-fails without draining node
- **WHEN** epilog encounters any cleanup error under `SLURM_JOB_ID`
- **THEN** the epilog SHALL exit with status zero
- **AND** the node SHALL remain in `idle` or `allocated` state (not `drained`)

### Requirement: sbatch test script documents the E2E workflow
The sbatch test script SHALL include verification steps and produce clear output documenting the pipeline state at each phase.

#### Scenario: Test script captures mount state
- **WHEN** the sbatch test job runs
- **THEN** the job output SHALL include `df -h` and `findmnt` output captured after prolog execution and before MPI program launch

#### Scenario: Test script reports dependency delivery status
- **WHEN** the sbatch test job runs
- **THEN** the job output SHALL list the `*_so.tar` files found in `/tmp/dependencies/`

### Requirement: Multiple sbatch cases invoke wrappersrun exactly once per case
The test suite SHALL provide multiple sbatch cases, and each case SHALL call `wrappersrun.sh` exactly one time.

#### Scenario: One wrappersrun call per case
- **WHEN** any sbatch case script in the suite is inspected
- **THEN** it SHALL contain exactly one runtime invocation of `wrappersrun.sh`

#### Scenario: Multi-case suite passes
- **WHEN** all sbatch cases are submitted and waited to completion
- **THEN** each case SHALL exit successfully
- **AND** each case SHALL provide log evidence of wrappersrun execution, deps execution, and MPI execution

### Requirement: Post-job verification procedure
A verification procedure SHALL exist to confirm full pipeline success after job completion.

#### Scenario: Post-job mount cleanup check
- **WHEN** the operator runs verification after the sbatch job completes
- **THEN** `findmnt -t fuse.fakefs` SHALL return empty output (all mounts cleaned)
- **AND** `sinfo` SHALL show the node in a non-drained state

#### Scenario: Post-job log review
- **WHEN** the operator reviews `logs/wrappersrun-test-*.out`
- **THEN** the log SHALL contain evidence of deps delivery, fakefs mount, MPI execution, and successful completion
