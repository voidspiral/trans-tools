## 1. Matrix case scaffolding

- [x] 1.1 Add a dedicated matrix runner script to submit/wait multiple wrappersrun sbatch cases and print stable `job_id:case_script` mapping.
- [x] 1.2 Add sbatch case scripts for high-frequency `srun` option categories (`-n/-N/-c`, `-p`, `--reservation`, `-t`, `-K`, `-w/--nodelist`, `-o`, `--chdir`).
- [x] 1.3 Implement environment capability checks for partition/reservation cases and mark unsupported cases as explicit `SKIP` with reason.

## 2. Lifecycle assertions and log contracts

- [x] 2.1 Add shared marker conventions for wrappersrun, deps execution, pre-epilog mount check, MPI completion, and post-epilog cleanup validation.
- [x] 2.2 Add runtime assertions that `df -h` and `findmnt -t fuse.fakefs` show fakefs mount targets under `/vol8/`.
- [x] 2.3 Add post-job assertions that previously observed `/vol8/` fakefs targets are absent after Epilog cleanup.

## 3. Integration with existing validation flow

- [x] 3.1 Extend `scripts/run_sbatch_wrappersrun_cases.sh` (or sibling entrypoint) to include matrix execution without breaking existing baseline cases.
- [x] 3.2 Keep timeout guards and failure diagnostics actionable (case name, missing marker, and suggested triage commands).
- [x] 3.3 Standardize output log naming and lookup so every matrix case has deterministic log discovery under `logs/`.

## 4. Verification and documentation alignment

- [x] 4.1 Run local single-node Slurm+MPICH validation and confirm pass/skip/fail behavior matches spec expectations.
- [x] 4.2 Verify fakefs mount-to-dependency correspondence evidence is preserved in logs for auditability.
- [x] 4.3 Update relevant validation docs/readme snippets to describe matrix scope, skip semantics, and prolog/epilog checks.
