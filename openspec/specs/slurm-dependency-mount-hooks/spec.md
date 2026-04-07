## Requirements

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

#### Scenario: Prolog error preserves dependency workspace

- **WHEN** the script runs as a Slurm prolog and enters an error path after creating `/tmp/dependency`
- **THEN** the script SHALL NOT remove `/tmp/dependency` during that failed run
- **AND** the script SHALL keep diagnostic artifacts available for postmortem analysis

### Requirement: Slurm epilog hook does not fail job teardown

When the cleanup script is executed with `SLURM_JOB_ID` set (Slurm epilog context), the process SHALL exit with status zero even if unmount, filesystem cleanup, or validation errors occur. When any such error path is triggered, the cleanup script SHALL NOT delete `/tmp/dependency`.

#### Scenario: Invalid options under Slurm epilog

- **WHEN** the cleanup script runs as a Slurm epilog and receives invalid arguments
- **THEN** the script SHALL log the misuse to the hook log or system log
- **AND** the script SHALL exit with status zero
- **AND** if `/tmp/dependency` already exists, the script SHALL NOT remove it

#### Scenario: Unmount or storage purge error under Slurm

- **WHEN** the cleanup script runs as a Slurm epilog and unmount or directory removal encounters an error
- **THEN** the script SHALL log the error
- **AND** the script SHALL exit with status zero
- **AND** the script SHALL NOT delete `/tmp/dependency`

#### Scenario: Epilog error preserves dependency workspace

- **WHEN** the cleanup script runs as a Slurm epilog and any handled error occurs while `/tmp/dependency` exists
- **THEN** the script SHALL NOT remove `/tmp/dependency` in that error path
- **AND** the script SHALL preserve remaining files for operator troubleshooting

### Requirement: Non-Slurm invocation may remain strict

When `SLURM_JOB_ID` is unset, the mount script MAY exit non-zero for missing `fakefs`, strict aggregate failure, or invalid CLI, unless the operator sets an explicit environment flag documented in the script header to force soft-fail for testing.

#### Scenario: Manual run without Slurm

- **WHEN** an operator runs the mount script interactively without `SLURM_JOB_ID` and `fakefs` is missing
- **THEN** the script MAY exit with non-zero status after printing or logging diagnostics

### Requirement: Hook log content

For both scripts in Slurm context, every handled error path SHALL emit at least one persistent log line containing a severity keyword (e.g. ERROR), a short reason code, and `SLURM_JOB_ID` when set.

#### Scenario: Correlation

- **WHEN** a prolog failure is logged under Slurm
- **THEN** the log line SHALL include the job identifier assigned by Slurm

#### Scenario: Durable error recording

- **WHEN** a handled prolog or epilog error occurs under Slurm
- **THEN** the script SHALL write an ERROR line to a persistent hook log destination rather than emitting diagnostics only to transient stdout
