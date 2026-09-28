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

## Usage

`sremain [-a|--all] [-f|--file PATH] [-h|--help]`

- `-a, --all`  Show all nodes and include a USERS(G, C) summary per node.
- `-f, --file PATH`  Read `squeue` output from a file for offline testing. When set, the tool also looks for `20251105.sinfo` (in the same directory or the current directory) for node/partition layout. If not found, it falls back to live `sinfo`.

Examples:
```
sremain
sremain -a
sremain -f sample.squeue
sremain -a -f sample.squeue
```

Sample output (truncated):
```
GPU             REMAIN          CPU_REMAIN
-----------------------------------------
2080ti          44/46           108/120

NODE            GPU             REMAIN          CPU_REMAIN
---------------------------------------------------------
n2              2080ti          7/8             6/20
```

## Parsing notes

- `sremain` uses this `squeue` format string internally (group column removed):
  - `squeue -o "%6i %12j  %9T %12u %15P %4D %20R %4C %40b %8m %11l %11L"`
- The parser reads columns from the right to tolerate spaces in job NAMEs.
- GPU count is derived from the `TRES_PER_NODE` field (e.g., `gres/gpu:MODEL:4`).
- Draining/down/unknown nodes are excluded; CPU-only partitions are ignored.

If you pass `-f sample.squeue`, the tool expects a header like:
`JOBID NAME STATE USER PARTITION NODE NODELIST(REASON) CPUS TRES_PER_NODE MIN_MEM TIME_LIMIT TIME_LEFT`.


## scrime (per-user GPU usage)

Summarize per-user running GPUs and queued GPUs with a ranked, colorized table.

`scrime [-f|--file PATH] [-t|--threshold PCT] [--ascii] [-h|--help]`

- `-f, --file PATH`  Read a saved `squeue` output (same format as `sremain`).
- `-t, --threshold`  Percent of total running GPUs to flag as “CRIMINAL” (default: 10).
- `--ascii`  Draw with ASCII only. This is the default when the locale isn't UTF-8. Use it if your terminal draws block characters double-width.

Examples:
```
scrime
scrime -f sample.squeue
scrime -t 15
```

Sample output (truncated):
```
GPU usage · 456 running · 102 queued · 32 users · limit 10%
──────────────────────────────────────────────────────────────────
  #  user          gpus  queue  share  █ run  ░ queued  ┆ limit
  1  tsyeom          88      ·  19.3%  ████████████████████████  CRIMINAL
  2  gongda0e        76      ·  16.7%  ████████████████████▋     CRIMINAL
  3  jaehyunglim     33      ·   7.2%  █████████   ┆
 13  minkyoung       10    +30   2.2%  ██▋░░░░░░░░ ┆
     pending only (no running GPUs)
  ·  hjh9902          ·     +4      ·  ░           ┆
```

- Each bar shows running GPUs (`█`) followed by queued GPUs (`░`), scaled to the top user. So `█` plus `░` shows how far a user would reach if their queue ran.
- `┆` marks the threshold. Blocks past it are red for users over the limit.
- Users with only queued GPUs are listed at the bottom.

## Output width

Both tools fit their tables to the terminal width.

- `sremain` keeps the usual 15-char columns when rows fit. Otherwise it switches to a compact layout, and with `-a` wraps the USERS column onto indented lines.
- `scrime` resizes the usage bar (8–50 chars) to fill the remaining width and hides it when less than 8 chars are left. The summary line wraps between items.
- The width comes from `$COLUMNS` if exported (`watch` does this), otherwise from the terminal. Piped or redirected output has no width limit. You can force a width with e.g. `COLUMNS=100 sremain -a | less -R`.

## Notes
- Tested against saved outputs (`sample.squeue`) and live Slurm on our cluster.
