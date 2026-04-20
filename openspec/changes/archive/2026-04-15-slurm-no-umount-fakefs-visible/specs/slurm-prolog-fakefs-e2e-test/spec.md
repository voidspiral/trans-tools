## ADDED Requirements

### Requirement: Existing E2E suite supports no-umount diagnostic mode
The Slurm fakefs E2E test suite SHALL provide a dedicated diagnostic mode where Epilog cleanup is intentionally disabled to validate mount observability.

#### Scenario: Diagnostic mode captures `df -h` mount evidence
- **WHEN** operators run the no-umount diagnostic scenario in the wrappersrun sbatch suite
- **THEN** logs SHALL include `df -h` output containing `fakefs` entries for fabricated `/vol8/test_libs*` dependency paths
- **AND** logs SHALL include `findmnt -t fuse.fakefs` output collected before manual cleanup

#### Scenario: Diagnostic mode does not replace normal cleanup assertions
- **WHEN** the normal Prolog+Epilog E2E suite is executed
- **THEN** existing expectations for zero residual fakefs mounts after job completion SHALL remain unchanged
- **AND** no-umount behavior SHALL be validated only in its dedicated scenario
