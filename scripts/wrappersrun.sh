#!/usr/bin/env bash
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
  WRAPPERSRUN_DEPS_NODES=<nodeset or host list>   # default: SLURM_NODELIST, fallback SLURM_JOB_NODELIST
  WRAPPERSRUN_DEPS_PROGRAM=<program path>         # default: auto-detect from srun command
  WRAPPERSRUN_DEPS_DEST=/tmp/dependencies
  WRAPPERSRUN_DEPS_PORT=2007
  WRAPPERSRUN_DEPS_WIDTH=50
  WRAPPERSRUN_DEPS_BUFFER=2M
  WRAPPERSRUN_DEPS_MIN_SIZE_MB=10
  WRAPPERSRUN_DEPS_FILTER_PREFIX=/vol8
  WRAPPERSRUN_DEPS_AUTO_CLEAN=true|false
  WRAPPERSRUN_DEPS_INSECURE=true|false
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
        --account|--acctg-freq|--array|--bb|--bbf|--bcast|--clusters|--comment|--constraint|--container|--container-id|--cpus-per-gpu|--cpus-per-task|--deadline|--delay-boot|--distribution|--error|--exclude|--export|--extra-node-info|--gpus|--gpus-per-node|--gpus-per-socket|--gpus-per-task|--gres|--gres-flags|--hint|--input|--job-name|--kill-on-bad-exit|--licenses|--mail-type|--mail-user|--mem|--mem-bind|--mem-per-cpu|--mem-per-gpu|--network|--nice|--nodelist|--ntasks|--ntasks-per-core|--ntasks-per-gpu|--ntasks-per-node|--nodes|--open-mode|--output|--partition|--power|--priority|--profile|--qos|--reservation|--signal|--sockets-per-node|--switches|--task-epilog|--task-prolog|--thread-spec|--threads-per-core|--time|--tmp|--uid|--wait|--wckey)
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

deps_nodes="${WRAPPERSRUN_DEPS_NODES:-${SLURM_NODELIST:-${SLURM_JOB_NODELIST:-}}}"
deps_program="${WRAPPERSRUN_DEPS_PROGRAM:-}"
deps_dest="${WRAPPERSRUN_DEPS_DEST:-/tmp/dependencies}"
deps_port="${WRAPPERSRUN_DEPS_PORT:-2007}"
deps_width="${WRAPPERSRUN_DEPS_WIDTH:-50}"
deps_buffer="${WRAPPERSRUN_DEPS_BUFFER:-2M}"
deps_min_size_mb="${WRAPPERSRUN_DEPS_MIN_SIZE_MB:-10}"
deps_filter_prefix="${WRAPPERSRUN_DEPS_FILTER_PREFIX:-/vol8}"
deps_auto_clean="$(to_bool "${WRAPPERSRUN_DEPS_AUTO_CLEAN:-true}" true)"
deps_insecure="$(to_bool "${WRAPPERSRUN_DEPS_INSECURE:-false}" false)"

if [[ "${enable_deps}" == "true" ]]; then
  if [[ -z "${deps_nodes}" ]]; then
    echo "missing nodes for deps, set WRAPPERSRUN_DEPS_NODES or provide SLURM_NODELIST/SLURM_JOB_NODELIST" >&2
    exit 1
  fi
  if [[ -z "${deps_program}" ]]; then
    if ! deps_program="$(extract_program_from_srun "$@")"; then
      echo "cannot detect program from srun args, set WRAPPERSRUN_DEPS_PROGRAM" >&2
      exit 1
    fi
  fi
  if [[ "${deps_program}" != /* ]]; then
    if ! deps_program="$(command -v "${deps_program}")"; then
      echo "resolve program failed: ${deps_program}" >&2
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
    --auto-clean "${deps_auto_clean}"
  )
  if [[ "${deps_insecure}" == "true" ]]; then
    deps_cmd+=(--insecure)
  fi
  "${deps_cmd[@]}"
fi

exec srun "$@"
