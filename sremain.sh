#!/usr/bin/env bash
set -euo pipefail

# Show where GPUs are free: per GPU type, how many are free and on which
# nodes. With -a, also every node and who is using it.

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/common.sh"

ALL=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [-a|--all] [-f|--file PATH] [--ascii]

Show free GPUs per GPU type and the nodes they are on.

Options:
  -a, --all        Also list every node with the users on it
  -f, --file PATH  Read squeue output from a file (offline mode); sinfo is
                   read from $SINFO_SNAPSHOT next to it or in the current
                   directory if there is one
      --ascii      Draw with ASCII only (default: Unicode on UTF-8 locales)
  -h, --help       Show this help

node:free lists nodes by how many GPUs they have free, e.g. n[4-5]:8.
GPUs on a node with no free CPU can't be used, so they aren't counted as
free and are listed last, after "no CPU:".
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--all) ALL=1; shift ;;
    -f|--file)
      [[ $# -ge 2 ]] || die "$1 requires a path"
      SQUEUE_FILE="$2"; shift 2 ;;
    --ascii) ASCII=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
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

# Free GPUs and CPUs per node. A node's free GPUs are usable only if it
# has a free CPU too; the rest are stranded.
declare -A FREE=() CPU_FREE=()
STRANDED=0

count_free() {
  local n f
  for n in "${NODES[@]}"; do
    f=$(( NODE_GPUS[$n] - ${USED_GPUS[$n]:-0} ))
    FREE[$n]=$(( f > 0 ? f : 0 ))
    f=$(( NODE_CPUS[$n] - ${USED_CPUS[$n]:-0} ))
    CPU_FREE[$n]=$(( f > 0 ? f : 0 ))
    if (( CPU_FREE[$n] == 0 )); then STRANDED=$(( STRANDED + FREE[$n] )); fi
  done
}

# Per GPU type: free/total GPUs and CPUs, queued GPUs, and its nodes grouped
# by free GPUs, most first. Fills the T_* arrays in TYPES order.
T_FREE=() T_GPUS=() T_CPU_FREE=() T_CPUS=() T_ITEMS=()

sum_types() {
  local -A free=() gpus=() cpu_free=() cpus=() most=() groups=() stranded=()
  local t n f key
  for n in "${NODES[@]}"; do
    t=${NODE_TYPE[$n]} f=${FREE[$n]}
    add gpus "$t" "${NODE_GPUS[$n]}"
    add cpus "$t" "${NODE_CPUS[$n]}"
    add cpu_free "$t" "${CPU_FREE[$n]}"
    if (( f == 0 )); then continue; fi
    if (( f > ${most[$t]:-0} )); then most[$t]=$f; fi
    if (( CPU_FREE[$n] == 0 )); then stranded["$t $f"]+=" $n"; continue; fi
    add free "$t" "$f"
    groups["$t $f"]+=" $n"
  done

  local -a items no_cpu
  for t in "${TYPES[@]}"; do
    items=() no_cpu=()
    for (( f=${most[$t]:-0}; f>0; f-- )); do
      key="$t $f"
      if [[ -n ${groups[$key]:-} ]]; then
        # shellcheck disable=SC2086
        compress_nodes ${groups[$key]}
        items+=("$REPLY:$f")
      fi
      if [[ -n ${stranded[$key]:-} ]]; then
        # shellcheck disable=SC2086
        compress_nodes ${stranded[$key]}
        no_cpu+=("$REPLY:$f")
      fi
    done
    if (( ${#no_cpu[@]} )); then items+=("${C_DIM}no CPU: ${no_cpu[*]}$C_END"); fi
    items_join "${items[@]}"
    T_ITEMS+=("$REPLY")
    T_FREE+=("${free[$t]:-0}") T_GPUS+=("${gpus[$t]}")
    T_CPU_FREE+=("${cpu_free[$t]}") T_CPUS+=("${cpus[$t]}")
  done
}

# Queued GPUs as a cell: +N in yellow, or a dim dot
queue_cell() {
  if (( $1 > 0 )); then REPLY="$C_YELLOW+$1$C_END"; else REPLY="$C_DIM$G_NONE$C_END"; fi
}

print_types() {
  local -a gcells ccells
  fracs T_FREE T_GPUS; gcells=("${FRACS[@]}")
  fracs T_CPU_FREE T_CPUS; ccells=("${FRACS[@]}")
  tbl_new lrrrl "type" "free gpus" "queue" "free cpus" "node:free"
  local i t g c q
  for i in "${!TYPES[@]}"; do
    t=${TYPES[i]} g=${gcells[i]} c=${ccells[i]}
    queue_cell "${QUEUED[$t]:-0}"; q=$REPLY
    if (( T_FREE[i] > 0 )); then
      color_free "$g" "$C_GREEN"
      tbl_row "$t" "$REPLY" "$q" "$c" "${T_ITEMS[i]}"
    else
      tbl_row "$C_DIM$t$C_END" "$C_DIM$g$C_END" "$q" "$C_DIM$c$C_END" "${T_ITEMS[i]}"
    fi
  done
  tbl_print
}

print_nodes() {
  # Users per node, most GPUs first; CPU-only users dimmed
  local -A users=()
  local n user g c
  while read -r n g c user; do
    if (( g > 0 )); then
      users[$n]+="$ITEM$user:$g/$c"
    else
      users[$n]+="$ITEM$C_DIM$user:$g/$c$C_END"
    fi
  done < <(for key in "${!USER_GPUS[@]}"; do
             printf '%s %s %s %s\n' "${key% *}" "${USER_GPUS[$key]}" "${USER_CPUS[$key]}" "${key#* }"
           done | sort -k2,2nr -k3,3nr -k4,4)

  local -a free=() gpus=() cpu_free=() cpus=() gcells ccells
  for n in "${NODES[@]}"; do
    free+=("${FREE[$n]}") gpus+=("${NODE_GPUS[$n]}")
    cpu_free+=("${CPU_FREE[$n]}") cpus+=("${NODE_CPUS[$n]}")
  done
  fracs free gpus; gcells=("${FRACS[@]}")
  fracs cpu_free cpus; ccells=("${FRACS[@]}")

  tbl_new llrrl "node" "type" "free gpus" "free cpus" "user:gpus/cpus"
  local i list
  for i in "${!NODES[@]}"; do
    n=${NODES[i]} list=${users[${NODES[i]}]:-}
    list=${list#"$ITEM"}
    if (( free[i] > 0 && cpu_free[i] > 0 )); then
      color_free "${gcells[i]}" "$C_GREEN"
      tbl_row "$n" "${NODE_TYPE[$n]}" "$REPLY" "${ccells[i]}" "$list"
    else
      tbl_row "$C_DIM$n$C_END" "$C_DIM${NODE_TYPE[$n]}$C_END" "$C_DIM${gcells[i]}$C_END" \
        "$C_DIM${ccells[i]}$C_END" "$list"
    fi
  done
  tbl_print
}

init_style
load_nodes
(( ${#NODES[@]} )) || die "no GPU nodes found in sinfo"
read_jobs
count_free
sum_types

free=0 total=0 queued=0
for i in "${!TYPES[@]}"; do
  free=$(( free + T_FREE[i] )) total=$(( total + T_GPUS[i] ))
  queued=$(( queued + ${QUEUED[${TYPES[i]}]:-0} ))
done
stats=("$free of $total free" "$queued queued")
if (( STRANDED )); then stats+=("$STRANDED without a free CPU"); fi
if (( NODES_OFF == 1 )); then stats+=("1 node down"); fi
if (( NODES_OFF > 1 )); then stats+=("$NODES_OFF nodes down"); fi
print_title "GPU availability" "${stats[@]}"
print_types
if (( ALL )); then
  echo
  print_nodes
fi
