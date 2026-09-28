# Cluster Remains (Slurm)

Show remaining GPU and CPU capacity per GPU type (partition) and per node in a Slurm cluster.

- Pure Bash (`sremain.sh`) — no Python runtime needed.
- Legacy Python scripts are kept for reference and optional use.

## Requirements
- Bash 4+ (uses associative arrays)
- Slurm client tools available in PATH: `squeue`, `sinfo`, `scontrol`

## Install

- Quick install (adds `sremain` to your shell):
  - Clone: `git clone https://github.com/postech-isoft/cluster-remains.git`
  - Run installer: `./cluster-remains/install.sh`
  - Reload shell: `source ~/.bashrc`

Installer details:
- Adds a small alias block to your rc (`~/.bashrc` by default) so you can run `sremain`, `scrime` and `smine` from anywhere.
- Also creates optional wrappers at `~/.local/bin/sremain`, `~/.local/bin/scrime` and `~/.local/bin/smine` if available.
- Uninstall: `./install.sh --uninstall`
- Use a different rc file: `./install.sh --rc ~/.zshrc`

Manual alternative:
```
# in your shell rc
sremain() {
  "/path/to/cluster-remains/sremain.sh" "$@"
}
scrime() {
  "/path/to/cluster-remains/scrime.sh" "$@"
}
smine() {
  "/path/to/cluster-remains/smine.sh" "$@"
}
```

## Output style

`sremain` answers "where can I run?", `scrime` answers "who is using the GPUs?" and `smine` answers "how are my jobs doing?". All print the same way:

- A bold title line with the totals, then one table (header, rule, rows).
- One row per thing, with every value in its own aligned column.
- Numbers are right-aligned, `·` means none, and `free/total` cells line up on the `/`.
- Each color means one thing: green = free now, yellow = queued, red = over the limit, bold = group heading, dim = nothing there or secondary.
- GPU types are the GPU partitions, in `sinfo` order. The `queue` column counts the GPUs that queued jobs ask for, in both tools.

Shared parsing and drawing live in `common.sh`, which must stay next to the scripts.

## sremain (free GPUs)

`sremain [-F|--full] [-a|--all] [-f|--file PATH] [--ascii] [-h|--help] [GPU...]`

By default `sremain` is compact: one row per GPU type. To see nodes, name the GPU types or use `-F`.

- `GPU...`  Show these GPU types with their nodes. Case doesn't matter. A name that matches no type exactly picks every type containing it, so `a100` shows all A100 types.
- `-F, --full`  Show the nodes of every GPU type.
- `-a, --all`  Show every node, including those with no free GPU, and the users on it (`user:gpus/cpus`). Implies `-F` if no GPU is named.
- `-f, --file PATH`  Read `squeue` output from a file for offline testing. When set, the tool also looks for `20251105.sinfo` (in the same directory or the current directory) for the node layout. If not found, it falls back to live `sinfo`.
- `--ascii`  Draw with ASCII only. This is the default when the locale isn't UTF-8.

Examples:
```
sremain
sremain A6000
sremain a100 h200
sremain -F
sremain -a
```

Compact (truncated):
```
GPU availability · 165 of 621 free · 102 queued
type        free gpus  free cpus  queue
───────────────────────────────────────
3090           48/175   165/1024      ·
A5000           2/56    346/448       ·
A6000          12/48    146/272      +6
A100-40GB       1/8     214/256       ·
RTX4090        15/20    152/160       ·
```

With nodes, `sremain 3090` (truncated):
```
GPU availability · 48 of 175 free · 0 queued
type / node  free gpus  free cpus  cpus/gpu  queue
──────────────────────────────────────────────────
3090            48/175   165/1024                ·
  n32            6/8      16/32         2.7
  n31            4/8      10/32         2.5
  n33            4/8       5/32         1.3
  n28            4/8       3/32         0.8
  n19            3/8      13/48         4.3
  ...
```

