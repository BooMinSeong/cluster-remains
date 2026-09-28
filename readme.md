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
- Numbers are right-aligned, `·` means none, and `free/total` cells line up on the `/`.
- The last column lists `label:count` items, largest first. It wraps under itself when the terminal is narrow.
- Each color means one thing: green = free now, yellow = queued, red = over the limit, dim = nothing there or secondary.
- GPU types are the GPU partitions, in `sinfo` order. The `queue` column counts the GPUs that queued jobs ask for, in both tools.

Shared parsing and drawing live in `common.sh`, which must stay next to `sremain.sh` and `scrime.sh`.

## sremain (free GPUs)

`sremain [-a|--all] [-f|--file PATH] [--ascii] [-h|--help]`

- `-a, --all`  Also list every node with the users on it (`user:gpus/cpus`).
- `-f, --file PATH`  Read `squeue` output from a file for offline testing. When set, the tool also looks for `20251105.sinfo` (in the same directory or the current directory) for the node layout. If not found, it falls back to live `sinfo`.
- `--ascii`  Draw with ASCII only. This is the default when the locale isn't UTF-8.

Examples:
```
sremain
sremain -a
sremain -f sample.squeue
```

Sample output (truncated):
```
GPU availability · 163 of 621 free · 102 queued · 2 without a free CPU
type        free gpus  queue  free cpus  node:free
──────────────────────────────────────────────────────────────────────────────────
2080ti         44/46       ·    48/120   n[1,4-5]:8  n[2-3]:7  n6:6
3090           46/175      ·   165/1024  n32:6  n[28,31,33]:4  n[17,19,21,27,30]:3
                                         n[11,18,25]:2  n[9,12-14,23,26,29]:1
                                         no CPU: n[24,34]:1
A6000          12/48      +6   146/272   n60:5  n[44-45]:2  n[42-43,46]:1
A100-pci        0/8        ·   104/128

node  type        free gpus  free cpus  user:gpus/cpus
──────────────────────────────────────────────────────────────────────────────────
n2    2080ti            7/8      6/20   jaehyunglim:1/4  qwg724:0/10
```

- `node:free` groups nodes by how many GPUs they have free, so `n[28,31,33]:4` means 4 free on each of n28, n31 and n33. The first item is the largest job that fits on one node right now.
- A node with free GPUs but no free CPU can't start a job. Its GPUs aren't counted as free and are listed dim after `no CPU:`.
- Rows with nothing free are dim.

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
 #  user          gpus  queue  share            type:gpus
──────────────────────────────────────────────────────────────────────────────────
 1  tsyeom          88      ·  19.3%  CRIMINAL  3090:47  A6000:30  RTX6000ADA:9
                                                A5000:1  RTX4090:1
 5  r7play          24    +12   5.3%            A100-80GB:24+12
    queued only
 ·  hjh9902          ·     +4      ·            H200:+4
```

- `type:gpus` shows the GPU types a user runs on. `A100-80GB:24+12` is 24 running and 12 more queued there.
- Users at or over the threshold are red and flagged `CRIMINAL`. Users queuing more than 50 GPUs are flagged `WTF`.
- Users with only queued GPUs are listed at the bottom.

## Parsing notes

- Live data comes from `squeue -o "%T %u %P %D %C %b %R"` and `sinfo -o "%P %C %t %N %D %G %m %l %f"`.
- GPUs per job come from `TRES_PER_NODE` (e.g. `gres/gpu:MODEL:4`) times its node count. GPUs per node come from sinfo's GRES, or from a feature like `...-8GPU` when GRES is cut off.
- CPU use per node includes jobs from the `cpu-*` partitions, since they share the GPU nodes.
- Down, draining and unknown nodes are left out; `cpu-*` partitions aren't GPU types.
- `-f` accepts a file in the format above or the older one in `sample.squeue` (`JOBID NAME STATE USER PARTITION NODE NODELIST(REASON) CPUS TRES_PER_NODE ...`), told apart by the header.

## Output width

Both tools fit their tables to the terminal width by wrapping the last column between items. The title line wraps between stats.

The width comes from `$COLUMNS` if exported (`watch` does this), otherwise from the terminal. Piped or redirected output has no width limit. You can force a width with e.g. `COLUMNS=100 sremain -a | less -R`. Set `NO_COLOR` to turn colors off.

## Notes
- Tested against saved outputs (`sample.squeue`) and live Slurm on our cluster.
