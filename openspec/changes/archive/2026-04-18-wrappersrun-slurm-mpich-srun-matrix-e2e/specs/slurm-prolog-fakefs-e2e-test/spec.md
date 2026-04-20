## ADDED Requirements

### Requirement: Prolog mount evidence SHALL map to MPI dependency directories
During job runtime, fakefs mount evidence SHALL prove that mounted `/vol8/...` targets correspond to dependency directories required by the MPI test binary.

#### Scenario: Prolog/runtime mount-to-dependency correspondence
- **WHEN** a wrappersrun sbatch case captures `df -h` and `findmnt -t fuse.fakefs` before MPI launch
- **THEN** fakefs mount targets SHALL include `/vol8/` paths used by the MPI binary's shared library dependencies
- **AND** logs SHALL preserve this evidence for post-run auditing

### Requirement: Epilog cleanup SHALL remove fakefs runtime mounts
After each job finishes, epilog behavior SHALL be validated by checking that previously observed fakefs mount targets are cleaned.

#### Scenario: Epilog cleanup succeeds for observed targets
- **WHEN** post-job verification runs for a completed case
- **THEN** any `/vol8/` fakefs targets captured during runtime SHALL no longer appear in `findmnt -t fuse.fakefs`
- **AND** `df -h` SHALL not report stale fakefs entries for those targets
