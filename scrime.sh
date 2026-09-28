#!/usr/bin/env bash
set -euo pipefail

# Show who is using the GPUs: per user, running and queued GPUs, their share
# of all running GPUs, and the GPU type they use most.

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/common.sh"

THRESHOLD=10    # percent of running GPUs to flag as "criminal"
WTF=50          # queued GPUs to flag as "WTF"

usage() {
  cat <<EOF
Usage: $(basename "$0") [-f|--file PATH] [-t|--threshold PCT] [--ascii]

Show running and queued GPUs per user.

Options:
  -f, --file PATH    Read squeue output from a file (offline mode); sinfo is
                     read from $SINFO_SNAPSHOT next to it or in the current
                     directory if there is one
  -t, --threshold N  Percent of running GPUs to flag as CRIMINAL (default: $THRESHOLD)
      --ascii        Draw with ASCII only (default: Unicode on UTF-8 locales)
  -h, --help         Show this help

main is the GPU type a user runs the most GPUs on, with that count; more
counts the other types they run on. Users queuing more than $WTF GPUs are
flagged WTF.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)
      [[ $# -ge 2 ]] || die "$1 requires a path"
      SQUEUE_FILE="$2"; shift 2 ;;
    -t|--threshold)
      [[ $# -ge 2 ]] || die "$1 requires a number"
      THRESHOLD="$2"; shift 2 ;;
    --ascii) ASCII=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done
[[ $THRESHOLD =~ ^[0-9]+$ ]] || die "threshold must be a whole number of percent"

declare -A RUN=() QUEUE=()          # user -> GPUs
declare -A RUN_ON=() QUEUE_ON=()    # "user type" -> GPUs
TOTAL_RUN=0 TOTAL_QUEUE=0

# Running GPUs count toward the type of the node they are on; queued ones
# toward the job's (first) partition
read_jobs() {
  local kind user part nodes cpus gpus list n
  while read -r kind user part nodes cpus gpus list; do
    if (( gpus == 0 )); then continue; fi
    if [[ $kind == P ]]; then
      gpus=$(( gpus * nodes ))
      add QUEUE "$user" "$gpus"
      add QUEUE_ON "$user $part" "$gpus"
      TOTAL_QUEUE=$(( TOTAL_QUEUE + gpus ))
      continue
    fi
    expand_nodes "$list"
    for n in "${EXPANDED[@]}"; do
      add RUN "$user" "$gpus"
      add RUN_ON "$user ${NODE_TYPE[$n]:-$part}" "$gpus"
      TOTAL_RUN=$(( TOTAL_RUN + gpus ))
    done
  done < <(job_lines)
}

# Each user's main GPU type: the one they run the most GPUs on, or for
# users with only queued GPUs, the one they queue the most on. Fills
# MAIN_TYPE, MAIN_RUN and MAIN_QUEUE with it and OTHER_TYPES with how many
# other types a user runs on.
declare -A MAIN_TYPE=() MAIN_RUN=() MAIN_QUEUE=() OTHER_TYPES=()

find_main_types() {
  local user run queue type key
  local -A seen=()
  while read -r user run queue type; do
    if [[ -z ${MAIN_TYPE[$user]:-} ]]; then
      MAIN_TYPE[$user]=$type MAIN_RUN[$user]=$run MAIN_QUEUE[$user]=$queue
    elif (( run > 0 )); then
      add OTHER_TYPES "$user" 1
    fi
  done < <(for key in "${!RUN_ON[@]}" "${!QUEUE_ON[@]}"; do
             if [[ -n ${seen[$key]:-} ]]; then continue; fi
             seen[$key]=1
             printf '%s %s %s %s\n' "${key% *}" "${RUN_ON[$key]:-0}" "${QUEUE_ON[$key]:-0}" "${key#* }"
           done | sort -k1,1 -k2,2nr -k3,3nr -k4,4)
}

print_report() {
  if (( TOTAL_RUN == 0 )); then
    printf '%sNo running GPU jobs found.%s\n' "$C_YELLOW" "$C_END"
    return
  fi

  # Users running GPUs, most first, then users with only queued GPUs
  local -a users=()
  local user run queue nrun=0
  while read -r run queue user; do
    users+=("$user")
    if (( run > 0 )); then nrun=$(( nrun + 1 )); fi
  done < <(for user in "${!RUN[@]}" "${!QUEUE[@]}"; do
             printf '%s %s %s\n' "${RUN[$user]:-0}" "${QUEUE[$user]:-0}" "$user"
           done | sort -u | sort -k1,1nr -k2,2nr -k3,3)

  local capacity=0 i
  for i in "${NODES[@]}"; do capacity=$(( capacity + NODE_GPUS[$i] )); done
  local stats=("$TOTAL_RUN running") limit=$(( (THRESHOLD * TOTAL_RUN + 99) / 100 ))
  if (( capacity )); then stats=("$TOTAL_RUN of $capacity running"); fi
  stats+=("$TOTAL_QUEUE queued" "$nrun users" "limit $THRESHOLD% = $limit")
  print_title "GPU usage" "${stats[@]}"

  local d=$C_DIM e=$C_END none="$C_DIM$G_NONE$C_END"
  tbl_new rlrrrlrll "#" "user" "gpus" "queue" "share" "main" "" "more" ""
  local rank name gpus qcell share flags tenths count more other
  for i in "${!users[@]}"; do
    user=${users[i]} run=${RUN[${users[i]}]:-0} queue=${QUEUE[${users[i]}]:-0}
    if (( i == nrun )); then tbl_note 1 "${d}queued only$e"; fi
    rank=$none gpus=$none qcell=$none share=$none name=$user flags=""
    if (( run > 0 )); then
      rank=$(( i + 1 )) gpus=$run
      tenths=$(( (run * 2000 + TOTAL_RUN) / (2 * TOTAL_RUN) ))
      share="$(( tenths / 10 )).$(( tenths % 10 ))%"
    fi
    if (( queue > 0 )); then qcell="$C_YELLOW+$queue$e"; fi
    if (( run * 100 >= THRESHOLD * TOTAL_RUN )); then
      name="$C_RED$user$e" flags="${C_RED}CRIMINAL$e"
    fi
    if (( queue > WTF )); then flags+="${flags:+ }${C_YELLOW}WTF$e"; fi
    count=${MAIN_RUN[$user]}
    if (( count == 0 )); then count="$C_YELLOW+${MAIN_QUEUE[$user]}$e"; fi
    other=${OTHER_TYPES[$user]:-0} more=""
    if (( other == 1 )); then more="$d+1 type$e"; fi
    if (( other > 1 )); then more="$d+$other types$e"; fi
    tbl_row "$rank" "$name" "$gpus" "$qcell" "$share" "${MAIN_TYPE[$user]}" "$count" "$more" "$flags"
  done
  tbl_print
}

init_style
load_nodes
read_jobs
find_main_types
print_report
