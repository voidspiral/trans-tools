## 1. Test Infrastructure

- [x] 1.1 Create `scripts/wrappersrun_test.sh` with bash shebang, `set -euo pipefail`, and temp dir cleanup trap
- [x] 1.2 Implement assertion helpers: `assert_eq`, `assert_exit`, `assert_file_exists`, `assert_file_not_exists`, `assert_file_contains`
- [x] 1.3 Source pure functions from `wrappersrun.sh` via awk extraction (anchored to function name boundaries)

## 2. Unit Tests — Pure Functions

- [x] 2.1 `to_bool`: truthy (true/1/yes/y/on/TRUE), falsy (false/0/no/n/off), empty+default, garbage+default (14 cases)
- [x] 2.2 `sanitize_nodes_expr`: plain, single-quoted, double-quoted, embedded-quote inputs (4 cases)
- [x] 2.3 `extract_nodelist_from_srun`: `-w`/`-wHOST`/`--nodelist`/`--nodelist=`/hostlist expr/last-wins/stops-at-`--`/no-nodelist-exit-1/MPI mixed patterns (12 cases)
- [x] 2.4 `extract_program_from_srun`: `-n`/`--ntasks=`/multi-node/`-w`+prog/`--mpi=pmix`/`--` separator/`-c -n`/`-o -e`/`-p -A`/long-separate-value/absolute-path/`--distribution=`/GPU MPI/complex bench/no-program-exit-1 (16 cases)

## 3. Integration Tests — Mock Binaries

- [x] 3.1 Create mock `trans-tools` and `srun` that log received args to files
- [x] 3.2 Implement `run_wrappersrun` helper with subshell env isolation and `VAR=val ... -- srun-args` calling convention
- [x] 3.3 Test: basic MPI with `SLURM_NODELIST` — verify deps nodes, deps program, srun passthrough
- [x] 3.4 Test: explicit `-w` nodelist without SLURM env
- [x] 3.5 Test: `WRAPPERSRUN_DEPS_NODES` overrides `-w` in argv
- [x] 3.6 Test: `SLURM_JOB_NODELIST` fallback
- [x] 3.7 Test: deps disabled — no trans-tools call, srun still runs
- [x] 3.8 Test: multi-node MPI layout (`-N 4 --ntasks-per-node=2`)
- [x] 3.9 Test: MPI with `--` separator
- [x] 3.10 Test: custom deps parameters (port/buffer/width/dest/min-size-mb/filter-prefix) forwarded
- [x] 3.11 Test: `auto-clean=false` and `insecure=false` omit flags
- [x] 3.12 Test: `WRAPPERSRUN_DEPS_PROGRAM` overrides auto-detection
- [x] 3.13 Test: `FAKEFS_DIRECT_MODE` exported correctly (default=1, override=0)
- [x] 3.14 Test: missing nodes with deps enabled → exit 1
- [x] 3.15 Test: no args → exit 2
- [x] 3.16 Test: single invocation produces exactly 1 deps + 1 srun call

## 4. CI Integration

- [x] 4.1 Add `validate-wrappersrun` target to Makefile
- [x] 4.2 Add help text for new target
- [x] 4.3 Remove placeholder `scripts/sbatch_template.sh`
