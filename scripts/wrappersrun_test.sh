#!/usr/bin/env bash
# Tests for wrappersrun.sh argument parsing and sbatch integration patterns.
# Validates correct extraction of nodelist and program from srun argv across
# typical MPI sbatch submission styles. Ensures a single wrappersrun invocation
# produces exactly one trans-tools deps call and one srun exec.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPERSRUN="${ROOT_DIR}/scripts/wrappersrun.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

pass=0
fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass=$((pass + 1))
  else
    echo "FAIL: $desc" >&2
    echo "  expected: '${expected}'" >&2
    echo "  actual:   '${actual}'" >&2
    fail=$((fail + 1))
  fi
}

assert_exit() {
  local desc="$1" expected_rc="$2" actual_rc="$3"
  if [[ "$expected_rc" == "$actual_rc" ]]; then
    pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected exit ${expected_rc}, got ${actual_rc})" >&2
    fail=$((fail + 1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    pass=$((pass + 1))
  else
    echo "FAIL: $desc (file not found: ${path})" >&2
    fail=$((fail + 1))
  fi
}

assert_file_not_exists() {
  local desc="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    pass=$((pass + 1))
  else
    echo "FAIL: $desc (file should not exist: ${path})" >&2
    fail=$((fail + 1))
  fi
}

assert_file_contains() {
  local desc="$1" path="$2" pattern="$3"
  if grep -qE -- "$pattern" "$path" 2>/dev/null; then
    pass=$((pass + 1))
  else
    echo "FAIL: $desc (pattern '${pattern}' not in ${path})" >&2
    [[ -f "$path" ]] && echo "  content: $(cat "$path")" >&2
    fail=$((fail + 1))
  fi
}

# ============================================================
# Part 1: Unit tests — source pure functions from wrappersrun
# ============================================================

eval "$(awk '/^to_bool\(\)/,/^enable_deps=/' "$WRAPPERSRUN" | sed '$d')"

echo "--- Unit: to_bool ---"

assert_eq "true"   "true"  "$(to_bool true)"
assert_eq "1"      "true"  "$(to_bool 1)"
assert_eq "yes"    "true"  "$(to_bool yes)"
assert_eq "y"      "true"  "$(to_bool y)"
assert_eq "on"     "true"  "$(to_bool on)"
assert_eq "TRUE"   "true"  "$(to_bool TRUE)"
assert_eq "false"  "false" "$(to_bool false)"
assert_eq "0"      "false" "$(to_bool 0)"
assert_eq "no"     "false" "$(to_bool no)"
assert_eq "n"      "false" "$(to_bool n)"
assert_eq "off"    "false" "$(to_bool off)"
assert_eq "empty→default=true"  "true"  "$(to_bool '' true)"
assert_eq "empty→default=false" "false" "$(to_bool '' false)"
assert_eq "garbage→default"     "true"  "$(to_bool random true)"

echo "--- Unit: sanitize_nodes_expr ---"

assert_eq "plain"         "node1"      "$(sanitize_nodes_expr 'node1')"
assert_eq "single-quoted" "node[1-4]"  "$(sanitize_nodes_expr "'node[1-4]'")"
assert_eq "double-quoted" "node[1-4]"  "$(sanitize_nodes_expr '"node[1-4]"')"
assert_eq "embedded quotes" "node1,node2" "$(sanitize_nodes_expr "node1','node2")"

echo "--- Unit: extract_nodelist_from_srun ---"

r="$(extract_nodelist_from_srun -w node01)" || true
assert_eq "-w node01" "node01" "$r"

r="$(extract_nodelist_from_srun -wnode01)" || true
assert_eq "-wnode01 merged" "node01" "$r"

r="$(extract_nodelist_from_srun --nodelist node01)" || true
assert_eq "--nodelist node01" "node01" "$r"

r="$(extract_nodelist_from_srun --nodelist=node01)" || true
assert_eq "--nodelist=node01" "node01" "$r"

r="$(extract_nodelist_from_srun --nodelist=node[001-004])" || true
assert_eq "hostlist expr" "node[001-004]" "$r"

r="$(extract_nodelist_from_srun -w first --nodelist=second)" || true
assert_eq "last occurrence wins" "second" "$r"

r="$(extract_nodelist_from_srun --nodelist=hosts -- prog)" || true
assert_eq "stops at --" "hosts" "$r"

set +e; extract_nodelist_from_srun -n 4 ./app >/dev/null 2>&1; rc=$?; set -e
assert_exit "no nodelist → exit 1" 1 "$rc"

r="$(extract_nodelist_from_srun -n 4 -w "node[1-4]" ./mpi_app)" || true
assert_eq "MPI: -n -w prog" "node[1-4]" "$r"

r="$(extract_nodelist_from_srun --ntasks-per-node=2 -N 4 --nodelist=node[001-008] ./app)" || true
assert_eq "MPI: complex layout" "node[001-008]" "$r"

r="$(extract_nodelist_from_srun --mpi=pmix -n 16 -w gpu[01-04] ./train)" || true
assert_eq "MPI: pmix + gpu nodes" "gpu[01-04]" "$r"

echo "--- Unit: extract_program_from_srun ---"

r="$(extract_program_from_srun -n 4 ./mpi_app)"
assert_eq "-n 4 prog" "./mpi_app" "$r"

r="$(extract_program_from_srun --ntasks=4 ./mpi_app)"
assert_eq "--ntasks=4 prog" "./mpi_app" "$r"

r="$(extract_program_from_srun -N 2 -n 8 ./mpi_app)"
assert_eq "-N 2 -n 8 prog" "./mpi_app" "$r"

r="$(extract_program_from_srun -n 4 -w "node[1-4]" ./mpi_app)"
assert_eq "-n -w nodes prog" "./mpi_app" "$r"

r="$(extract_program_from_srun --mpi=pmix -n 16 ./mpi_app arg1)"
assert_eq "--mpi=pmix prog" "./mpi_app" "$r"

r="$(extract_program_from_srun -n 4 -- ./mpi_app --flag)"
assert_eq "after -- separator" "./mpi_app" "$r"

r="$(extract_program_from_srun -c 4 -n 2 ./mpi_app)"
assert_eq "-c -n prog" "./mpi_app" "$r"

r="$(extract_program_from_srun --ntasks-per-node=2 -N 4 ./mpi_app)"
assert_eq "--ntasks-per-node=val prog" "./mpi_app" "$r"

r="$(extract_program_from_srun -o out.log -e err.log -n 4 ./mpi_app)"
assert_eq "-o -e -n prog" "./mpi_app" "$r"

r="$(extract_program_from_srun -p compute -A myacct -n 4 ./mpi_app)"
assert_eq "-p -A -n prog" "./mpi_app" "$r"

r="$(extract_program_from_srun --partition compute --account myacct --ntasks 4 ./mpi_app)"
assert_eq "long separate-value opts" "./mpi_app" "$r"

r="$(extract_program_from_srun -n 4 /opt/bin/my_mpi_app)"
assert_eq "absolute path" "/opt/bin/my_mpi_app" "$r"

r="$(extract_program_from_srun --distribution=block:cyclic --cpu-bind=cores -n 8 ./mpi_app)"
assert_eq "long=value opts" "./mpi_app" "$r"

r="$(extract_program_from_srun --gres=gpu:4 --mem=32G -n 4 -N 1 ./gpu_mpi_app)"
assert_eq "GPU MPI pattern" "./gpu_mpi_app" "$r"

r="$(extract_program_from_srun --ntasks-per-node 4 -N 2 --nodelist "node[01-02]" -- /opt/mpi/bench --iters 1000)"
assert_eq "complex MPI bench" "/opt/mpi/bench" "$r"

set +e; extract_program_from_srun -n 4 -w hosts >/dev/null 2>&1; rc=$?; set -e
assert_exit "no program → exit 1" 1 "$rc"

# ============================================================
# Part 2: Integration tests — mock trans-tools + srun
# ============================================================

echo "--- Integration: wrappersrun.sh end-to-end ---"

mkdir -p "${TMP}/bin"
cat > "${TMP}/bin/trans-tools" <<'MOCK'
#!/usr/bin/env bash
echo "$*" > "${MOCK_LOG_DIR}/trans-tools.log"
MOCK
chmod +x "${TMP}/bin/trans-tools"

cat > "${TMP}/bin/srun" <<'MOCK'
#!/usr/bin/env bash
echo "$*" > "${MOCK_LOG_DIR}/srun.log"
echo "${FAKEFS_DIRECT_MODE:-unset}" > "${MOCK_LOG_DIR}/fakefs_mode.log"
MOCK
chmod +x "${TMP}/bin/srun"

run_wrappersrun() {
  local log_dir="$1"; shift
  mkdir -p "$log_dir"
  (
    unset SLURM_NODELIST SLURM_JOB_NODELIST
    unset WRAPPERSRUN_ENABLE_DEPS WRAPPERSRUN_DEPS_NODES
    unset WRAPPERSRUN_DEPS_PROGRAM WRAPPERSRUN_DEPS_DEST
    unset WRAPPERSRUN_DEPS_PORT WRAPPERSRUN_DEPS_WIDTH
    unset WRAPPERSRUN_DEPS_BUFFER WRAPPERSRUN_DEPS_MIN_SIZE_MB
    unset WRAPPERSRUN_DEPS_FILTER_PREFIX WRAPPERSRUN_DEPS_AUTO_CLEAN
    unset WRAPPERSRUN_DEPS_INSECURE WRAPPERSRUN_FAKEFS_DIRECT_MODE
    unset WRAPPERSRUN_TRANS_TOOLS_BIN MOCK_LOG_DIR

    export MOCK_LOG_DIR="$log_dir"
    export PATH="${TMP}/bin:${PATH}"

    while [[ $# -gt 0 && "$1" != "--" ]]; do
      export "$1"; shift
    done
    [[ "${1:-}" == "--" ]] && shift

    exec bash "$WRAPPERSRUN" "$@"
  )
}

# --- Test: basic MPI, nodes from SLURM_NODELIST ---
d="${TMP}/t_basic"; set +e
run_wrappersrun "$d" "SLURM_NODELIST=node[001-004]" -- -n 4 /bin/hostname
rc=$?; set -e
assert_exit      "basic MPI: exit 0"         0 "$rc"
assert_file_exists   "basic MPI: deps called"    "$d/trans-tools.log"
assert_file_contains "basic MPI: deps nodes"     "$d/trans-tools.log" "--nodes node\[001-004\]"
assert_file_contains "basic MPI: deps program"   "$d/trans-tools.log" "--program /bin/hostname"
assert_file_exists   "basic MPI: srun called"    "$d/srun.log"
assert_file_contains "basic MPI: srun args"      "$d/srun.log" "^-n 4 /bin/hostname$"

# --- Test: MPI with explicit -w nodelist (no SLURM env) ---
d="${TMP}/t_explicit_w"; set +e
run_wrappersrun "$d" -- -n 8 -w "gpu[01-04]" /bin/hostname
rc=$?; set -e
assert_exit      "explicit -w: exit 0"       0 "$rc"
assert_file_contains "explicit -w: deps nodes"   "$d/trans-tools.log" "--nodes gpu\[01-04\]"
assert_file_contains "explicit -w: srun args"    "$d/srun.log" "-n 8 -w gpu\[01-04\] /bin/hostname"

# --- Test: WRAPPERSRUN_DEPS_NODES overrides -w in argv ---
d="${TMP}/t_env_override"; set +e
run_wrappersrun "$d" "WRAPPERSRUN_DEPS_NODES=override[1-2]" -- -n 4 -w "argv[1-4]" /bin/hostname
rc=$?; set -e
assert_exit      "env override: exit 0"      0 "$rc"
assert_file_contains "env override: deps uses env nodes" "$d/trans-tools.log" "--nodes override\[1-2\]"
assert_file_contains "env override: srun keeps argv"     "$d/srun.log" "-w argv\[1-4\]"

# --- Test: SLURM_JOB_NODELIST fallback ---
d="${TMP}/t_job_nodelist"; set +e
run_wrappersrun "$d" "SLURM_JOB_NODELIST=fallback[01-02]" -- -n 2 /bin/hostname
rc=$?; set -e
assert_exit      "JOB_NODELIST fallback: exit 0" 0 "$rc"
assert_file_contains "JOB_NODELIST: deps nodes"  "$d/trans-tools.log" "--nodes fallback\[01-02\]"

# --- Test: deps disabled — no trans-tools call, srun still runs ---
d="${TMP}/t_deps_off"; set +e
run_wrappersrun "$d" "WRAPPERSRUN_ENABLE_DEPS=false" -- -n 4 /bin/hostname
rc=$?; set -e
assert_exit          "deps off: exit 0"          0 "$rc"
assert_file_not_exists "deps off: no deps call"    "$d/trans-tools.log"
assert_file_exists     "deps off: srun called"     "$d/srun.log"
assert_file_contains   "deps off: srun args"       "$d/srun.log" "^-n 4 /bin/hostname$"

# --- Test: multi-node MPI layout ---
d="${TMP}/t_multinode"; set +e
run_wrappersrun "$d" "SLURM_NODELIST=cn[001-008]" -- -N 4 --ntasks-per-node=2 /bin/hostname
rc=$?; set -e
assert_exit      "multi-node: exit 0"        0 "$rc"
assert_file_contains "multi-node: deps nodes"    "$d/trans-tools.log" "--nodes cn\[001-008\]"
assert_file_contains "multi-node: deps program"  "$d/trans-tools.log" "--program /bin/hostname"
assert_file_contains "multi-node: srun passthru" "$d/srun.log" "-N 4 --ntasks-per-node=2 /bin/hostname"

# --- Test: MPI with -- separator ---
d="${TMP}/t_separator"; set +e
run_wrappersrun "$d" "SLURM_NODELIST=node01" -- -n 4 -- /bin/hostname --mpi-flag
rc=$?; set -e
assert_exit      "separator: exit 0"         0 "$rc"
assert_file_contains "separator: deps program"   "$d/trans-tools.log" "--program /bin/hostname"
assert_file_contains "separator: srun passthru"  "$d/srun.log" "-n 4 -- /bin/hostname --mpi-flag"

# --- Test: custom deps parameters forwarded to trans-tools ---
d="${TMP}/t_custom_params"; set +e
run_wrappersrun "$d" \
  "SLURM_NODELIST=node01" \
  "WRAPPERSRUN_DEPS_PORT=3000" \
  "WRAPPERSRUN_DEPS_BUFFER=4M" \
  "WRAPPERSRUN_DEPS_WIDTH=100" \
  "WRAPPERSRUN_DEPS_DEST=/data/deps" \
  "WRAPPERSRUN_DEPS_MIN_SIZE_MB=20" \
  "WRAPPERSRUN_DEPS_FILTER_PREFIX=/vol9" \
  -- -n 1 /bin/hostname
rc=$?; set -e
assert_exit      "custom params: exit 0"     0 "$rc"
assert_file_contains "custom: port"   "$d/trans-tools.log" "--port 3000"
assert_file_contains "custom: buffer" "$d/trans-tools.log" "--buffer 4M"
assert_file_contains "custom: width"  "$d/trans-tools.log" "--width 100"
assert_file_contains "custom: dest"   "$d/trans-tools.log" "--dest /data/deps"
assert_file_contains "custom: min-sz" "$d/trans-tools.log" "--min-size-mb 20"
assert_file_contains "custom: filter" "$d/trans-tools.log" "--filter-prefix /vol9"

# --- Test: auto-clean=false and insecure=false omit flags ---
d="${TMP}/t_no_flags"; set +e
run_wrappersrun "$d" \
  "SLURM_NODELIST=node01" \
  "WRAPPERSRUN_DEPS_AUTO_CLEAN=false" \
  "WRAPPERSRUN_DEPS_INSECURE=false" \
  -- -n 1 /bin/hostname
rc=$?; set -e
assert_exit "no-flags: exit 0" 0 "$rc"
if grep -qF 'auto-clean' "$d/trans-tools.log" 2>/dev/null; then
  echo "FAIL: no-flags: --auto-clean should be absent" >&2; fail=$((fail + 1))
else
  pass=$((pass + 1))
fi
if grep -qF 'insecure' "$d/trans-tools.log" 2>/dev/null; then
  echo "FAIL: no-flags: --insecure should be absent" >&2; fail=$((fail + 1))
else
  pass=$((pass + 1))
fi

# --- Test: WRAPPERSRUN_DEPS_PROGRAM overrides auto-detection ---
d="${TMP}/t_prog_override"; set +e
run_wrappersrun "$d" \
  "SLURM_NODELIST=node01" \
  "WRAPPERSRUN_DEPS_PROGRAM=/opt/real/mpi_app" \
  -- -n 4 /bin/hostname
rc=$?; set -e
assert_exit      "prog override: exit 0"     0 "$rc"
assert_file_contains "prog override: deps uses env" "$d/trans-tools.log" "--program /opt/real/mpi_app"
assert_file_contains "prog override: srun unchanged" "$d/srun.log" "/bin/hostname"

# --- Test: FAKEFS_DIRECT_MODE exported to srun ---
d="${TMP}/t_fakefs"; set +e
run_wrappersrun "$d" "SLURM_NODELIST=node01" "WRAPPERSRUN_FAKEFS_DIRECT_MODE=0" -- -n 1 /bin/hostname
rc=$?; set -e
assert_exit      "fakefs mode: exit 0"       0 "$rc"
assert_file_contains "fakefs mode=0 exported" "$d/fakefs_mode.log" "^0$"

d="${TMP}/t_fakefs1"; set +e
run_wrappersrun "$d" "SLURM_NODELIST=node01" -- -n 1 /bin/hostname
rc=$?; set -e
assert_file_contains "fakefs default=1" "$d/fakefs_mode.log" "^1$"

# --- Test: missing nodes with deps enabled → exit 1 ---
d="${TMP}/t_missing_nodes"; set +e
run_wrappersrun "$d" -- -n 4 /bin/hostname 2>/dev/null
rc=$?; set -e
assert_exit "missing nodes: exit 1" 1 "$rc"

# --- Test: no args → exit 2 ---
d="${TMP}/t_no_args"; set +e
run_wrappersrun "$d" "WRAPPERSRUN_ENABLE_DEPS=false" -- 2>/dev/null
rc=$?; set -e
assert_exit "no args: exit 2" 2 "$rc"

# --- Test: single invocation produces exactly one deps + one srun call ---
d="${TMP}/t_single"; set +e
run_wrappersrun "$d" "SLURM_NODELIST=node[001-004]" -- -N 4 -n 16 --ntasks-per-node=4 /bin/hostname
rc=$?; set -e
assert_exit "single invocation: exit 0" 0 "$rc"
deps_lines="$(wc -l < "$d/trans-tools.log")"
srun_lines="$(wc -l < "$d/srun.log")"
assert_eq "exactly 1 deps call" "1" "$deps_lines"
assert_eq "exactly 1 srun call" "1" "$srun_lines"

# ============================================================
# Summary
# ============================================================

echo ""
echo "Results: ${pass} passed, ${fail} failed"
if [[ "${fail}" -gt 0 ]]; then
  exit 1
fi
echo "OK: wrappersrun_test"
