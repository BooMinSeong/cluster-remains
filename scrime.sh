#!/usr/bin/env bash
set -euo pipefail

# Show per-user GPU usage (running) and queued GPU requests (pending)
# Parsed similarly to sremain.sh for consistency.

# Colors
HEADER="\033[95m"
OKGREEN="\033[92m"
WARNING="\033[93m"
FAIL="\033[91m"
ENDC="\033[0m"

SQUEUE_FILE=""
THRESHOLD=10    # percent to flag as "criminal"
BAR_WIDTH=24    # width of the usage bar

usage() {
  cat <<EOF
Usage: 
  $(basename "$0") [-f|--file PATH] [-t|--threshold PCT]

Options:
  -f, --file PATH    Read squeue output from a file (offline mode)
  -t, --threshold N  Percent of total running GPUs to flag (default: 10)
  -h, --help         Show this help

Notes:
  - Uses the same squeue format as sremain.sh and parses columns from right.
  - GPU count is derived from the TRES field (e.g., gres/gpu:MODEL:4 or gres/gpu:1).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)
      [[ $# -ge 2 ]] || { echo "-f|--file requires a path" >&2; exit 1; }
      SQUEUE_FILE="$2"; shift 2 ;;
    -t|--threshold)
      [[ $# -ge 2 ]] || { echo "-t|--threshold requires a number" >&2; exit 1; }
      THRESHOLD="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

trim() { sed 's/^\s\+//; s/\s\+$//' ; }

# Extract numeric GPU count from a TRES token
# Examples:
#   - "gres/gpu:1"            -> 1
#   - "gres/gpu:MODEL:8"      -> 8
#   - "N/A" or missing gpu    -> 0
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
  echo 1
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
    return
  fi
}

declare -A USER_RUNNING_GPU  # user -> running GPU count (integer)
declare -A USER_PENDING_GPU  # user -> queued GPU count (integer)

TOTAL_RUNNING=0

read_and_aggregate() {
  local squeue_lines
  if [[ -n "$SQUEUE_FILE" ]]; then
    squeue_lines=$(cat -- "$SQUEUE_FILE")
  else
    squeue_lines=$(squeue -o "%6i %12j  %9T %12u %15P %4D %20R %4C %40b %8m %11l %11L" || true)
  fi

  local first=1
  while IFS= read -r line; do
    if (( first )); then first=0; continue; fi
    [[ -z "$line" ]] && continue
    # shellcheck disable=SC2206
    local arr=( $line )
    local n=${#arr[@]}
    (( n < 12 )) && continue

    local user="${arr[n-9]}"
    local part="${arr[n-8]}"
    local nodelist="${arr[n-6]}"
    local cpus="${arr[n-5]}"   # not used for now
    local tres="${arr[n-4]}"

    # Ignore CPU-only partitions
    if [[ "$part" == cpu* ]]; then continue; fi

    # Determine state from NodeList(REASON)
    local state="pending"
    if [[ "${nodelist:0:1}" == "n" ]]; then
      state="running"
    fi

    # Expand nodes if running
    local nodes_count=1
    if [[ "$state" == "running" ]]; then
      local expanded
      expanded=$(expand_nodelist "$nodelist") || true
      if [[ -n "$expanded" ]]; then
        nodes_count=0
        local _n
        for _n in $expanded; do nodes_count=$((nodes_count+1)); done
        (( nodes_count == 0 )) && nodes_count=1
      fi
    fi

    local gcount
    gcount=$(parse_gpu_count_from_tres "$tres")
    [[ -z "$gcount" ]] && gcount=0

    # Follow scrime.py logic:
    # - For running with multi-node, divide by node count
    # - For pending, keep as-is (node info unknown)
    local add_run=0
    if [[ "$state" == "running" ]]; then
      add_run=$(( gcount / nodes_count ))
      USER_RUNNING_GPU["$user"]=$(( ${USER_RUNNING_GPU["$user"]:-0} + add_run ))
      TOTAL_RUNNING=$(( TOTAL_RUNNING + add_run ))
    else
      USER_PENDING_GPU["$user"]=$(( ${USER_PENDING_GPU["$user"]:-0} + gcount ))
    fi
  done <<< "$squeue_lines"
}

print_report() {
  # Build sortable list: value user
  local lines=""
  local u
  for u in "${!USER_RUNNING_GPU[@]}"; do
    local v=${USER_RUNNING_GPU[$u]}
    lines+="$v $u\n"
  done

  # Header & summary
  if (( TOTAL_RUNNING == 0 )); then
    printf "%bNo running GPU jobs found.%b\n" "$WARNING" "$ENDC"
  else
    local num_users=${#USER_RUNNING_GPU[@]}
    printf "%bGPU Usage by User%b  | Total running: %d  | Users: %d  | Threshold: %d%%\n" \
      "$HEADER" "$ENDC" "$TOTAL_RUNNING" "$num_users" "$THRESHOLD"
    printf -- '--------------------------------------------------------------------------------\n'
    printf "%-4s %-16s %8s %7s  %-*s  %-8s %s\n" "#" "User" "GPUs" "%" "$BAR_WIDTH" "Usage" "Queued" "Notes"
    printf -- '--------------------------------------------------------------------------------\n'
  fi

  [[ -z "$lines" ]] && return

  local sorted
  sorted=$(printf "%b" "$lines" | sort -k1,1nr -k2,2)
  # Top value for bar scaling
  local TOP=0
  TOP=${sorted%% *}
  local rank=0
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    local val user
    val=${row%% *}
    user=${row#* }
    rank=$((rank+1))

    local pending=${USER_PENDING_GPU[$user]:-0}

    # Percent label
    local pct
    pct=$(awk -v v="$val" -v t="$TOTAL_RUNNING" 'BEGIN{if(t>0) printf "%.2f", (100.0*v)/t; else print "0.00"}')

    # Bar scaled to top user's usage for better contrast
    local filled=0
    if (( TOP > 0 )); then
      filled=$(( (val * BAR_WIDTH) / TOP ))
      (( filled > BAR_WIDTH )) && filled=$BAR_WIDTH
      if (( val > 0 && filled == 0 )); then filled=1; fi
    fi
    local bar
    bar=$(printf '%*s' "$filled" '' | tr ' ' '#')
    local pad=$(( BAR_WIDTH - filled ))
    local padstr
    padstr=$(printf '%*s' "$pad" '')

    # Row color
    local color="$OKGREEN"
    if (( TOTAL_RUNNING > 0 )) && (( val * 100 >= THRESHOLD * TOTAL_RUNNING )); then
      color="$FAIL"
    elif (( pending > 0 )); then
      color="$WARNING"
    fi

    # Flags
    local notes=""
    if [[ "$color" == "$FAIL" ]]; then
      notes="CRIMINAL"
    fi
    local wtf=""
    if (( pending > 50 )); then
      if [[ -n "$notes" ]]; then notes+=" | "; fi
      notes+="WTF"
    fi

    printf "%3d  %b%-16s%b %8d %6s  %-*s  %-8s %s\n" \
      "$rank" "$color" "$user" "$ENDC" "$val" "$pct" "$BAR_WIDTH" "${bar}${padstr}" "$pending" "$notes"
  done <<< "$sorted"

  # Pending-only section
  local pending_only_lines=""
  for u in "${!USER_PENDING_GPU[@]}"; do
    if [[ -z "${USER_RUNNING_GPU[$u]:-}" || ${USER_RUNNING_GPU[$u]:-0} -eq 0 ]]; then
      if (( ${USER_PENDING_GPU[$u]} > 0 )); then
        pending_only_lines+="${USER_PENDING_GPU[$u]} $u\n"
      fi
    fi
  done
  if [[ -n "$pending_only_lines" ]]; then
    echo
    printf "%bPending Only (no running GPUs)%b\n" "$HEADER" "$ENDC"
    printf -- '--------------------------------------------------------------------------------\n'
    printf "%-4s %-16s %8s\n" "#" "User" "Queued"
    printf -- '--------------------------------------------------------------------------------\n'
    local sorted_p
    sorted_p=$(printf "%b" "$pending_only_lines" | sort -k1,1nr -k2,2)
    local r=0
    while IFS= read -r row; do
      [[ -z "$row" ]] && continue
      local val user
      val=${row%% *}
      user=${row#* }
      r=$((r+1))
      local wtf=""
      if (( val > 50 )); then wtf=" WTF"; fi
      printf "%3d  %-16s %8d%s\n" "$r" "$user" "$val" "$wtf"
    done <<< "$sorted_p"
  fi
}

read_and_aggregate
print_report
