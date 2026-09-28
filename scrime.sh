#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

# Show per-user GPU usage (running) and queued GPU requests (pending)
# Parsed similarly to sremain.sh for consistency.

# Colors
HEADER="\033[95m"
OKGREEN="\033[92m"
WARNING="\033[93m"
FAIL="\033[91m"
DIM="\033[2m"
ENDC="\033[0m"

SQUEUE_FILE=""
THRESHOLD=10    # percent to flag as "criminal"
ASCII=0         # draw with ASCII only
BAR_WIDTH=24    # width of the usage bar when output is not a terminal
BAR_MIN=8       # bar width limits when fitting to the terminal
BAR_MAX=50
BAR_COL=5       # index of the usage bar among the table's columns

usage() {
  cat <<EOF
Usage: 
  $(basename "$0") [-f|--file PATH] [-t|--threshold PCT] [--ascii]

Options:
  -f, --file PATH    Read squeue output from a file (offline mode)
  -t, --threshold N  Percent of total running GPUs to flag (default: 10)
      --ascii        Draw with ASCII only (default: Unicode on UTF-8 locales)
  -h, --help         Show this help

Notes:
  - Uses the same squeue format as sremain.sh and parses columns from right.
  - GPU count is derived from the TRES field (e.g., gres/gpu:MODEL:4 or gres/gpu:1).
  - The usage bar shows running GPUs as solid blocks and queued ones as light
    shade, scaled to the top user; the dotted line marks the threshold.
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
    --ascii) ASCII=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# Terminal width to fit the table into: $COLUMNS if exported (watch does this),
# else the tty's width. 0 means no limit (output is piped or redirected).
TERM_COLS=0
if [[ "${COLUMNS:-}" =~ ^[0-9]+$ ]] && (( COLUMNS > 0 )); then
  TERM_COLS=$COLUMNS
elif [[ -t 1 ]]; then
  TERM_COLS=$(tput cols 2>/dev/null || true)
  [[ "$TERM_COLS" =~ ^[0-9]+$ ]] || TERM_COLS=0
fi

# Glyphs: Unicode blocks when the locale is UTF-8, else plain ASCII.
# G_EIGHTHS draws partial bar cells; empty means whole cells only.
if (( ! ASCII )) && [[ "$(locale charmap 2>/dev/null)" == UTF-8 ]]; then
  G_RULE="─"; G_RUN="█"; G_QUEUE="░"; G_MARK="┆"; G_NONE="·"; G_SEP=" · "
  G_EIGHTHS=("" "▏" "▎" "▍" "▌" "▋" "▊" "▉")
else
  G_RULE="-"; G_RUN="#"; G_QUEUE="."; G_MARK="|"; G_NONE="-"; G_SEP=" | "
  G_EIGHTHS=()
fi

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

