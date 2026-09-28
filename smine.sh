#!/usr/bin/env bash
set -euo pipefail

# Show my jobs and my fairshare: each running job with where it runs and the
# time it has left, each queued job with why it waits in plain words, then
# how much of each GPU type I have used and what that costs my priority.

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/common.sh"

TARGET=${USER:-$(id -un)}   # whose jobs and fairshare to show
NAME_MAX=20                 # cut job names longer than this
ID_MAX=18                   # cut job ids (array task lists) longer than this
BAR=20                      # width of a 100% share bar

usage() {
  cat <<EOF
Usage: $(basename "$0") [-u|--user USER] [--ascii]

Show your jobs and your fairshare.

Options:
  -u, --user USER  Show USER instead of you
      --ascii      Draw with ASCII only (default: Unicode on UTF-8 locales)
  -h, --help       Show this help

Queued jobs show why they wait, in plain words, and Slurm's estimated start
if it has one. Fairshare shows the GPU hours you used per GPU type, decayed
by the half-life, times the partition's billing weight. Your priority comes
almost only from fairshare, so the types with the biggest share cost you the
most.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user)
      [[ $# -ge 2 ]] || die "$1 requires a user"
      TARGET="$2"; shift 2 ;;
    --ascii) ASCII=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# --- association: GPU limit, fairshare, usage ---------------------------------

ACCOUNT="" FACTOR="" RANK=0 PEERS=0
GPU_LIMIT="" GPU_USED=0
declare -A USAGE=()   # TRES (cpu, billing, gres/gpu:TYPE) -> decayed minutes

# Read every association once. The target's own record gives its limits and
# usage; the other users of its account give its fairshare rank.
read_assoc() {
  local kind a b c
  while read -r kind a b c; do
    case $kind in
      A) ACCOUNT=$a FACTOR=$b ;;
      L) GPU_LIMIT=$a GPU_USED=$b ;;
      U) USAGE[$a]=$b ;;
      R) RANK=$a PEERS=$b ;;
    esac
  done < <(scontrol show assoc_mgr flags=assoc 2>/dev/null | awk -v me="$TARGET" '
    # "a=N(5),b=64(2)" -> fills lim[] and use[] by key
    function tres(s,   n, t, i, k, v) {
      delete lim; delete use
      n = split(s, t, ",")
      for (i = 1; i <= n; i++) {
        k = t[i]; sub(/=.*/, "", k)
        v = t[i]; sub(/^[^=]*=/, "", v)
        lim[k] = v; sub(/\(.*/, "", lim[k])
        use[k] = v; sub(/^[^(]*\(/, "", use[k]); sub(/\).*/, "", use[k])
      }
    }
    /^ClusterName=/ {
      acct = user = part = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^Account=/)   { acct = substr($i, 9) }
        if ($i ~ /^UserName=/)  { user = substr($i, 10); sub(/\(.*/, "", user) }
        if ($i ~ /^Partition=/) { part = substr($i, 11) }
      }
      mine = (user == me && part == "" && !found)
      if (mine) found = 1
      next
    }
    user == "" || part != "" { next }
    $1 ~ /^SharesRaw/ {
      split(substr($1, index($1, "=") + 1), s, "/")
      fac[acct, user] = s[4]
      if (mine) { my_acct = acct; my_fac = s[4]; print "A", acct, s[4] }
    }
    !mine { next }
    $1 ~ /^GrpTRES=/ {
      tres(substr($1, 9))
      print "L", lim["gres/gpu"], use["gres/gpu"]
    }
    $1 ~ /^GrpTRESMins=/ {
      tres(substr($1, 13))
      for (k in use) if (use[k] > 0) print "U", k, use[k]
    }
    END {
      if (!found) exit
      for (k in fac) {
        split(k, p, SUBSEP)
        if (p[1] != my_acct) continue
        peers++
        if (fac[k] + 0 > my_fac + 0) ahead++
      }
      print "R", ahead + 1, peers
    }')
}

# Billing weight and a display name (the first partition in sinfo order) for
# each GPU TRES, e.g. gres/gpu:rtx3090 -> 22 RTX3090, and the CPU weight
declare -A WEIGHT=() LABEL=()
CPU_WEIGHT=""

read_weights() {
  local -A pweight=() cweight=()
  local line part w
  while read -r line; do
    [[ $line =~ PartitionName=([^ ]+) ]] || continue
    part=${BASH_REMATCH[1]}
    [[ $line =~ TRESBillingWeights=([^ ]+) ]] || continue
    w=${BASH_REMATCH[1]}
    pweight[$part]=$w
    if [[ $w =~ (^|,)CPU=([0-9.]+) ]]; then cweight[$part]=${BASH_REMATCH[2]}; fi
  done < <(scontrol show partition -o 2>/dev/null)

  local gres type key
  while read -r part gres; do
    part=${part%\*}
    if [[ $part == cpu* || -z ${pweight[$part]:-} || $gres != gpu:* ]]; then continue; fi
    type=${gres#gpu:}; type=${type%%:*}
    key="gres/gpu:${type,,}"
    if [[ -n ${LABEL[$key]:-} ]]; then continue; fi
    w=${pweight[$part],,}
    if [[ $w =~ (^|,)${key//\//\\/}=([0-9.]+) ]]; then
      WEIGHT[$key]=${BASH_REMATCH[2]}
    elif [[ $w =~ (^|,)gres/gpu=([0-9.]+) ]]; then
      WEIGHT[$key]=${BASH_REMATCH[2]}
    else
      continue
    fi
    LABEL[$key]=$part
    if [[ -z $CPU_WEIGHT ]]; then CPU_WEIGHT=${cweight[$part]:-}; fi
  done < <(sinfo -h -o "%P %G" 2>/dev/null)
}

# --- jobs ---------------------------------------------------------------------

# Plain words for why a job is queued, into REPLY; REPLY_BAD=1 if it will
# never start on its own
explain_reason() {
  REPLY_BAD=0
  case $1 in
    None) REPLY="not looked at by the scheduler yet" ;;
    Resources) REPLY="waiting for GPUs or CPUs to free up" ;;
    Priority) REPLY="jobs with higher priority are ahead" ;;
    Dependency) REPLY="waiting for the job it depends on" ;;
    DependencyNeverSatisfied)
      REPLY="the job it depends on failed; cancel it" REPLY_BAD=1 ;;
    BeginTime) REPLY="set to start later (--begin)" ;;
    JobArrayTaskLimit) REPLY="array is at its limit of running tasks (%N)" ;;
    JobHeldUser) REPLY="held by you; scontrol release to run" REPLY_BAD=1 ;;
    JobHeldAdmin) REPLY="held by an admin" REPLY_BAD=1 ;;
    "job requeued in held state")
      REPLY="requeued and held; scontrol release to run" REPLY_BAD=1 ;;
    AssocGrpGRES|AssocGrpGpu*) REPLY="your GPU limit is used up" ;;
    AssocGrpCpu*|AssocGrpCPU*) REPLY="your CPU limit is used up" ;;
    AssocGrp*) REPLY="your account limit is used up" ;;
    AssocMax*) REPLY="over a per-job limit of your account" REPLY_BAD=1 ;;
    QOSMinGRES) REPLY="asks for fewer GPUs than its QOS needs" REPLY_BAD=1 ;;
    QOSMax*PerUser*|QOSMax*PU*) REPLY="your limit in this QOS is used up" ;;
    QOSGrp*) REPLY="the QOS limit is used up by everyone" ;;
    QOSMax*|QOSMin*) REPLY="outside a per-job limit of its QOS" REPLY_BAD=1 ;;
    PartitionTimeLimit) REPLY="time limit is over the partition's" REPLY_BAD=1 ;;
    PartitionNodeLimit) REPLY="asks for more nodes than the partition allows" REPLY_BAD=1 ;;
    ReqNodeNotAvail*) REPLY="a node it needs is down or reserved" ;;
    BadConstraints) REPLY="no node matches its constraints" REPLY_BAD=1 ;;
    Reservation) REPLY="waiting for its reservation to start" ;;
    *) REPLY="" ;;
  esac
}