- Nodes are listed under their GPU type, most free GPUs first.
- `cpus/gpu` is the node's free CPUs per free GPU. A job needs CPUs too, so free GPUs on a node with few CPUs left may be unusable for your job. Nodes with no free CPU are dim.
- Types with nothing free are dim.

`sremain -a H200`:
```
GPU availability · 2 of 8 free · 8 queued
type / node  free gpus  free cpus  cpus/gpu  queue  user:gpus/cpus
─────────────────────────────────────────────────────────────────────────────
H200               2/8      46/64               +8
  n87              2/8      46/64      23.0         qwg724:4/16  khj20343:2/2
```

## scrime (per-user GPU usage)

`scrime [-f|--file PATH] [-t|--threshold PCT] [--ascii] [-h|--help]`

- `-f, --file PATH`  Read a saved `squeue` output (same as `sremain`).
- `-t, --threshold`  Percent of running GPUs to flag as `CRIMINAL` (default: 10).
- `--ascii`  Draw with ASCII only. This is the default when the locale isn't UTF-8.

Examples:
```
scrime
scrime -f sample.squeue
scrime -t 15
```

Sample output (truncated):
```
GPU usage · 456 of 621 running · 102 queued · 32 users · limit 10% = 46
 #  user          gpus  queue  share  main            more
────────────────────────────────────────────────────────────────────────
 1  tsyeom          88      ·  19.3%  3090        47  +4 types  CRIMINAL
 2  gongda0e        76      ·  16.7%  A5000       48  +2 types  CRIMINAL
 3  jaehyunglim     33      ·   7.2%  3090        32  +1 type
 4  jinseokchung    33      ·   7.2%  RTX6000ADA  18  +2 types
 5  r7play          24    +12   5.3%  A100-80GB   24
    queued only
 ·  hjh9902          ·     +4      ·  H200        +4
```

- `main` is the GPU type a user runs the most GPUs on, with that count. `more` counts the other types they run on.
- Users at or over the threshold are red and flagged `CRIMINAL`. Users queuing more than 50 GPUs are flagged `WTF`.
- Users with only queued GPUs are listed at the bottom, with the type they queue the most on.

## smine (my priority and jobs)

`smine [-u|--user USER] [-a|--all] [--ascii] [-h|--help]`

