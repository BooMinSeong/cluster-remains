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
- Adds a small alias block to your rc (`~/.bashrc` by default) so you can run `sremain` and `scrime` from anywhere.
- Also creates optional wrappers at `~/.local/bin/sremain` and `~/.local/bin/scrime` if available.
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
```

## Output style

`sremain` answers "where can I run?" and `scrime` answers "who is using the GPUs?". Both print the same way:

- A bold title line with the totals, then one table (header, rule, rows).
- One row per thing, with every value in its own aligned column.
- Numbers are right-aligned, `·` means none, and `free/total` cells line up on the `/`.
- Each color means one thing: green = free now, yellow = queued, red = over the limit, bold = group heading, dim = nothing there or secondary.
- GPU types are the GPU partitions, in `sinfo` order. The `queue` column counts the GPUs that queued jobs ask for, in both tools.

Shared parsing and drawing live in `common.sh`, which must stay next to `sremain.sh` and `scrime.sh`.

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
