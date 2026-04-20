## MODIFIED Requirements

### Requirement: Prolog mount evidence SHALL map to MPI dependency directories
During job runtime, fakefs mount evidence SHALL prove that mounted `/vol8/...` targets correspond to dependency directories required by the MPI test binary, and runtime-loaded shared objects SHALL originate from fakefs-backed local staging.

#### Scenario: Prolog/runtime mount-to-dependency correspondence
- **WHEN** a wrappersrun sbatch case captures `df -h` and `findmnt -t fuse.fakefs` before MPI launch
- **THEN** fakefs mount targets SHALL include `/vol8/` paths used by the MPI binary's shared library dependencies
- **AND** logs SHALL preserve this evidence for post-run auditing

#### Scenario: Runtime shared object source traces to fakefs staging
- **WHEN** the MPI test binary is launched after prolog mount completion
- **THEN** evidence SHALL confirm linked shared objects are loaded from fakefs-backed `/tmp/dependencies/.fakefs/...` source paths
- **AND** runtime markers SHALL prove these loaded artifacts are different from the original `/vol8` baseline payload when a differentiated fixture is provided
