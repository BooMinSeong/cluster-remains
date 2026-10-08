# Shared by sremain.sh, scrime.sh and sme.sh so they read Slurm the same way and
# print in the same style:
#   - a bold title line with the totals, then a table
#   - one row per thing, every value in its own aligned column
#   - numbers right-aligned, "·" for nothing, free/total with the "/" lined up
#   - each color means one thing: green = free now, yellow = queued,
#     red = over the limit, bold = group heading, dim = nothing there or
#     secondary
# Source it first, then call init_style once options are parsed.

shopt -s extglob

SQUEUE_FILE=""    # read jobs from this file instead of squeue
ASCII=0           # draw with ASCII only

SQUEUE_FMT="%T %u %P %D %C %b %R"
SINFO_FMT="%P %C %t %N %D %G %m %l %f"
SINFO_SNAPSHOT="20251105.sinfo"   # sinfo used with -f, if found

ESC=$'\e'
ITEM=$'\x1f'      # separates the items of a table's last column
NOTE=$'\x1e'      # marks a note row in a table
GAP=2             # spaces between table columns
MIN_LAST=20       # never wrap the last column narrower than this

die() { echo "$(basename "$0"): $*" >&2; exit 1; }

# Terminal width to fit output into: $COLUMNS if exported (watch does this),
# else the tty's width. 0 means no limit (output is piped or redirected).
TERM_COLS=0
if [[ "${COLUMNS:-}" =~ ^[0-9]+$ ]] && (( COLUMNS > 0 )); then
  TERM_COLS=$COLUMNS
elif [[ -t 1 ]]; then
  TERM_COLS=$(tput cols 2>/dev/null || true)
  [[ "$TERM_COLS" =~ ^[0-9]+$ ]] || TERM_COLS=0
fi

# Colors (none if NO_COLOR is set) and glyphs (ASCII unless the locale is
# UTF-8 and --ascii wasn't given)
init_style() {
  if [[ -n "${NO_COLOR:-}" ]]; then
    C_BOLD="" C_DIM="" C_GREEN="" C_YELLOW="" C_RED="" C_END=""
  else
    C_BOLD=$'\e[1m' C_DIM=$'\e[2m' C_GREEN=$'\e[92m' C_YELLOW=$'\e[93m'
    C_RED=$'\e[91m' C_END=$'\e[0m'
  fi
  if (( ! ASCII )) && [[ "$(locale charmap 2>/dev/null)" == UTF-8 ]]; then
    G_RULE="─" G_NONE="·" G_SEP=" · "
  else
    G_RULE="-" G_NONE="-" G_SEP=" | "
  fi
}

# Add $3 to entry $2 of the associative array named $1
add() {
  local -n _arr=$1
  _arr[$2]=$(( ${_arr[$2]:-0} + $3 ))
}

# --- Slurm state -------------------------------------------------------------