# Length of the longest argument
max_len() {
  local s m=0
  for s in "$@"; do
    if (( ${#s} > m )); then m=${#s}; fi
  done
  echo "$m"
}

# Total width of the current layout; columns of width 0 are hidden
layout_total() {
  local w cols=0
  LAYOUT_TOTAL=0
  for w in "${LAYOUT_W[@]}"; do
    if (( w == 0 )); then continue; fi
    LAYOUT_TOTAL=$(( LAYOUT_TOTAL + w )); cols=$(( cols + 1 ))
  done
  LAYOUT_TOTAL=$(( LAYOUT_TOTAL + (cols - 1) * LAYOUT_GAP ))
}

# Give the usage bar the width left over in the current layout, up to BAR_MAX,
# or hide it if less than BAR_MIN is left. Sets BAR_WIDTH.
fit_bar() {
  LAYOUT_W[BAR_COL]=0
  layout_total
  if (( TERM_COLS > 0 )); then
    BAR_WIDTH=$(( TERM_COLS - LAYOUT_TOTAL - LAYOUT_GAP ))
    if (( BAR_WIDTH > BAR_MAX )); then BAR_WIDTH=$BAR_MAX; fi
    if (( BAR_WIDTH < BAR_MIN )); then BAR_WIDTH=0; fi
  fi
  LAYOUT_W[BAR_COL]=$BAR_WIDTH
  layout_total
}

# Print a row with the current layout. Args: each column's alignment as a
# string of l/r, then one cell per column. Cells may contain color codes;
# padding goes by their visible width.
print_row() {
  local align=$1; shift
  local -a cells=("$@")
  local n=$# i c plain pad line="" sep=""
  printf -v sep '%*s' "$LAYOUT_GAP" ''
  for (( i=0; i<n; i++ )); do
    if (( LAYOUT_W[i] == 0 )); then continue; fi
    c=${cells[i]}
    plain=${c//\\033\[*([0-9;])m/}
    pad=$(( LAYOUT_W[i] - ${#plain} ))
    if (( pad < 0 )); then pad=0; fi
    printf -v pad '%*s' "$pad" ''
    if [[ "${align:i:1}" == r ]]; then c=$pad$c; else c=$c$pad; fi
    line+="${line:+$sep}$c"
  done
  printf '%b\n' "${line%%+( )}"
}

# Print the title and stats on one line if they fit, otherwise the title
# alone and the stats packed onto as few lines as fit TERM_COLS
print_summary() {
  local title=$1; shift
  local item line=""
  for item in "$@"; do line+="$G_SEP$item"; done
  if (( TERM_COLS == 0 || ${#title} + ${#line} <= TERM_COLS )); then
    printf '%b%s%b%s\n' "$HEADER" "$title" "$ENDC" "$line"
    return
  fi
  printf '%b%s%b\n' "$HEADER" "$title" "$ENDC"
  line=""
  for item in "$@"; do
    if [[ -n "$line" ]] && (( ${#line} + ${#G_SEP} + ${#item} > TERM_COLS )); then
      printf '%s\n' "$line"
      line=""
    fi
    line+="${line:+$G_SEP}$item"
  done
  printf '%s\n' "$line"
}

# Build one user's usage bar into BAR: running GPUs as solid blocks, then
# queued GPUs as light shade up to where running + queued would reach. SCALE
# GPUs (x100) fill BAR_WIDTH cells. The limit marker sits in cell MARK when
# the bar is shorter; for a user over the limit, blocks from MARK on are red.
make_bar() {
  local run=$1 queued=$2 over=$3
  local w=$BAR_WIDTH e runs rc qc=0 fill s
  e=$(( run * 100 * w * 8 / SCALE ))   # running GPUs in eighths of a cell
  if (( ${#G_EIGHTHS[@]} == 0 )); then e=$(( (e + 4) / 8 * 8 )); fi
  if (( run > 0 && e == 0 )); then
    if (( ${#G_EIGHTHS[@]} )); then e=1; else e=8; fi
  fi
  printf -v runs '%*s' $(( e / 8 )) ''
  runs=${runs// /$G_RUN}
  if (( e % 8 )); then runs+=${G_EIGHTHS[e % 8]}; fi
  rc=${#runs}

  if (( queued > 0 )); then
    qc=$(( ((run + queued) * 100 * w * 2 + SCALE) / (2 * SCALE) - rc ))
    if (( qc < 1 )); then qc=1; fi
    if (( qc > w - rc )); then qc=$(( w - rc )); fi
  fi

  s=$runs
  if (( over && rc > MARK )); then s="${runs:0:MARK}$FAIL${runs:MARK}$ENDC"; fi
  if (( qc > 0 )); then
    printf -v fill '%*s' "$qc" ''
    s+="$WARNING${fill// /$G_QUEUE}$ENDC"
  fi
  if (( rc + qc <= MARK )); then
    printf -v fill '%*s' $(( MARK - rc - qc )) ''
    s+="$fill$DIM$G_MARK$ENDC"
  fi
  BAR=$s
}

print_report() {
  if (( TOTAL_RUNNING == 0 )); then
    printf "%bNo running GPU jobs found.%b\n" "$WARNING" "$ENDC"
    return
  fi

  # Rows: users running GPUs, most first, then users with only queued GPUs
  local running="" pending_only="" total_pending=0 u v
  for u in "${!USER_RUNNING_GPU[@]}"; do
    v=${USER_RUNNING_GPU[$u]}
    if (( v > 0 )); then running+="$v $u\n"; fi
  done
  for u in "${!USER_PENDING_GPU[@]}"; do
    v=${USER_PENDING_GPU[$u]}
    total_pending=$(( total_pending + v ))
    if (( ${USER_RUNNING_GPU[$u]:-0} == 0 && v > 0 )); then pending_only+="$v $u\n"; fi
  done
  local -a users=() vals=() pends=()
  local row
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    vals+=("${row%% *}"); users+=("${row#* }")
  done < <(printf "%b" "$running" | sort -k1,1nr -k2,2)
  local nrun=${#users[@]}
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    vals+=(0); users+=("${row#* }")
  done < <(printf "%b" "$pending_only" | sort -k1,1nr -k2,2)

  # Plain cell text per row, then colored cells when printing
  local -a ranks=() queues=() shares=() notes=() colors=() overs=()
  local i
  for i in "${!users[@]}"; do
    local val=${vals[i]} pending=${USER_PENDING_GPU[${users[i]}]:-0}
    local over=0 note="" color="$OKGREEN" rank=$G_NONE share=$G_NONE queue=$G_NONE
    if (( val * 100 >= THRESHOLD * TOTAL_RUNNING )); then over=1; fi
    if (( i < nrun )); then
      rank=$(( i + 1 ))
      local tenths=$(( (val * 2000 + TOTAL_RUNNING) / (2 * TOTAL_RUNNING) ))
      share="$(( tenths / 10 )).$(( tenths % 10 ))%"
    fi
    if (( pending > 0 )); then queue="+$pending"; fi

    if (( over )); then
      color="$FAIL"; note="${FAIL}CRIMINAL${ENDC}"
    elif (( pending > 0 )); then
      color="$WARNING"
    fi
    if (( pending > 50 )); then note+="${note:+$G_SEP}${WARNING}WTF${ENDC}"; fi

    ranks+=("$rank"); queues+=("$queue"); shares+=("$share"); notes+=("$note")
    colors+=("$color"); overs+=("$over")
  done

  # Fit the table to the terminal: text columns take their content's width
  # and the usage bar gets what is left (hidden if too narrow)
  local rank_w
  rank_w=$(max_len "#" "${ranks[@]}")
  if (( rank_w < 3 )); then rank_w=3; fi
  local plain_notes=("${notes[@]//\\033\[*([0-9;])m/}")
  LAYOUT_GAP=2
  LAYOUT_W=("$rank_w" "$(max_len user "${users[@]}")" "$(max_len gpus "${vals[@]}")" \
    "$(max_len queue "${queues[@]}")" "$(max_len share "${shares[@]}")" 0 \
    "$(max_len "${plain_notes[@]}")")
  fit_bar

  # Bars are scaled to the top user, or to the limit if nobody reaches it
  SCALE=$(( vals[0] * 100 ))
  if (( THRESHOLD * TOTAL_RUNNING > SCALE )); then SCALE=$(( THRESHOLD * TOTAL_RUNNING )); fi
  MARK=0
  if (( BAR_WIDTH > 0 )); then
    MARK=$(( THRESHOLD * TOTAL_RUNNING * BAR_WIDTH / SCALE ))
    if (( MARK > BAR_WIDTH - 1 )); then MARK=$(( BAR_WIDTH - 1 )); fi
  fi

  # Bar legend: the longest variant that fits the bar
  local legend="usage" variant
  for variant in "$G_RUN run  $G_QUEUE queued  $G_MARK limit" \
    "$G_RUN run $G_QUEUE queue $G_MARK limit" "$G_RUN run $G_QUEUE queue"; do
    if (( ${#variant} <= BAR_WIDTH )); then legend=$variant; break; fi
  done
  legend=${legend/"$G_RUN"/$ENDC$G_RUN$HEADER}
  legend=${legend/"$G_QUEUE"/$ENDC$WARNING$G_QUEUE$ENDC$HEADER}
  legend=${legend/"$G_MARK"/$ENDC$DIM$G_MARK$ENDC$HEADER}

  local rule_w=$LAYOUT_TOTAL
  if (( TERM_COLS > 0 && rule_w > TERM_COLS )); then rule_w=$TERM_COLS; fi
  local rule
  printf -v rule '%*s' "$rule_w" ''
  rule=${rule// /$G_RULE}

  print_summary "GPU usage" "$TOTAL_RUNNING running" "$total_pending queued" \
    "$nrun users" "limit $THRESHOLD%"
  printf '%b%s%b\n' "$DIM" "$rule" "$ENDC"
  local h=$HEADER e=$ENDC
  print_row rlrrrll "$h#$e" "${h}user$e" "${h}gpus$e" "${h}queue$e" "${h}share$e" "$h$legend$e" ""

  local d=$DIM
  for i in "${!users[@]}"; do
    local rank=${ranks[i]} gpus=${vals[i]} queue=${queues[i]} share=${shares[i]}
    if (( i == nrun )); then
      printf '%*s%b%s%b\n' $(( rank_w + LAYOUT_GAP )) '' "$d" "pending only (no running GPUs)" "$e"
    fi
    if [[ "$rank" == "$G_NONE" ]]; then rank="$d$rank$e"; fi
    if (( gpus == 0 )); then gpus="$d$G_NONE$e"; fi
    if [[ "$queue" == "$G_NONE" ]]; then queue="$d$queue$e"; fi
    if [[ "$share" == "$G_NONE" ]]; then share="$d$share$e"; fi
    BAR=""
    if (( BAR_WIDTH > 0 )); then
      make_bar "${vals[i]}" "${USER_PENDING_GPU[${users[i]}]:-0}" "${overs[i]}"
    fi
    print_row rlrrrll "$rank" "${colors[i]}${users[i]}$e" "$gpus" "$queue" "$share" \
      "$BAR" "${notes[i]}"
  done
}

read_and_aggregate
print_report
