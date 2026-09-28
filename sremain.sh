#!/usr/bin/env bash
set -euo pipefail

# Show where GPUs are free: per GPU type, how many are free. For the GPU
# types named on the command line, or all with -F, also each node with free
# GPUs and how many CPUs are left there. With -a, every node and who is
# using it.

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/common.sh"

FULL=0          # show nodes under their GPU type
ALL=0           # show every node, and the users on it
FILTERS=()      # GPU types to show

usage() {
  cat <<EOF
Usage: $(basename "$0") [-F|--full] [-a|--all] [-f|--file PATH] [--ascii] [GPU...]

Show free GPUs per GPU type. Name GPU types, or use -F, to also see their
nodes with the CPUs left beside the free GPUs.

Arguments:
  GPU              GPU type to show with its nodes, e.g. A6000. Case doesn't
                   matter; a name matching no type exactly picks every type
                   containing it (a100 -> all A100 types).

Options:
  -F, --full       Show the nodes of every GPU type
  -a, --all        Show every node, not just those with free GPUs, and the
                   users on it (implies -F if no GPU is named)
  -f, --file PATH  Read squeue output from a file (offline mode); sinfo is
                   read from $SINFO_SNAPSHOT next to it or in the current
                   directory if there is one
      --ascii      Draw with ASCII only (default: Unicode on UTF-8 locales)
  -h, --help       Show this help

cpus/gpu is a node's free CPUs per free GPU. A job needs CPUs too, so free
GPUs on a node with few CPUs left may not be usable. Nodes with no free CPU
are dimmed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -F|--full) FULL=1; shift ;;
    -a|--all) ALL=1; FULL=1; shift ;;
    -f|--file)
      [[ $# -ge 2 ]] || die "$1 requires a path"
      SQUEUE_FILE="$2"; shift 2 ;;
    --ascii) ASCII=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) FILTERS+=("$1"); shift ;;
  esac
done

declare -A USED_GPUS=() USED_CPUS=()   # node -> allocated
declare -A USER_GPUS=() USER_CPUS=()   # "node user" -> allocated
declare -A QUEUED=()                   # GPU type -> GPUs asked for by queued jobs

