## ADDED Requirements

### Requirement: Test script exists and is executable
The project SHALL provide `scripts/wrappersrun_test.sh` as an executable bash script that can be run standalone or via `make validate-wrappersrun`.

#### Scenario: File is present and executable
- **WHEN** a developer checks `scripts/wrappersrun_test.sh`
- **THEN** the file exists, has a bash shebang, and has the executable permission bit set

#### Scenario: Makefile target
- **WHEN** a developer runs `make validate-wrappersrun`
- **THEN** the test script executes and reports pass/fail results

### Requirement: to_bool unit tests
The test suite SHALL validate `to_bool` for all accepted input forms and default-value fallback.

#### Scenario: Truthy inputs
- **WHEN** `to_bool` is called with `true`, `1`, `yes`, `y`, `on`, or `TRUE`
- **THEN** it returns `"true"`

#### Scenario: Falsy inputs
- **WHEN** `to_bool` is called with `false`, `0`, `no`, `n`, or `off`
- **THEN** it returns `"false"`

#### Scenario: Empty or unrecognized input with default
- **WHEN** `to_bool` is called with an empty string or unrecognized value and a default
- **THEN** it returns the default value

### Requirement: sanitize_nodes_expr unit tests
The test suite SHALL validate quote stripping and sanitization of node expressions.

#### Scenario: Plain, single-quoted, double-quoted, and embedded-quote inputs
- **WHEN** `sanitize_nodes_expr` is called with various quoting styles
- **THEN** it returns the cleaned node expression with all wrapping and embedded quotes removed

### Requirement: extract_nodelist_from_srun unit tests
The test suite SHALL validate nodelist extraction across all srun argument forms used in MPI sbatch submissions.

#### Scenario: Short and long nodelist forms
- **WHEN** srun args contain `-w host`, `-whost`, `--nodelist host`, or `--nodelist=host`
- **THEN** the correct nodelist is extracted

#### Scenario: Last occurrence wins
- **WHEN** srun args contain multiple nodelist specifications
- **THEN** the last one is returned

#### Scenario: Scanning stops at --
- **WHEN** srun args contain `--` separator
- **THEN** only nodelist args before `--` are considered

#### Scenario: No nodelist present
- **WHEN** srun args contain no nodelist specification
- **THEN** the function exits with code 1

#### Scenario: MPI patterns with mixed options
- **WHEN** srun args use typical MPI patterns (`-n 4 -w nodes ./app`, `--mpi=pmix -w gpus ./train`)
- **THEN** the nodelist is correctly extracted despite surrounding options

### Requirement: extract_program_from_srun unit tests
The test suite SHALL validate program extraction across diverse MPI srun invocation patterns.

#### Scenario: Basic MPI patterns
- **WHEN** srun args are `-n 4 ./mpi_app`, `--ntasks=4 ./app`, `-N 2 -n 8 ./app`
- **THEN** the program is correctly identified

#### Scenario: Options with values consumed correctly
- **WHEN** srun args include value-taking options (`-o out.log -e err.log -p compute -A acct`)
- **THEN** option values are not misidentified as the program

#### Scenario: Long options with = syntax
- **WHEN** srun args include `--mpi=pmix`, `--distribution=block:cyclic`, `--gres=gpu:4`, `--mem=32G`
- **THEN** these are consumed as single args and the program is correctly found after them

#### Scenario: -- separator
- **WHEN** srun args contain `-- /path/to/app --app-flag`
- **THEN** the first token after `--` is returned as the program

#### Scenario: No program found
- **WHEN** all srun args are options with values and no program token exists
- **THEN** the function exits with code 1

### Requirement: Integration test with mock trans-tools and srun
The test suite SHALL validate end-to-end `wrappersrun.sh` behavior using mock binaries that record received arguments.

#### Scenario: Basic MPI with SLURM_NODELIST
- **WHEN** `wrappersrun.sh` runs with `SLURM_NODELIST` set and srun args `-n 4 /bin/hostname`
- **THEN** mock `trans-tools` receives `deps --nodes <nodelist> --program /bin/hostname ...` and mock `srun` receives `-n 4 /bin/hostname`

#### Scenario: Explicit -w nodelist without SLURM env
- **WHEN** srun args include `-w gpu[01-04]` and no SLURM env is set
- **THEN** deps uses the argv nodelist

#### Scenario: WRAPPERSRUN_DEPS_NODES overrides argv
- **WHEN** both `WRAPPERSRUN_DEPS_NODES` env and `-w` argv are present
- **THEN** deps uses the env value while srun receives the original argv unchanged

#### Scenario: SLURM_JOB_NODELIST fallback
- **WHEN** only `SLURM_JOB_NODELIST` is set (no `SLURM_NODELIST`, no `-w`)
- **THEN** deps uses `SLURM_JOB_NODELIST`

#### Scenario: Deps disabled
- **WHEN** `WRAPPERSRUN_ENABLE_DEPS=false`
- **THEN** no `trans-tools` call occurs and srun still receives all original args

#### Scenario: Custom deps parameters forwarded
- **WHEN** custom `WRAPPERSRUN_DEPS_*` env vars are set (port, buffer, width, dest, min-size-mb, filter-prefix)
- **THEN** all values appear in the `trans-tools deps` invocation

#### Scenario: auto-clean and insecure flags omitted when false
- **WHEN** `WRAPPERSRUN_DEPS_AUTO_CLEAN=false` and `WRAPPERSRUN_DEPS_INSECURE=false`
- **THEN** `--auto-clean` and `--insecure` flags are absent from the deps call

#### Scenario: WRAPPERSRUN_DEPS_PROGRAM overrides auto-detection
- **WHEN** `WRAPPERSRUN_DEPS_PROGRAM` is set
- **THEN** deps uses the env program while srun args are unchanged

#### Scenario: FAKEFS_DIRECT_MODE exported
- **WHEN** `WRAPPERSRUN_FAKEFS_DIRECT_MODE` is set to `0` or defaults to `1`
- **THEN** the mock srun observes the correct `FAKEFS_DIRECT_MODE` env value

#### Scenario: Missing nodes with deps enabled
- **WHEN** deps is enabled but no node source is available
- **THEN** `wrappersrun.sh` exits with code 1

#### Scenario: No arguments
- **WHEN** `wrappersrun.sh` is called with no srun arguments
- **THEN** it exits with code 2

### Requirement: Single invocation guarantee
The test suite SHALL verify that one `wrappersrun.sh` call produces exactly one `trans-tools deps` invocation and one `srun exec`.

#### Scenario: Exactly one deps and one srun call
- **WHEN** `wrappersrun.sh` runs with a multi-node MPI pattern
- **THEN** the mock log files contain exactly one line each