The first line is your priority from fairshare out of its weight, how many of the other active users of your account rank ahead of you (active means any decayed usage; users with none are left out since they don't compete), your decayed usage against the median user with any usage, and your priority in a week if you start nothing new. Your jobs follow.

Colors on the first line: the priority is green, yellow or red by how close it is to the best reachable (users with no usage always rank first, so nobody with usage reaches the full weight); usage is green at or below the median, yellow up to twice it, red beyond; the week ahead is green if the priority rises.

- `-u, --user USER`  Show USER instead of you.
- `-a, --all`  Also show usage by GPU type and how your priority recovers over the next weeks.
- `--ascii`  Draw with ASCII only. This is the default when the locale isn't UTF-8.

Sample output:
```
Priority · dkim011006 · 500/10000 · 153/171 active users ahead · usage 31× median user · 600 in 1 week
My jobs · dkim011006 · 4 running (12 GPUs) · 2 queued (4 GPUs) · GPU limit 64
     id  name     state    type           gpus  cpus    ran   left  prio  node / why queued
─────────────────────────────────────────────────────────────────────────────────────────────────────────
1027741  h200x4   running  H200-ZT           4    32    40m  2d23h     ·  n90
1027742  a80x4    running  A100-80GB         4    32  5h52m  2d18h     ·  n59
1027743  h200x2a  queued   H200       +1     2    16      ·      ·   542  Priority  jobs with higher priority are ahead
                                                                          est. start 09-29 05:50
```

With `-a`:
```
Fairshare · dkim011006 · factor 0.05 · half-life 7 days
type            hours  weight  billing  share
──────────────────────────────────────────────────────────
H200              550     220     121k  55.3%  ███████████
A100-80GB         609     108      66k  30.1%  ██████
4A100             378      60      23k  10.4%  ██
cpu               12k     0.6     7.4k   3.4%  █

Recovery · if you start nothing new · running jobs count until they end · best 0.31, as 421 users with no usage rank first
in       factor     rank  priority
──────────────────────────────────
now        0.05  575/607       500
1 day      0.05  575/607       500
1 week     0.06  571/607       600
2 weeks    0.09  553/607       900
4 weeks    0.13  527/607      1300
8 weeks    0.19  494/607      1900
```

Jobs:
- Running jobs first, then queued ones. `type` is the first partition the job may run in, with `+N` more. `left` is red under an hour.
- `prio` is a queued job's priority as a whole number, the same one `sprio` and `squeue -o %Q` show. The `PRIORITY` column of `squeue -o %p` is this number divided by 2³² (`0.00000012619421 × 2³² = 542`). Higher starts first, among jobs waiting for the same resources.
- Queued jobs show Slurm's reason and what it means, and Slurm's estimated start when it has one in the future. Reasons that won't clear on their own (a failed dependency, a held job, a request over a limit) are red.
- An array job counts as its number of queued tasks in the title. Long ids and names are cut with `…`.
- `GPU limit` is your association's GPU limit (`GrpTRES gres/gpu`), red when you are at it.

Fairshare:
- Read from `scontrol show assoc_mgr`, since `sshare` and `sacctmgr` may be off-limits to users.
- `hours` are the GPU hours (CPU hours for `cpu`) you used on each GPU type, decayed by the half-life. `weight` is the partition's billing weight per GPU (`TRESBillingWeights`), and `billing` is hours times weight. `share` is each row's part of your billing.
- Priority here comes almost only from fairshare (`PriorityWeightFairShare`), so the rows with the biggest share are what lower your priority the most. `rank` is your place among the users of your account by fairshare factor, 1 being the highest.

Recovery:
- Fair Tree ranks the users of an account by usage per share, fewest first, and gives rank `r` of `n` the factor `(n - r + 1) / n`. On our cluster this matches the factor Slurm reports for all but a handful of users.
- The projection decays your usage by the half-life and adds your running jobs' billing until they end (on average, from `GrpTRESRunMins`). Everyone else's usage is held where it is now, as if they kept using at the same pace. If others stop too, you recover more slowly; if they use more, faster.
- `priority` is the fairshare part of a job's priority, factor × `PriorityWeightFairShare`, in the same units as `prio`. It is nearly all of it here.
- Users with no usage all share the top rank, so no one with usage can pass them. `best` is the highest factor you can reach.

## Parsing notes

- Live data comes from `squeue -o "%T %u %P %D %C %b %R"` and `sinfo -o "%P %C %t %N %D %G %m %l %f"`.
- GPUs per job come from `TRES_PER_NODE` (e.g. `gres/gpu:MODEL:4`) times its node count. GPUs per node come from sinfo's GRES, or from a feature like `...-8GPU` when GRES is cut off.
- CPU use per node includes jobs from the `cpu-*` partitions, since they share the GPU nodes.
- Down, draining and unknown nodes are left out; `cpu-*` partitions aren't GPU types.
- `-f` accepts a file in the format above or the older one in `sample.squeue` (`JOBID NAME STATE USER PARTITION NODE NODELIST(REASON) CPUS TRES_PER_NODE ...`), told apart by the header.

## Output width

Both tools fit their output to the terminal width: the title line wraps between stats, and the users column of `sremain -a` wraps between users.

The width comes from `$COLUMNS` if exported (`watch` does this), otherwise from the terminal. Piped or redirected output has no width limit. You can force a width with e.g. `COLUMNS=100 sremain -a | less -R`. Set `NO_COLOR` to turn colors off.

## Notes
- Tested against saved outputs (`sample.squeue`) and live Slurm on our cluster.
