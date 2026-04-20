## ADDED Requirements

### Requirement: Existing sbatch wrappersrun validation SHALL include matrix orchestration
The sbatch wrappersrun validation capability SHALL provide an entrypoint that submits and tracks multiple parameterized wrappersrun sbatch cases with stable case-to-job mapping.

#### Scenario: Case-to-job mapping is reported
- **WHEN** the matrix entrypoint finishes submission and waits for all cases
- **THEN** output SHALL list each `job_id:case_script` mapping
- **AND** each mapping SHALL resolve to a concrete log file under `logs/`

### Requirement: Existing wrappersrun sbatch checks SHALL assert strict marker set
Each case log validation SHALL require wrappersrun stage, deps stage, mount-check stage, and MPI success stage markers.

#### Scenario: Marker validation passes
- **WHEN** a completed case log is analyzed
- **THEN** the log SHALL contain `STAGE=wrappersrun`, deps execution marker text, `STAGE=pre-epilog-mount-check`, and `MPI Test completed successfully!`

#### Scenario: Missing marker fails validation
- **WHEN** any required marker is absent from a case log
- **THEN** the validation entrypoint SHALL exit non-zero and print which marker failed
