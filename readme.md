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
- Adds a small alias block to your rc (`~/.bashrc` by default) so you can run `sremain` from anywhere.
- Also creates an optional wrapper at `~/.local/bin/sremain` if available.
- Uninstall: `./install.sh --uninstall`
- Use a different rc file: `./install.sh --rc ~/.zshrc`

Manual alternative:
```
# in your shell rc
sremain() {
  "/path/to/cluster-remains/sremain.sh" "$@"
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


## Notes
- Tested against saved outputs (`sample.squeue`) and live Slurm on our cluster.
