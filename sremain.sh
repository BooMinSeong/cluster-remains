#!/usr/bin/env bash
set -euo pipefail

# Colors
HEADER="\033[95m"
OKGREEN="\033[92m"
WARNING="\033[93m"
FAIL="\033[91m"
# Sky-blue for fully free GPU nodes when -a is set
SKYBLUE="\033[96m"
ENDC="\033[0m"

ALL=0
SQUEUE_FILE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [-a|--all] [-f|--file squeue_file]

Options:
  -a, --all        Show all nodes and include USERS column per node
  -f, --file PATH  Read squeue output from a file; when set, also try to read
                   sinfo snapshot from 20251105.sinfo (same dir or CWD)
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--all) ALL=1; shift ;;
    -f|--file)
      [[ $# -ge 2 ]] || { echo "-f|--file requires a path" >&2; exit 1; }
      SQUEUE_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# Declare associative arrays
declare -A CLUSTER_GPU_TOTAL   # partition -> total GPUs
declare -A CLUSTER_CPU_TOTAL   # partition -> total CPUs
declare -A NODE_GPU_TYPE       # node -> partition name
declare -A NODE_GPU_PER_NODE   # node -> gpu per node
declare -A NODE_CPU_PER_NODE   # node -> cpu per node
declare -A NODE_STATE          # node -> state
declare -A DRNG_NODE_SET       # node -> 1 (draining)

declare -A DEV_USED_GPU        # partition -> used GPUs (from squeue)
declare -A DEV_USED_CPU        # partition -> used CPUs (from squeue)
declare -A NODE_USED_GPU       # node -> used GPUs
declare -A NODE_USED_CPU       # node -> used CPUs
declare -A NODE_USER_GPU       # key "node|user" -> gpu count
declare -A NODE_USER_CPU       # key "node|user" -> cpu count

trim() { sed 's/^\s\+//; s/\s\+$//' ; }

parse_gpu_count_from_tres() {
  local field="$1"
  [[ -z "$field" ]] && { echo 0; return; }
  if [[ "$field" == "N/A" ]]; then echo 0; return; fi
  if [[ "$field" != *"gres/gpu"* ]]; then echo 0; return; fi
  local norm="${field//=/:}"
  IFS=',' read -r first _ <<< "$norm"
  IFS=':' read -r -a parts <<< "$first"
  for (( i=${#parts[@]}-1; i>=0; i-- )); do
    if [[ ${parts[$i]} =~ ^[0-9]+$ ]]; then
      echo "${parts[$i]}"; return
    fi
  done
  # no explicit count but it's a gpu TRES
  echo 1
}

parse_gpu_count_from_gres_feature() {
  local gres="$1"; shift || true
  local feat="$1"; shift || true
  local cnt=""
  # Try feature like '...-8GPU'
  cnt=$(printf '%s' "$feat" | grep -Eo '([0-9]+)GPU' | tail -n1 | grep -Eo '[0-9]+' || true)
  if [[ -n "$cnt" ]]; then echo "$cnt"; return; fi
  # Try gres like 'gpu:MODEL:8'
  cnt=$(printf '%s' "$gres" | awk -F: '{for(i=NF;i>=1;i--) if($i ~ /^[0-9]+$/){print $i; exit}}')
  if [[ -n "$cnt" ]]; then echo "$cnt"; return; fi
  echo 0
}

expand_nodelist() {
  local nl="$1"
  if [[ -z "$nl" ]]; then return; fi
  if [[ "$nl" =~ ^n\[[^]]+\]$ ]]; then
    local inside="${nl#n[}"; inside="${inside%]}"
    IFS=',' read -r -a parts <<< "$inside"
    for p in "${parts[@]}"; do
      if [[ "$p" == *-* ]]; then
        local s="${p%-*}"; local e="${p#*-}"
        for ((i=s; i<=e; i++)); do printf 'n%s ' "$i"; done
      else
        printf 'n%s ' "$p"
      fi
    done
  elif [[ "$nl" =~ ^n[0-9]+$ ]]; then
    printf '%s' "$nl"
  else
    # not a node list we recognize
    return
  fi
}

read_sinfo() {
  local sinfo_lines
  if [[ -n "$SQUEUE_FILE" ]]; then
    local base_dir
    base_dir=$(dirname -- "$SQUEUE_FILE")
    local candidate="$base_dir/20251105.sinfo"
    if [[ -r "$candidate" ]]; then
      sinfo_lines=$(cat -- "$candidate")
    elif [[ -r "20251105.sinfo" ]]; then
      sinfo_lines=$(cat -- "20251105.sinfo")
    else
      sinfo_lines=$(sinfo -o "%16P %14C  %6t %25N %5D %15G  %10m %11l %30f" || true)
    fi
  else
    sinfo_lines=$(sinfo -o "%16P %14C  %6t %25N %5D %15G  %10m %11l %30f" || true)
  fi

  # Process sinfo (skip header)
  local first=1
  while IFS= read -r line; do
    if (( first )); then first=0; continue; fi
    [[ -z "$line" ]] && continue
    # shellcheck disable=SC2206
    local arr=( $line )
    local part="${arr[0]//\*/}"      # partition (GPU name, strip *)
    local cfield="${arr[1]}"    # CPUS(A/I/O/T)
    local state="${arr[2]}"     # state
    local nodelist="${arr[3]}"  # n[...]
    local nodes="${arr[4]}"     # number of nodes
    local gres="${arr[5]}"      # gpu:MODEL:COUNT
    local feature="${arr[8]:-}" # AVAIL_FEATURES (may be missing)

    # Skip cpu* partitions and down/drain/drng/unk states
    if [[ "$part" == cpu* ]]; then continue; fi
    if [[ "$state" == down* || "$state" == drain* || "$state" == drng* || "$state" == unk* ]]; then continue; fi

    # Per-node GPU count
    local per_node_gpu
    per_node_gpu=$(parse_gpu_count_from_gres_feature "$gres" "$feature")
    # Total CPUs for this partition line
    local total_cpus
    total_cpus=$(awk -F/ '{print $4}' <<< "$cfield")
    # CPU per node (integer)
    local cpu_per_node=$(( total_cpus / nodes ))

    # Accumulate cluster totals
    CLUSTER_GPU_TOTAL["$part"]=$(( ${CLUSTER_GPU_TOTAL["$part"]:-0} + (nodes * per_node_gpu) ))
    CLUSTER_CPU_TOTAL["$part"]=$(( ${CLUSTER_CPU_TOTAL["$part"]:-0} + total_cpus ))

    # Expand nodes and populate node info
    local expanded
    expanded=$(expand_nodelist "$nodelist") || true
    for n in $expanded; do
      if [[ -z "${NODE_GPU_TYPE[$n]:-}" ]]; then
        NODE_GPU_TYPE["$n"]="$part"
        NODE_GPU_PER_NODE["$n"]=$per_node_gpu
        NODE_CPU_PER_NODE["$n"]=$cpu_per_node
        NODE_STATE["$n"]="$state"
      fi
    done

    # Track draining nodes
    if [[ "$state" == drng* ]]; then
      for n in $expanded; do DRNG_NODE_SET["$n"]=1; done
    fi
  done <<< "$sinfo_lines"
}

read_squeue() {
  local squeue_lines
  if [[ -n "$SQUEUE_FILE" ]]; then
    squeue_lines=$(cat -- "$SQUEUE_FILE")
  else
    # Removed group column (%g) to match sample.squeue layout
    squeue_lines=$(squeue -o "%6i %12j  %9T %12u %15P %4D %20R %4C %40b %8m %11l %11L" || true)
  fi
  # squeue -o   "%6i %12j  %9T %12u %15P %4D %20R %4C %40b %8m %11l %11L"

  # Skip header; parse from right to be robust
  local first=1
  while IFS= read -r line; do
    if (( first )); then first=0; continue; fi
    [[ -z "$line" ]] && continue
    # shellcheck disable=SC2206
    local arr=( $line )
    local n=${#arr[@]}
    # Need at least 12-13 tokens based on default squeue
    if (( n < 12 )); then continue; fi
    # With %g removed, shift user index one to the left
    local user="${arr[n-9]}"
    local part="${arr[n-8]}"
    local nodelist="${arr[n-6]}"
    local cpus="${arr[n-5]}"
    local tres="${arr[n-4]}"

    # Skip non-node allocations and draining nodes
    if [[ "${nodelist:0:1}" != "n" ]]; then continue; fi

    # Expand node list
    local expanded
    expanded=$(expand_nodelist "$nodelist") || true
    [[ -z "$expanded" ]] && continue
    local nodes_count=0
    for _n in $expanded; do nodes_count=$((nodes_count+1)); done

    # GPU and CPU per node for this job
    local gcount
    gcount=$(parse_gpu_count_from_tres "$tres")
    local gpu_per_node=$(( gcount / nodes_count ))
    local cpu_per_node=$(( cpus / nodes_count ))

    # Accumulate per device
    DEV_USED_GPU["$part"]=$(( ${DEV_USED_GPU["$part"]:-0} + gpu_per_node ))
    DEV_USED_CPU["$part"]=$(( ${DEV_USED_CPU["$part"]:-0} + cpu_per_node ))

    # Accumulate per node and per user
    for n in $expanded; do
      # Skip draining nodes
      if [[ -n "${DRNG_NODE_SET[$n]:-}" ]]; then continue; fi
      NODE_USED_GPU["$n"]=$(( ${NODE_USED_GPU["$n"]:-0} + gpu_per_node ))
      NODE_USED_CPU["$n"]=$(( ${NODE_USED_CPU["$n"]:-0} + cpu_per_node ))
      if (( ALL )); then
        local key="$n|$user"
        NODE_USER_GPU["$key"]=$(( ${NODE_USER_GPU["$key"]:-0} + gpu_per_node ))
        NODE_USER_CPU["$key"]=$(( ${NODE_USER_CPU["$key"]:-0} + cpu_per_node ))
      fi
    done
  done <<< "$squeue_lines"
}

print_gpu_table() {
  printf "%b%-15s %-15s %-15s%b\n" "$HEADER" "GPU" "REMAIN" "CPU_REMAIN" "$ENDC"
  printf -- '---------------------------------------------\n'
  for part in "${!CLUSTER_GPU_TOTAL[@]}"; do
    local total_g=${CLUSTER_GPU_TOTAL[$part]}
    local total_c=${CLUSTER_CPU_TOTAL[$part]}
    local used_g=${DEV_USED_GPU[$part]:-0}
    local used_c=${DEV_USED_CPU[$part]:-0}
    local rem_g=$(( total_g - used_g ))
    local rem_c=$(( total_c - used_c ))
    local color="$OKGREEN"
    if (( rem_g == 0 )); then color="$FAIL"; fi
    printf "%b%-15s %3s/%-13s %3s/%-13s%b\n" "$color" "$part" "$rem_g" "$total_g" "$rem_c" "$total_c" "$ENDC"
  done
  echo
}

print_node_table() {
  if (( ALL )); then
    printf "%b%-15s %-15s %-15s %-15s %-45s%b\n" "$HEADER" "NODE" "GPU" "REMAIN" "CPU_REMAIN" "USERS(G, C)" "$ENDC"
    printf -- '----------------------------------------------------------------------------------------------------\n'
  else
    printf "%b%-15s %-15s %-15s %-15s%b\n" "$HEADER" "NODE" "GPU" "REMAIN" "CPU_REMAIN" "$ENDC"
    printf -- '------------------------------------------------------------\n'
  fi

  # Sort node names numerically by suffix (n<number>)
  local tmp_list=""
  for n in "${!NODE_GPU_TYPE[@]}"; do
    local num=${n#n}
    tmp_list+="$n $num\n"
  done
  local sorted_nodes
  sorted_nodes=$(printf "%b" "$tmp_list" | sort -k2,2n | awk '{print $1}')

  while read -r n; do
    [[ -z "$n" ]] && continue
    local part="${NODE_GPU_TYPE[$n]}"
    local total_g=${NODE_GPU_PER_NODE[$n]:-0}
    local total_c=${NODE_CPU_PER_NODE[$n]:-0}
    local used_g=${NODE_USED_GPU[$n]:-0}
    local used_c=${NODE_USED_CPU[$n]:-0}
    local rem_g=$(( total_g - used_g ))
    local rem_c=$(( total_c - used_c ))

    if (( ALL == 0 )) && (( rem_g == 0 )); then
      continue
    fi

    local color="$OKGREEN"
    if (( rem_g == 0 )); then
      color="$FAIL"
    elif (( ALL )) && (( total_g > 0 )) && (( rem_g == total_g )); then
      # Full GPUs available (e.g., 8/8 or 4/4) highlighted in sky-blue only with -a
      color="$SKYBLUE"
    elif (( rem_c == 0 )); then
      color="$WARNING"
    fi

    if (( ALL )); then
      # Build USERS summary
      local lines=""
      for key in "${!NODE_USER_GPU[@]}"; do
        if [[ "$key" == "$n|"* ]]; then
          local user=${key#${n}|}
          local gcnt=${NODE_USER_GPU[$key]}
          local ccnt=${NODE_USER_CPU[$key]:-0}
          lines+="$gcnt $user $ccnt\n"
        fi
      done
      local summary="-"
      if [[ -n "$lines" ]]; then
        summary=$(printf "%b" "$lines" | sort -k1,1nr -k2,2 | awk '{printf "%s(%s, %s), ", $2, $1, $3}' | sed 's/, $//')
      fi
      printf "%b%-15s %-15s %3s/%-13s %3s/%-13s %-45s%b\n" \
        "$color" "$n" "$part" "$rem_g" "$total_g" "$rem_c" "$total_c" "$summary" "$ENDC"
    else
      printf "%b%-15s %-15s %3s/%-13s %3s/%-13s%b\n" \
        "$color" "$n" "$part" "$rem_g" "$total_g" "$rem_c" "$total_c" "$ENDC"
    fi
  done <<< "$sorted_nodes"
  echo
}

read_sinfo
read_squeue
print_gpu_table
print_node_table
