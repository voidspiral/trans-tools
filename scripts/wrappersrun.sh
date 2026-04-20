#!/bin/bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
wrappersrun.sh - srun-compatible wrapper with fixed trans-tools deps

Usage:
  wrappersrun.sh <all original srun args...>

Workflow:
  1) trans-tools deps
  2) srun (all args passthrough)

Environment (optional):
  WRAPPERSRUN_ENABLE_DEPS=true|false
  WRAPPERSRUN_TRANS_TOOLS_BIN=trans-tools
  WRAPPERSRUN_DEPS_NODES=<nodeset or host list>   # see Nodes note below
  WRAPPERSRUN_DEPS_PROGRAM=<program path>         # default: auto-detect from srun command
  WRAPPERSRUN_DEPS_DEST=/tmp/dependencies
  WRAPPERSRUN_DEPS_PORT=2007
  WRAPPERSRUN_DEPS_WIDTH=50
  WRAPPERSRUN_DEPS_BUFFER=2M
  WRAPPERSRUN_DEPS_MIN_SIZE_MB=10
  WRAPPERSRUN_DEPS_FILTER_PREFIX=/vol8
  WRAPPERSRUN_DEPS_AUTO_CLEAN=true|false
  WRAPPERSRUN_DEPS_INSECURE=true|false         # default true
  WRAPPERSRUN_FAKEFS_DIRECT_MODE=1|0           # default 1, exported as FAKEFS_DIRECT_MODE
  WRAPPERSRUN_SRUN_MPI=<srun --mpi value>      # e.g. none when Open MPI lacks Slurm PMI
  WRAPPERSRUN_LAUNCHER=srun|mpirun             # default srun; mpirun for MPI without Slurm PMI (Open MPI vs MPICH detected)
  WRAPPERSRUN_POST_DEPS_HOOK=<shell command>  # optional; runs after successful deps (testing / site hooks)

Nodes for deps (first non-empty wins):
  1) WRAPPERSRUN_DEPS_NODES
  2) explicit srun -w / --nodelist in argv (only if you name hosts; -N/-n alone = no list)
  3) SLURM_NODELIST or SLURM_JOB_NODELIST (e.g. after salloc or inside sbatch)

Random allocation (srun -N1 -n1 with no -w) has no host list before srun runs deps.
  Use an allocation shell (salloc/sbatch), export WRAPPERSRUN_DEPS_NODES, set
  WRAPPERSRUN_ENABLE_DEPS=false, or push dependency delivery to site prolog / another step.
EOF
  exit 0
fi

if [[ $# -eq 0 ]]; then
  echo "missing srun arguments" >&2
  exit 2
fi

to_bool() {
  local v
  v="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "${v}" in
    1|true|yes|y|on) echo "true" ;;
    0|false|no|n|off) echo "false" ;;
    *) echo "${2:-false}" ;;
  esac
}

contains_equals() {
  [[ "$1" == *"="* ]]
}

