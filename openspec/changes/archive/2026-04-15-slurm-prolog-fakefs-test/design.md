## Context

A single-node Slurm test environment is running on WSL2 Ubuntu 22.04 (hostname `DESKTOP-N3EHMFF`) with munge, slurmctld, slurmd, OpenMPI 4.1.2, and `trans-tools` (agent + deps CLI). There is **no shared Lustre `/vol8`** on this machine. For single-node E2E testing, `/vol8` is a **local directory tree** that mimics production layout: create `/vol8/test_libs`, `/vol8/test_libs_case2`, `/vol8/test_libs_case3`, run `/home/code/test_mpi_app/scripts/generate_three_dep_libs.sh` (default targets are those paths) to install fabricated `libdep{1,2,3}.so`, then `make` in `test_mpi_app` so `mpi_test` is linked with rpath to those paths. The MPI binary at `/home/code/test_mpi_app/mpi_test` then reports `/vol8/...` dependencies in `ldd` and to `trans-tools deps`, matching what the prolog/fakefs pipeline expects.

The current `slurm.conf` has the Prolog/Epilog directives commented out:

```
#Prolog=/home/code/trans-tools/scripts/dependency_mount_fakefs.sh
#Epilog=/home/code/trans-tools/scripts/dependency_mount_cleanup_fakefs.sh
```

Without these hooks, the E2E test (`scripts/sbatch_wrappersrun_test.sh`) only validates the `wrappersrun.sh` → `trans-tools deps` → `srun` path. The fakefs overlay mount that makes dependency libraries visible to compute nodes at their original paths is never exercised.

The `fakefs` binary is already installed at `/usr/local/bin/fakefs`. The agent binary is at `/home/code/trans-tools/bin/agent`.

## Goals / Non-Goals

**Goals:**
- Enable Slurm Prolog/Epilog in `slurm.conf` pointing to `dependency_mount_fakefs.sh` / `dependency_mount_cleanup_fakefs.sh`.
- Verify in integrated `slurm + mpi` execution that `wrappersrun.sh` works correctly when called by `sbatch`.
- Build multiple sbatch test cases where each case invokes `wrappersrun.sh` exactly once.
- Verify each case completes successfully with evidence for deps stage + MPI stage.

**Non-Goals:**
- Multi-node cluster testing (single-node WSL2 only).
- Modifying `wrappersrun.sh`, `dependency_mount_fakefs.sh`, or `dependency_mount_cleanup_fakefs.sh` logic.
- Performance benchmarking.

## Decisions

### 1. Uncomment Prolog/Epilog in slurm.conf

Enable the hooks directly in `/etc/slurm/slurm.conf`:

```ini
Prolog=/home/code/trans-tools/scripts/dependency_mount_fakefs.sh
Epilog=/home/code/trans-tools/scripts/dependency_mount_cleanup_fakefs.sh
```

After modifying `slurm.conf`, restart slurmctld and slurmd with `scontrol reconfigure` or daemon restart.

**Alternative considered:** Using `PrologSlurmctld` instead — rejected because the prolog must run on the compute node (slurmd side) to perform FUSE mounts locally.

### 2. Fabricated `/vol8` layout and MPI binary from `test_mpi_app`

**Setup (once per clean machine or after removing `/vol8`):**

1. `sudo mkdir -p /vol8/test_libs /vol8/test_libs_case2 /vol8/test_libs_case3` (root may be required for `/vol8`).
2. `cd /home/code/test_mpi_app && ./scripts/generate_three_dep_libs.sh` — installs one distinct `.so` per directory (defaults: `/vol8/test_libs`, `/vol8/test_libs_case2`, `/vol8/test_libs_case3`). Optional: pass three explicit paths if using a non-root test prefix (script accepts `DIR1 DIR2 DIR3` as first three args; then build with matching `LIB_DIR1/2/3` overrides).
3. `make clean && make` in `test_mpi_app` — `Makefile` defaults match those three `/vol8` paths.
4. Verify: `ldd /home/code/test_mpi_app/mpi_test | grep libdep` shows three lines under `/vol8/test_libs*`.