# Number of tasks in an array task list like 3-9,11%2; 1 for N/A (no array)
array_tasks() {
  REPLY=1
  [[ $1 =~ ^([0-9,-]+) ]] || return 0
  local p
  REPLY=0
  for p in ${BASH_REMATCH[1]//,/ }; do
    if [[ $p == *-* ]]; then
      REPLY=$(( REPLY + ${p#*-} - ${p%-*} + 1 ))
    else
      REPLY=$(( REPLY + 1 ))
    fi
  done
}

# Squeeze a Slurm time like 2-17:36:01, 17:36:01 or 36:01 into 2d17h,
# 17h36m or 36m; other values (UNLIMITED, INVALID) are lowercased
short_time() {
  if [[ $1 =~ ^(([0-9]+)-)?(([0-9]+):)?([0-9]+):[0-9]+$ ]]; then
    local d=${BASH_REMATCH[2]} h=${BASH_REMATCH[4]} m=${BASH_REMATCH[5]}
    if [[ -n $d ]]; then
      printf -v REPLY '%dd%02dh' "$d" "$((10#$h))"
    elif [[ -n $h ]]; then
      printf -v REPLY '%dh%02dm' "$((10#$h))" "$((10#$m))"
    else
      REPLY="$((10#$m))m"
    fi
  else
    REPLY=${1,,}
  fi
}

print_jobs() {
  local -a lines=()
  mapfile -t lines < <(squeue -h -u "$TARGET" -o "%i|%j|%T|%P|%D|%C|%b|%M|%L|%S|%r|%N|%K" 2>/dev/null |
                       sort -t'|' -k3,3r -k1,1V)

  local d=$C_DIM e=$C_END none="$C_DIM$G_NONE$C_END" dots="…"
  if (( ASCII )) || [[ $G_NONE != "·" ]]; then dots="~"; fi
  local nrun=0 nqueue=0 grun=0 gqueue=0 now
  printf -v now '%(%Y-%m-%dT%H:%M:%S)T' -1
  local id name state parts nodes cpus tres ran left start reason list
  local gpus type more last tasks array
  tbl_new rllllrrrrl "id" "name" "state" "type" "" "gpus" "cpus" "ran" "left" "node / why queued"
  for line in "${lines[@]}"; do
    IFS='|' read -r id name state parts nodes cpus tres ran left start reason list array <<< "$line"

    gpus=0
    if [[ $tres == *gpu* ]]; then
      gpus=${tres##*gpu}; gpus=${gpus##*[:=]}
      [[ $gpus =~ ^[0-9]+$ ]] || gpus=1
      gpus=$(( gpus * nodes ))
    fi
    if (( ${#name} > NAME_MAX )); then name="${name:0:NAME_MAX-1}$dots"; fi
    if (( ${#id} > ID_MAX )); then id="${id:0:ID_MAX-2}$dots]"; fi
    type=${parts%%,*} more=""
    if [[ $parts == *,* ]]; then
      more=${parts//[^,]/}
      more="$d+${#more}$e"
    fi

    local -a why=()
    case $state in
      RUNNING)
        nrun=$(( nrun + 1 )) grun=$(( grun + gpus ))
        state=running
        short_time "$ran"; ran=$REPLY
        short_time "$left"
        left=$REPLY
        if [[ $left =~ ^[0-9]+m$ ]]; then left="$C_RED$left$e"; fi
        why=("$list") ;;
      PENDING)
        array_tasks "$array"; tasks=$REPLY
        nqueue=$(( nqueue + tasks )) gqueue=$(( gqueue + gpus * tasks ))
        state="${C_YELLOW}queued$e" ran=$none left=$none
        explain_reason "$reason"
        if (( REPLY_BAD )); then
          why=("$C_RED$reason$e" "$REPLY")
        elif [[ -n $REPLY ]]; then
          why=("$d$reason$e" "$REPLY")
        else
          why=("$reason")
        fi
        if [[ $start == 20* && $start > $now ]]; then
          start=${start#*-}
          why+=("${d}est. start$e ${start/T/ }")
          why[-1]=${why[-1]%:*}
        fi ;;
      *)
        state="$d${state,,}$e"
        short_time "$ran"; ran=$REPLY
        short_time "$left"; left=$REPLY
        why=("$list") ;;
    esac
    last=$(IFS=$ITEM; echo "${why[*]}")
    if (( gpus == 0 )); then gpus=$none; fi
    tbl_row "$id" "$name" "$state" "$type" "$more" "$gpus" "$cpus" "$ran" "$left" "$last"
  done

  local stats=("$TARGET")
  stats+=("$nrun running ($grun GPUs)" "$nqueue queued ($gqueue GPUs)")
  if [[ $GPU_LIMIT =~ ^[0-9]+$ ]]; then
    stats+=("GPU limit $GPU_LIMIT")
    if (( GPU_USED >= GPU_LIMIT )); then stats[-1]="$C_RED${stats[-1]}$e"; fi
  fi
  local title="My jobs"
  if [[ $TARGET != "${USER:-}" ]]; then title="Jobs"; fi
  print_title "$title" "${stats[@]}"
  if (( ${#lines[@]} == 0 )); then
    printf '%sNo jobs.%s\n' "$d" "$e"
    return
  fi
  tbl_print
}

# --- fairshare ------------------------------------------------------------------

# Round $1 (a decimal) into a short number: 1234567 -> 1.2M, 5.3 -> 5.3
short_num() {
  REPLY=$(awk -v x="$1" 'BEGIN {
    if (x >= 1e6) printf "%.1fM", x / 1e6
    else if (x >= 1e4) printf "%.0fk", x / 1e3
    else if (x >= 1e3) printf "%.1fk", x / 1e3
    else if (x >= 10) printf "%.0f", x
    else if (x > 0 && x < 0.05) printf "<0.1"
    else printf "%.1f", x }')
}

print_fairshare() {
  local d=$C_DIM e=$C_END
  local weight half
  weight=$(scontrol show config 2>/dev/null | awk '$1 == "PriorityWeightFairShare" { print $3 }')
  half=$(scontrol show config 2>/dev/null | awk '$1 == "PriorityDecayHalfLife" { print $3 }')
  if [[ $half =~ ^([0-9]+)-00:00:00$ ]]; then half="${BASH_REMATCH[1]} days"; fi

  if [[ -z $FACTOR ]]; then
    print_title "Fairshare" "$TARGET"
    printf '%sNo association found.%s\n' "$d" "$e"
    return
  fi
  local stats=("$TARGET" "factor $FACTOR")
  if (( PEERS )); then stats+=("rank $RANK of $PEERS"); fi
  if [[ $weight =~ ^[0-9]+$ ]]; then
    stats+=("priority +$(awk -v f="$FACTOR" -v w="$weight" 'BEGIN { printf "%.0f", f * w }') of $weight")
  fi
  if [[ -n $half ]]; then stats+=("half-life $half"); fi
  print_title "Fairshare" "${stats[@]}"

  # One row per GPU type used, biggest billing first, then CPUs
  local -a rows=()
  local key
  mapfile -t rows < <(
    for key in "${!USAGE[@]}"; do
      if [[ $key == gres/gpu:* && -n ${WEIGHT[$key]:-} ]]; then
        printf '%s %s %s\n' "${LABEL[$key]}" "${USAGE[$key]}" "${WEIGHT[$key]}"
      fi
    done | awk '{ print $1, $2, $3, $2 * $3 }' | sort -k4,4nr
    if [[ -n ${USAGE[cpu]:-} && -n $CPU_WEIGHT ]]; then
      awk -v m="${USAGE[cpu]}" -v w="$CPU_WEIGHT" 'BEGIN { print "cpu", m, w, m * w }'
    fi)
  if (( ${#rows[@]} == 0 )); then
    printf '%sNo usage recorded.%s\n' "$d" "$e"
    return
  fi

  local total
  total=$(printf '%s\n' "${rows[@]}" | awk '{ t += $4 } END { print t }')
  local block="█"
  if [[ $G_NONE != "·" ]]; then block="#"; fi
  tbl_new lrrrrl "type" "hours" "weight" "billing" "share" ""
  local label mins w bill hours share tenths n bar
  for key in "${rows[@]}"; do
    read -r label mins w bill <<< "$key"
    short_num "$(awk -v m="$mins" 'BEGIN { print m / 60 }')"; hours=$REPLY
    short_num "$(awk -v b="$bill" 'BEGIN { print b / 60 }')"; bill=$REPLY
    tenths=$(awk -v b="${key##* }" -v t="$total" 'BEGIN { printf "%.0f", b * 1000 / t }')
    share="$(( tenths / 10 )).$(( tenths % 10 ))%"
    n=$(( (tenths * BAR + 500) / 1000 ))
    printf -v bar '%*s' "$n" ''
    bar=${bar// /$block}
    if [[ $label == cpu ]]; then
      tbl_row "${d}cpu$e" "$hours" "$w" "$bill" "$share" "$d$bar$e"
    else
      tbl_row "$label" "$hours" "$w" "$bill" "$share" "$bar"
    fi
  done
  tbl_print
}

init_style
read_assoc
read_weights
print_jobs
echo
print_fairshare