trim_wrapping_quotes() {
  local s="${1:-}"
  if [[ ${#s} -ge 2 ]]; then
    if [[ "${s:0:1}" == "'" && "${s: -1}" == "'" ]]; then
      s="${s:1:${#s}-2}"
    elif [[ "${s:0:1}" == '"' && "${s: -1}" == '"' ]]; then
      s="${s:1:${#s}-2}"
    fi
  fi
  printf '%s' "${s}"
}

sanitize_nodes_expr() {
  local s
  s="$(trim_wrapping_quotes "${1:-}")"
  s="${s//\'/}"
  s="${s//\"/}"
  printf '%s' "${s}"
}

# Slurm node list from argv: -w HOST, -wHOST, --nodelist HOST, --nodelist=HOST (before --).
# Last occurrence wins. -N / --nodes is a count, not a hostname list (not parsed).
extract_nodelist_from_srun() {
  local args=("$@")
  local i=0
  local found=""
  while (( i < ${#args[@]} )); do
    local a="${args[$i]}"
    if [[ "${a}" == "--" ]]; then
      break
    fi
    if [[ "${a}" == --nodelist=* ]]; then
      found="${a#--nodelist=}"
      ((i++))
      continue
    fi
    if [[ "${a}" == --nodelist ]]; then
      ((i++))
      (( i < ${#args[@]} )) || break
      found="${args[$i]}"
      ((i++))
      continue
    fi
    if [[ "${a}" == -w ]]; then
      ((i++))
      (( i < ${#args[@]} )) || break
      found="${args[$i]}"
      ((i++))
      continue
    fi
    if [[ "${a}" == -w* ]]; then
      found="${a#-w}"
      ((i++))
      continue
    fi
    ((i++))
  done
  if [[ -n "${found}" ]]; then
    echo "${found}"
    return 0
  fi
  return 1
}

resolve_trans_tools_bin() {
  local candidate="${1:-}"
  local resolved=""
  if [[ -z "${candidate}" ]]; then
    printf '%s' "${candidate}"
    return 0
  fi
  if [[ "${candidate}" == /* ]]; then
    printf '%s' "${candidate}"
    return 0
  fi
  resolved="$(command -v -- "${candidate}" 2>/dev/null || true)"
  if [[ -n "${resolved}" ]]; then
    printf '%s' "${resolved}"
    return 0
  fi
  printf '%s' "${candidate}"
}

extract_program_from_srun() {
  local args=("$@")
  local i=0
  while (( i < ${#args[@]} )); do
    local a="${args[$i]}"
    if [[ "${a}" == "--" ]]; then
      ((i++))
      [[ ${i} -lt ${#args[@]} ]] || return 1
      echo "${args[$i]}"
      return 0
    fi
    if [[ "${a}" != -* || "${a}" == "-" ]]; then
      echo "${a}"
      return 0
    fi
    if [[ "${a}" == --* ]]; then
      if contains_equals "${a}"; then
        ((i++))
        continue
      fi
      case "${a}" in
        --account|--acctg-freq|--array|--bb|--bbf|--bcast|--chdir|--clusters|--comment|--constraint|--container|--container-id|--cpus-per-gpu|--cpus-per-task|--deadline|--delay-boot|--distribution|--error|--exclude|--export|--extra-node-info|--gpus|--gpus-per-node|--gpus-per-socket|--gpus-per-task|--gres|--gres-flags|--hint|--input|--job-name|--kill-on-bad-exit|--licenses|--mail-type|--mail-user|--mem|--mem-bind|--mem-per-cpu|--mem-per-gpu|--network|--nice|--nodelist|--ntasks|--ntasks-per-core|--ntasks-per-gpu|--ntasks-per-node|--nodes|--open-mode|--output|--partition|--power|--priority|--profile|--qos|--reservation|--signal|--sockets-per-node|--switches|--task-epilog|--task-prolog|--thread-spec|--threads-per-core|--time|--tmp|--uid|--wait|--wckey)
          ((i+=2))
          continue
          ;;
        *)
          ((i++))
          continue
          ;;
      esac
    fi
    if [[ "${#a}" -eq 2 ]]; then
      case "${a}" in
        -A|-a|-b|-B|-c|-C|-D|-d|-e|-E|-f|-G|-i|-I|-J|-K|-L|-m|-M|-N|-n|-o|-O|-p|-Q|-q|-R|-S|-s|-T|-t|-u|-v|-W|-w|-x|-X|-Z)
          ((i+=2))
          continue
          ;;
      esac
    fi
    ((i++))
  done
  return 1
}

enable_deps="$(to_bool "${WRAPPERSRUN_ENABLE_DEPS:-true}" true)"

trans_tools_bin="${WRAPPERSRUN_TRANS_TOOLS_BIN:-trans-tools}"
if [[ "${enable_deps}" == "true" ]]; then
  trans_tools_bin="$(resolve_trans_tools_bin "${trans_tools_bin}")"
  if [[ -z "${trans_tools_bin}" || ! -x "${trans_tools_bin}" ]]; then
    echo "WRAPPERSRUN_TRANS_TOOLS_BIN not found or not executable: ${WRAPPERSRUN_TRANS_TOOLS_BIN:-trans-tools}" >&2
    exit 1
  fi
fi

deps_nodes="${WRAPPERSRUN_DEPS_NODES:-}"
if [[ -z "${deps_nodes}" ]]; then
  if parsed="$(extract_nodelist_from_srun "$@")"; then
    deps_nodes="${parsed}"
  fi
fi
if [[ -z "${deps_nodes}" ]]; then
  deps_nodes="${SLURM_NODELIST:-${SLURM_JOB_NODELIST:-}}"
fi
deps_nodes="$(sanitize_nodes_expr "${deps_nodes}")"
deps_program="${WRAPPERSRUN_DEPS_PROGRAM:-}"
deps_dest="${WRAPPERSRUN_DEPS_DEST:-/tmp/dependencies}"
deps_port="${WRAPPERSRUN_DEPS_PORT:-2007}"
deps_width="${WRAPPERSRUN_DEPS_WIDTH:-50}"
deps_buffer="${WRAPPERSRUN_DEPS_BUFFER:-2M}"
deps_min_size_mb="${WRAPPERSRUN_DEPS_MIN_SIZE_MB:-10}"
deps_filter_prefix="${WRAPPERSRUN_DEPS_FILTER_PREFIX:-/vol8}"
deps_auto_clean="$(to_bool "${WRAPPERSRUN_DEPS_AUTO_CLEAN:-true}" true)"
deps_insecure="$(to_bool "${WRAPPERSRUN_DEPS_INSECURE:-true}" true)"
wrappersrun_fakefs_direct_mode="${WRAPPERSRUN_FAKEFS_DIRECT_MODE:-1}"

if [[ "${wrappersrun_fakefs_direct_mode}" != "0" && "${wrappersrun_fakefs_direct_mode}" != "1" ]]; then
  echo "invalid WRAPPERSRUN_FAKEFS_DIRECT_MODE: ${wrappersrun_fakefs_direct_mode} (expected 0 or 1)" >&2
  exit 2
fi
export FAKEFS_DIRECT_MODE="${wrappersrun_fakefs_direct_mode}"

if [[ "${enable_deps}" == "true" ]]; then
  if [[ -z "${deps_nodes}" ]]; then
    echo "missing nodes for deps: set WRAPPERSRUN_DEPS_NODES, use SLURM allocation env, or pass srun -w/--nodelist" >&2
    exit 1
  fi
  if [[ -z "${deps_program}" ]]; then
    if ! deps_program="$(extract_program_from_srun "$@")"; then
      echo "cannot detect program from srun args, set WRAPPERSRUN_DEPS_PROGRAM" >&2
      exit 1
    fi
  fi
  if [[ "${deps_program}" != /* ]]; then
    unresolved_program="${deps_program}"
    if ! deps_program="$(command -v "${deps_program}")"; then
      echo "resolve program failed: ${unresolved_program}" >&2
      exit 1
    fi
  fi

  deps_cmd=(
    "${trans_tools_bin}" deps
    --program "${deps_program}"
    --nodes "${deps_nodes}"
    --port "${deps_port}"
    --buffer "${deps_buffer}"
    --width "${deps_width}"
    --dest "${deps_dest}"
    --min-size-mb "${deps_min_size_mb}"
    --filter-prefix "${deps_filter_prefix}"
  )
  if [[ "${deps_auto_clean}" == "true" ]]; then
    deps_cmd+=(--auto-clean)
  fi
  if [[ "${deps_insecure}" == "true" ]]; then
    deps_cmd+=(--insecure)
  fi
  "${deps_cmd[@]}"
  if [[ -n "${WRAPPERSRUN_POST_DEPS_HOOK:-}" ]]; then
    bash -c "${WRAPPERSRUN_POST_DEPS_HOOK}"
  fi
fi

wrappersrun_launcher="${WRAPPERSRUN_LAUNCHER:-srun}"
if [[ "${wrappersrun_launcher}" == "mpirun" ]]; then
  mpirun_is_mpich=0
  if mpirun --version 2>/dev/null | grep -qi HYDRA; then
    mpirun_is_mpich=1
  fi
  if [[ "${mpirun_is_mpich}" -eq 0 ]] && [[ "$(id -u)" -eq 0 ]]; then
    export OMPI_ALLOW_RUN_AS_ROOT=1
    export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
  fi
  mpirun_ntasks=1
  mpirun_host=""
  mpirun_forward=()
  mpirun_i=0
  mpirun_arr=("$@")
  while (( mpirun_i < ${#mpirun_arr[@]} )); do
    mpirun_a="${mpirun_arr[mpirun_i]}"
    case "${mpirun_a}" in
      -n|--ntasks)
        ((++mpirun_i))
        if (( mpirun_i >= ${#mpirun_arr[@]} )); then
          echo "missing value for ${mpirun_a}" >&2
          exit 2
        fi
        mpirun_ntasks="${mpirun_arr[mpirun_i]}"
        ;;
      -n[0-9]*)
        mpirun_ntasks="${mpirun_a#-n}"
        ;;
      --ntasks=*)
        mpirun_ntasks="${mpirun_a#*=}"
        ;;
      -w|--nodelist)
        ((++mpirun_i))
        if (( mpirun_i >= ${#mpirun_arr[@]} )); then
          echo "missing value for ${mpirun_a}" >&2
          exit 2
        fi
        mpirun_host="${mpirun_arr[mpirun_i]}"
        ;;
      --nodelist=*)
        mpirun_host="${mpirun_a#*=}"
        ;;
      *)
        mpirun_forward+=("${mpirun_a}")
        ;;
    esac
    ((++mpirun_i))
  done
  mpirun_cmd=(mpirun)
  if [[ "${mpirun_is_mpich}" -eq 0 ]]; then
    mpirun_cmd+=(--oversubscribe)
  fi
  mpirun_cmd+=(-n "${mpirun_ntasks}")
  if [[ -n "${mpirun_host}" ]]; then
    if [[ "${mpirun_is_mpich}" -eq 1 ]]; then
      mpirun_cmd+=(-hosts "${mpirun_host}:${mpirun_ntasks}")
    else
      mpirun_cmd+=(-host "${mpirun_host}:${mpirun_ntasks}")
    fi
  fi
  mpirun_cmd+=("${mpirun_forward[@]}")
  exec "${mpirun_cmd[@]}"
fi

srun_mpi=()
if [[ -n "${WRAPPERSRUN_SRUN_MPI:-}" ]]; then
  srun_mpi=(--mpi="${WRAPPERSRUN_SRUN_MPI}")
fi
exec srun "${srun_mpi[@]}" "$@"