Use `/home/code/test_mpi_app/mpi_test` so `trans-tools deps` discovers `/vol8/...` DT_NEEDED paths and produces `*_so.tar` names that decode back to the same mountpoints for `dependency_mount_fakefs.sh`. The repo `bin/mpi_hello` has no `/vol8` deps and does not exercise this path.

**Alternative considered:** Hard-coding libs under `trans-tools/` only — rejected; `test_mpi_app` already standardizes multi-directory dep layout and sizes.

### 3. Verification via `df -h` and `findmnt` Inside the Job

The sbatch test script will capture `df -h` and `findmnt -t fuse.fakefs` output both before and after the MPI program runs (but within the same job allocation where prolog has executed). This provides evidence that:
1. Prolog successfully invoked `dependency_mount_fakefs.sh`.
2. fakefs overlay mounts appeared at `/vol8/test_libs*` paths.
3. The mount type is `fuse.fakefs`.

After job completion, a post-job verification checks that epilog unmounted the paths.

### 6. Multi-case sbatch validation with one wrappersrun call per case

Create a small suite of sbatch scripts (or one driver script generating cases). Each case must satisfy:
1. Exactly one call to `wrappersrun.sh` in the sbatch script body.
2. Distinct argument/env setup (for example different `-n`, different deps filter, explicit/implicit node selection).
3. Deterministic assertions from logs:
   - wrappersrun path executed,
   - deps stage executed (`trans-tools deps` evidence),
   - MPI stage executed successfully,
   - sbatch exit status is zero.

This directly validates the two requested outcomes:
- wrappersrun works in integrated Slurm+MPI flow;
- sbatch can correctly dispatch wrappersrun across multiple cases.

### 4. DEPENDENCY_STORAGE_DIR Environment for Prolog

When running as Slurm prolog, `dependency_mount_fakefs.sh` reads `DEPENDENCY_STORAGE_DIR` (defaulting to `/tmp/dependencies`). The sbatch test script sets `WRAPPERSRUN_DEPS_DEST=/tmp/dependencies` to align with the prolog's default. This ensures that the tar files deposited by `trans-tools deps` are found by the prolog.

**Key constraint:** The prolog runs before the job script, so it will pick up `*_so.tar` files deposited by a previous `trans-tools deps` run or by wrappersrun within the same allocation. In practice, on a single-node test, `wrappersrun.sh` runs deps then exec srun; the prolog fires per-job-allocation, so the flow is: allocation starts → prolog runs (may find no tars yet) → job script starts → wrappersrun runs deps → exec srun. This means the prolog may not find tars on the first job step.

**Workaround:** Run `trans-tools deps` in a preparatory step before `sbatch`, or use a two-step approach: first sbatch to deliver deps, then sbatch to run with prolog. For the single-node test, the simplest approach is to pre-populate `/tmp/dependencies/` via `trans-tools deps` before submitting the sbatch job, so the prolog finds tars on entry.

### 5. Two-Phase Test Approach

**Phase A — Dependency Delivery:** Run `trans-tools deps` manually or via a preparatory sbatch to scan `/home/code/test_mpi_app/mpi_test` and deliver `*_so.tar` to `/tmp/dependencies/`.

**Phase B — Prolog + MPI Execution:** Submit the sbatch job; prolog finds tars, mounts fakefs overlays, then `srun` executes `mpi_test` with overlaid libraries visible.

This two-phase approach avoids the timing issue where prolog runs before deps delivery within the same job.

## Risks / Trade-offs

- [Prolog runs before job script so tars may not exist yet] → Mitigation: two-phase test approach with pre-populated deps.
- [WSL2 FUSE may behave differently from production kernel] → Mitigation: this is a flow validation, not a performance test; basic FUSE mount/unmount should work.
- [Single-node test cannot validate cross-node dependency delivery] → Mitigation: agent runs on localhost, simulating cross-node communication; multi-node testing is a separate concern.
- [Enabling prolog/epilog may cause node drain if scripts fail] → Mitigation: both scripts implement soft-fail (exit 0) when `SLURM_JOB_ID` is set; no node drain risk.
- [`/vol8` missing or libs not installed] → Mitigation: run `generate_three_dep_libs.sh` and `make` in `test_mpi_app`; confirm `ldd mpi_test` resolves `libdep*.so` under `/vol8/...`. Lowerdirs must exist and contain real files for a meaningful overlay test.