# Expand a node list like n[1-3,7] into EXPANDED=(n1 n2 n3 n7); empty if
# it isn't a node list
expand_nodes() {
  EXPANDED=()
  local p i
  if [[ $1 =~ ^n[0-9]+$ ]]; then EXPANDED=("$1"); return; fi
  [[ $1 =~ ^n\[([0-9,-]+)\]$ ]] || return 0
  for p in ${BASH_REMATCH[1]//,/ }; do
    if [[ $p == *-* ]]; then
      for (( i=${p%-*}; i<=${p#*-}; i++ )); do EXPANDED+=("n$i"); done
    else
      EXPANDED+=("n$p")
    fi
  done
}

# GPUs per node from sinfo's GRES (gpu:MODEL:8), else from a feature like
# ...-8GPU (GRES may be cut off in saved snapshots); 0 if neither says
gpus_per_node() {
  local g=${1%%,*}
  g=${g%%(*}
  if [[ $g == gpu* && ${g##*:} =~ ^[0-9]+$ ]]; then
    REPLY=${g##*:}
  elif [[ $2 =~ ([0-9]+)GPU ]]; then
    REPLY=${BASH_REMATCH[1]}
  else
    REPLY=0
  fi
}

# GPU nodes that can take jobs, from sinfo. Partitions are GPU types; cpu*
# partitions and nodes that are down or draining are left out.
declare -A NODE_TYPE=()   # node -> GPU type
declare -A NODE_GPUS=()   # node -> GPUs
declare -A NODE_CPUS=()   # node -> CPUs
NODES=()                  # by number
TYPES=()                  # in sinfo order
NODES_OFF=0               # GPU nodes down or draining

load_nodes() {
  local lines="" part cpus state list count gres feat n
  local -A seen=() off=()
  if [[ -n $SQUEUE_FILE ]]; then
    local f
    for f in "$(dirname -- "$SQUEUE_FILE")/$SINFO_SNAPSHOT" "$SINFO_SNAPSHOT"; do
      if [[ -r $f ]]; then lines=$(<"$f"); break; fi
    done
  fi
  if [[ -z $lines ]]; then lines=$(sinfo -o "$SINFO_FMT" || true); fi

  while read -r part cpus state list count gres _ _ feat _; do
    part=${part%\*}
    if [[ -z $part || $part == PARTITION || $part == cpu* ]]; then continue; fi
    expand_nodes "$list"
    case $state in
      down*|drain*|drng*|fail*|unk*|inval*|maint*)
        for n in "${EXPANDED[@]}"; do off[$n]=1; done
        continue ;;
    esac
    gpus_per_node "$gres" "${feat:-}"
    if (( REPLY == 0 )); then continue; fi
    if [[ -z ${seen[$part]:-} ]]; then seen[$part]=1; TYPES+=("$part"); fi
    for n in "${EXPANDED[@]}"; do
      if [[ -n ${NODE_TYPE[$n]:-} ]]; then continue; fi
      NODE_TYPE[$n]=$part
      NODE_GPUS[$n]=$REPLY
      NODE_CPUS[$n]=$(( ${cpus##*/} / count ))
    done
  done <<< "$lines"

  if (( ${#NODE_TYPE[@]} )); then
    mapfile -t NODES < <(printf '%s\n' "${!NODE_TYPE[@]}" | sort -V)
  fi
  for n in "${!off[@]}"; do
    if [[ -z ${NODE_TYPE[$n]:-} ]]; then NODES_OFF=$(( NODES_OFF + 1 )); fi
  done
}

# Print one line per job:  KIND USER PARTITION NODES CPUS GPUS_PER_NODE NODELIST
# KIND is R for jobs holding nodes (NODELIST names them) and P for queued
# ones (NODELIST is -). PARTITION is the first one the job may run in.
# $SQUEUE_FILE may hold our format or the older one of sample.squeue
# (JOBID NAME STATE USER ...); the header tells which.
job_lines() {
  if [[ -n $SQUEUE_FILE ]]; then
    cat -- "$SQUEUE_FILE"
  else
    squeue -o "$SQUEUE_FMT" || true
  fi | awk '
    NR == 1 { old = ($1 == "JOBID"); next }
    old {
      # NAME may contain spaces, so count fields from the right
      if (NF < 12) next
      user = $(NF-8); part = $(NF-7); nodes = $(NF-6)
      list = $(NF-5); cpus = $(NF-4); tres = $(NF-3)
    }
    !old {
      if (NF < 7) next
      user = $2; part = $3; nodes = $4; cpus = $5; tres = $6; list = $7
    }
    {
      sub(/,.*/, "", part)
      gpus = 0
      n = split(tres, t, ",")
      for (i = 1; i <= n; i++) {
        if (t[i] !~ /gpu/) continue
        gsub(/=/, ":", t[i])
        m = split(t[i], f, ":")
        gpus = 1
        for (j = m; j >= 1; j--) if (f[j] ~ /^[0-9]+$/) { gpus = f[j]; break }
        break
      }
      held = (list ~ /^n[0-9[]/)
      print (held ? "R" : "P"), user, part, nodes, cpus, gpus, (held ? list : "-")
    }'
}

# --- output ------------------------------------------------------------------

# Visible width of $1, not counting color codes, into REPLY
vis_len() {
  local p=${1//"$ESC"\[*([0-9;])m/}
  REPLY=${#p}
}

# Print the title in bold followed by the stats on one line if they fit,
# otherwise the title alone and the stats packed onto as few lines as fit
print_title() {
  local title=$1; shift
  local item line=""
  for item in "$@"; do line+="$G_SEP$item"; done
  vis_len "$line"
  if (( TERM_COLS == 0 || ${#title} + REPLY <= TERM_COLS )); then
    printf '%s%s%s%s\n' "$C_BOLD" "$title" "$C_END" "$line"
    return
  fi
  printf '%s%s%s\n' "$C_BOLD" "$title" "$C_END"
  line=""
  for item in "$@"; do
    vis_len "$line$G_SEP$item"
    if [[ -n $line ]] && (( REPLY > TERM_COLS )); then
      printf '%s\n' "$line"
      line=""
    fi
    line+="${line:+$G_SEP}$item"
  done
  printf '%s\n' "$line"
}

# Format free/total cells into FRACS, all the same width with the slashes
# lined up. Args: the names of an array of free counts and one of totals.
fracs() {
  local -n _free=$1 _total=$2
  local fw=0 tw=0 i
  for i in "${!_free[@]}"; do
    if (( ${#_free[i]} > fw )); then fw=${#_free[i]}; fi
    if (( ${#_total[i]} > tw )); then tw=${#_total[i]}; fi
  done
  FRACS=()
  for i in "${!_free[@]}"; do
    printf -v REPLY '%*s/%-*s' "$fw" "${_free[i]}" "$tw" "${_total[i]}"
    FRACS+=("$REPLY")
  done
}

# Color the part of a free/total cell before the slash
color_free() {
  REPLY="$2${1%%/*}$C_END/${1#*/}"
}

# Tables: tbl_new ALIGN HEADER..., then tbl_row CELL... per row (one cell per
# column) or tbl_note COLUMN TEXT for a line of text starting at a column,
# then tbl_print. ALIGN has an l or r per column. Cells may contain color
# codes. The last cell is a list of items joined by $ITEM that wraps
# between items, indented under its column, when the row is too wide for
# the terminal. Columns that are empty in every row, header included, are
# left out.
tbl_new() {
  TBL_ALIGN=$1; shift
  TBL_N=$#
  TBL_HEAD=("$@")
  TBL_ROWS=()
}

tbl_row() { TBL_ROWS+=("$@"); }

tbl_note() {
  local -a row=("$NOTE$1" "$2")
  while (( ${#row[@]} < TBL_N )); do row+=(""); done
  TBL_ROWS+=("${row[@]}")
}

tbl_print() {
  local n=$TBL_N i r last
  local nrows=$(( ${#TBL_ROWS[@]} / n ))
  TBL_W=()
  for (( i=0; i<n; i++ )); do vis_len "${TBL_HEAD[i]}"; TBL_W[i]=$REPLY; done
  for (( r=0; r<nrows; r++ )); do
    if [[ ${TBL_ROWS[r*n]} == "$NOTE"* ]]; then continue; fi
    for (( i=0; i<n; i++ )); do
      last=${TBL_ROWS[r*n+i]}
      if (( i == n - 1 )); then last=${last//$ITEM/  }; fi
      vis_len "$last"
      if (( REPLY > TBL_W[i] )); then TBL_W[i]=$REPLY; fi
    done
  done

  # Wrap the last column if the table is wider than the terminal
  TBL_PREFIX=0
  for (( i=0; i<n-1; i++ )); do
    if (( TBL_W[i] )); then TBL_PREFIX=$(( TBL_PREFIX + TBL_W[i] + GAP )); fi
  done
  local width=$(( TBL_PREFIX + TBL_W[n-1] ))
  if (( TBL_W[n-1] == 0 )); then width=$(( width - GAP )); fi
  TBL_LAST=0
  if (( TERM_COLS > 0 && width > TERM_COLS )); then
    TBL_LAST=$(( TERM_COLS - TBL_PREFIX ))
    if (( TBL_LAST < MIN_LAST )); then TBL_LAST=$MIN_LAST; fi
    width=$(( TBL_PREFIX + TBL_LAST ))
    if (( width > TERM_COLS )); then width=$TERM_COLS; fi
  fi

  local -a head=()
  for (( i=0; i<n; i++ )); do
    head+=("${TBL_HEAD[i]:+$C_DIM${TBL_HEAD[i]}$C_END}")
  done
  tbl_line "${head[@]}"
  local rule
  printf -v rule '%*s' "$width" ''
  printf '%s%s%s\n' "$C_DIM" "${rule// /$G_RULE}" "$C_END"
  for (( r=0; r<nrows; r++ )); do tbl_line "${TBL_ROWS[@]:r*n:n}"; done
}

# Print one row with the layout tbl_print chose
tbl_line() {
  local -a cells=("$@")
  local n=$TBL_N i c pad line="" indent
  if [[ ${cells[0]} == "$NOTE"* ]]; then
    local col=${cells[0]#"$NOTE"} at=0
    for (( i=0; i<col; i++ )); do
      if (( TBL_W[i] )); then at=$(( at + TBL_W[i] + GAP )); fi
    done
    printf '%*s%s\n' "$at" '' "${cells[1]}"
    return
  fi
  for (( i=0; i<n-1; i++ )); do
    if (( TBL_W[i] == 0 )); then continue; fi
    c=${cells[i]}
    vis_len "$c"
    printf -v pad '%*s' $(( TBL_W[i] - REPLY + GAP )) ''
    if [[ ${TBL_ALIGN:i:1} == r ]]; then
      line+="${pad:GAP}$c${pad:0:GAP}"
    else
      line+=$c$pad
    fi
  done

  local -a items=()
  local item cur="" curw=0
  printf -v indent '%*s' "$TBL_PREFIX" ''
  if [[ -n ${cells[n-1]} ]]; then IFS=$ITEM read -ra items <<< "${cells[n-1]}"; fi
  for item in "${items[@]}"; do
    vis_len "$item"
    if [[ -n $cur ]] && (( TBL_LAST > 0 && curw + GAP + REPLY > TBL_LAST )); then
      printf '%s\n' "$line$cur"
      line=$indent cur="" curw=0
    fi
    if [[ -n $cur ]]; then cur+="  "; curw=$(( curw + GAP )); fi
    cur+=$item
    curw=$(( curw + REPLY ))
  done
  line+=$cur
  printf '%s\n' "${line%%+( )}"
}
