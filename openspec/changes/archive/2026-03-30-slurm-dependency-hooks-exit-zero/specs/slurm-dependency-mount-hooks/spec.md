## ADDED Requirements

### Requirement: Slurm prolog hook does not fail the allocation

When the mount script is executed with `SLURM_JOB_ID` set (Slurm prolog context), the process SHALL exit with status zero even if dependency extraction, mount, or strict-mode aggregation would otherwise indicate failure.

#### Scenario: Missing fakefs binary under Slurm

- **WHEN** the script runs as a Slurm prolog (`SLURM_JOB_ID` is non-empty) and the `fakefs` binary is not available
- **THEN** the script SHALL write an error message to the configured hook log destination
- **AND** the script SHALL exit with status zero

#### Scenario: Mount or timeout failure under Slurm

- **WHEN** the script runs as a Slurm prolog and one or more `fakefs` mounts fail or time out
- **THEN** each failure SHALL be recorded in the hook log with job and node identifiers where available
- **AND** the script SHALL exit with status zero

### Requirement: Slurm epilog hook does not fail job teardown

When the cleanup script is executed with `SLURM_JOB_ID` set (Slurm epilog context), the process SHALL exit with status zero even if unmount, filesystem cleanup, or validation errors occur.

#### Scenario: Invalid options under Slurm epilog

- **WHEN** the cleanup script runs as a Slurm epilog and receives invalid arguments
- **THEN** the script SHALL log the misuse to the hook log or system log
- **AND** the script SHALL exit with status zero

#### Scenario: Unmount or storage purge error under Slurm

- **WHEN** the cleanup script runs as a Slurm epilog and unmount or directory removal encounters an error
- **THEN** the script SHALL log the error
- **AND** the script SHALL exit with status zero

### Requirement: Non-Slurm invocation may remain strict

When `SLURM_JOB_ID` is unset, the mount script MAY exit non-zero for missing `fakefs`, strict aggregate failure, or invalid CLI, unless the operator sets an explicit environment flag documented in the script header to force soft-fail for testing.

#### Scenario: Manual run without Slurm

- **WHEN** an operator runs the mount script interactively without `SLURM_JOB_ID` and `fakefs` is missing
- **THEN** the script MAY exit with non-zero status after printing or logging diagnostics

### Requirement: Hook log content

For both scripts in Slurm context, every handled error path SHALL emit at least one log line containing a severity keyword (e.g. ERROR), a short reason code, and `SLURM_JOB_ID` when set.

#### Scenario: Correlation

- **WHEN** a prolog failure is logged under Slurm
- **THEN** the log line SHALL include the job identifier assigned by Slurm