read_jobs() {
  local kind user part nodes cpus gpus list n per_cpu
  while read -r kind user part nodes cpus gpus list; do
    if [[ $kind == P ]]; then
      if (( gpus > 0 )); then add QUEUED "$part" $(( gpus * nodes )); fi
      continue
    fi
    expand_nodes "$list"
    if (( ${#EXPANDED[@]} == 0 )); then continue; fi
    per_cpu=$(( cpus / ${#EXPANDED[@]} ))
    for n in "${EXPANDED[@]}"; do
      if [[ -z ${NODE_TYPE[$n]:-} ]]; then continue; fi
      add USED_GPUS "$n" "$gpus"
      add USED_CPUS "$n" "$per_cpu"
      if (( ALL )); then
        add USER_GPUS "$n $user" "$gpus"
        add USER_CPUS "$n $user" "$per_cpu"
      fi
    done
  done < <(job_lines)
}

# Free GPUs and CPUs per node and per GPU type
declare -A FREE=() CPU_FREE=()
declare -A T_FREE=() T_GPUS=() T_CPU_FREE=() T_CPUS=()

count_free() {
  local n t f
  for n in "${NODES[@]}"; do
    f=$(( NODE_GPUS[$n] - ${USED_GPUS[$n]:-0} ))
    FREE[$n]=$(( f > 0 ? f : 0 ))
    f=$(( NODE_CPUS[$n] - ${USED_CPUS[$n]:-0} ))
    CPU_FREE[$n]=$(( f > 0 ? f : 0 ))
    t=${NODE_TYPE[$n]}
    add T_FREE "$t" "${FREE[$n]}"
    add T_GPUS "$t" "${NODE_GPUS[$n]}"
    add T_CPU_FREE "$t" "${CPU_FREE[$n]}"
    add T_CPUS "$t" "${NODE_CPUS[$n]}"
  done
}

# Users on each node as items like user:gpus/cpus, most GPUs first, CPU-only
# users dimmed. Fills USERS_ON.
declare -A USERS_ON=()

list_users() {
  local key n g c user
  while read -r n g c user; do
    if (( g > 0 )); then
      USERS_ON[$n]+="${USERS_ON[$n]:+$ITEM}$user:$g/$c"
    else
      USERS_ON[$n]+="${USERS_ON[$n]:+$ITEM}$C_DIM$user:$g/$c$C_END"
    fi
  done < <(for key in "${!USER_GPUS[@]}"; do
             printf '%s %s %s %s\n' "${key% *}" "${USER_GPUS[$key]}" "${USER_CPUS[$key]}" "${key#* }"
           done | sort -k2,2nr -k3,3nr -k4,4)
}

# The GPU types to show, in sinfo order: all, or those FILTERS name. A
# filter matching a type exactly (ignoring case) picks just that type,
# otherwise every type containing it. Sets SHOWN.
pick_types() {
  local f t match
  local -A pick=()
  SHOWN=()
  if (( ${#FILTERS[@]} == 0 )); then SHOWN=("${TYPES[@]}"); return; fi
  for f in "${FILTERS[@]}"; do
    match=""
    for t in "${TYPES[@]}"; do
      if [[ ${t,,} == "${f,,}" ]]; then match=$t; fi
    done
    if [[ -n $match ]]; then pick[$match]=1; continue; fi
    for t in "${TYPES[@]}"; do
      if [[ ${t,,} == *"${f,,}"* ]]; then pick[$t]=1; match=$t; fi
    done
    [[ -n $match ]] || die "no GPU type matches '$f' (types: ${TYPES[*]})"
  done
  for t in "${TYPES[@]}"; do
    if [[ -n ${pick[$t]:-} ]]; then SHOWN+=("$t"); fi
  done
}

# One table: a row per GPU type in SHOWN, each followed by its nodes with
# free GPUs (every node with -a), most free GPUs first, if nodes are shown
print_table() {
  local -A nodes_of=()
  local t f c n
  while read -r t f c n; do
    nodes_of[$t]+=" $n"
  done < <(for n in "${NODES[@]}"; do
             if (( FREE[$n] == 0 && ! ALL )); then continue; fi
             printf '%s %s %s %s\n' "${NODE_TYPE[$n]}" "${FREE[$n]}" "${CPU_FREE[$n]}" "$n"
           done | sort -k2,2nr -k3,3nr -k4,4V)

  # Rows as parallel arrays; the fractions are formatted all at once so
  # their slashes line up across type and node rows
  local -a names=() free=() gpus=() cpu_free=() cpus=() is_type=()
  for t in "${SHOWN[@]}"; do
    names+=("$t") is_type+=(1)
    free+=("${T_FREE[$t]}") gpus+=("${T_GPUS[$t]}")
    cpu_free+=("${T_CPU_FREE[$t]}") cpus+=("${T_CPUS[$t]}")
    if (( ! SHOW_NODES )); then continue; fi
    for n in ${nodes_of[$t]:-}; do
      names+=("$n") is_type+=(0)
      free+=("${FREE[$n]}") gpus+=("${NODE_GPUS[$n]}")
      cpu_free+=("${CPU_FREE[$n]}") cpus+=("${NODE_CPUS[$n]}")
    done
  done
  local -a gcells ccells
  fracs free gpus; gcells=("${FRACS[@]}")
  fracs cpu_free cpus; ccells=("${FRACS[@]}")

  local d=$C_DIM e=$C_END first="type" ratio_head="" users_head=""
  if (( SHOW_NODES )); then first="type / node" ratio_head="cpus/gpu"; fi
  if (( ALL )); then users_head="user:gpus/cpus"; fi
  tbl_new lrrrrl "$first" "free gpus" "free cpus" "$ratio_head" "queue" "$users_head"
  local i name g ratio tenths
  for i in "${!names[@]}"; do
    name=${names[i]} g=${gcells[i]} c=${ccells[i]}
    if (( is_type[i] )); then
      queue_cell "${QUEUED[$name]:-0}"
      if (( free[i] > 0 )); then
        color_free "$g" "$C_GREEN"
        tbl_row "$C_BOLD$name$e" "$REPLY" "$c" "" "$QUEUE_CELL" ""
      else
        tbl_row "$d$name$e" "$d$g$e" "$d$c$e" "" "$QUEUE_CELL" ""
      fi
      continue
    fi
    ratio=""
    if (( free[i] > 0 )); then
      tenths=$(( (cpu_free[i] * 20 + free[i]) / (2 * free[i]) ))
      ratio="$(( tenths / 10 )).$(( tenths % 10 ))"
    fi
    if (( free[i] > 0 && cpu_free[i] > 0 )); then
      color_free "$g" "$C_GREEN"
      tbl_row "  $name" "$REPLY" "$c" "$ratio" "" "${USERS_ON[$name]:-}"
    else
      tbl_row "  $d$name$e" "$d$g$e" "$d$c$e" "$d$ratio$e" "" "${USERS_ON[$name]:-}"
    fi
  done
  tbl_print
}

# Queued GPUs as a cell: +N in yellow, or a dim dot. Sets QUEUE_CELL.
queue_cell() {
  if (( $1 > 0 )); then
    QUEUE_CELL="$C_YELLOW+$1$C_END"
  else
    QUEUE_CELL="$C_DIM$G_NONE$C_END"
  fi
}

init_style
load_nodes
(( ${#NODES[@]} )) || die "no GPU nodes found in sinfo"
read_jobs
count_free
if (( ALL )); then list_users; fi
pick_types
SHOW_NODES=0
if (( FULL || ${#FILTERS[@]} )); then SHOW_NODES=1; fi

free=0 total=0 queued=0
for t in "${SHOWN[@]}"; do
  free=$(( free + T_FREE[$t] )) total=$(( total + T_GPUS[$t] ))
  queued=$(( queued + ${QUEUED[$t]:-0} ))
done
stats=("$free of $total free" "$queued queued")
if (( NODES_OFF == 1 )); then stats+=("1 node down"); fi
if (( NODES_OFF > 1 )); then stats+=("$NODES_OFF nodes down"); fi
print_title "GPU availability" "${stats[@]}"
print_table
