# 클러스터 남은 자리 찾기 자동화

## Installation
```
!V2!
If you already set alias from previous version, you must erase sremain alias in ~/.bashrc
```

1. Clone Project

```
git clone https://github.com/postech-isoft/cluster-remains.git
```

2. Install with `PIP`

```
cd cluster-remains
```

```
pip install -e .
```

## Usage

1. Run `sremain`

(Option) -a, --all 
	return all nodes
```
[you@gsai-master]$ sremain -a

GPU             REMAIN         
------------------------------
2080ti          44/48             
TITANRTX        0/4              
A100            0/8              
4A100           0/8              
A100-pci        0/8              
A5000           0/48             
A100-80GB       0/16             

NODE            GPU             REMAIN         
---------------------------------------------
n1              2080ti          4/8              
n2              2080ti          8/8              
n3              2080ti          8/8              
n4              2080ti          8/8              
n5              2080ti          8/8              
n6              2080ti          8/8              
n7              TITANRTX        0/4              
n8              A100            0/8              
n9              4A100           0/8              
n10             A100-pci        0/4              
n11             A100-pci        0/4              
n12             A5000           8/8              
n13             A5000           0/8              
n14             A5000           0/8              
n15             A5000           0/8              
n16             A5000           0/8              
n17             A5000           0/8              
n18             A5000           0/8              
n19             A100-80GB       0/8              
n20             A100-80GB       0/8       
```

--- 
https://user-images.githubusercontent.com/29483429/202845383-2c8db4b2-df64-4a90-b9d5-56f639a028f5.mov


### Test with squeue file

You can test `sremain` using a saved `squeue` output file (e.g., `sample.squeue`) instead of querying live.

```
[you@gsai-master]$ sremain -f sample.squeue
[you@gsai-master]$ sremain -a -f sample.squeue
```

When using `-f/--file`, `sremain` also looks for a matching `sinfo` snapshot named `20251105.sinfo` and uses it for cluster/node info. It searches first in the same directory as the provided squeue file, then in the current directory. If not found, it falls back to live `sinfo`.

```
# files side-by-side
./sample.squeue
./20251105.sinfo
```


### Extract Slurm Job Output Log with `slog`

You can use the `slog` command to print the output log file of a Slurm job by providing its job ID. This will automatically extract the StdOut log path from `scontrol show job` and print its contents.

**Example:**

```
[you@gsai-master]$ slog 732893
```

This will print the contents of the log file referenced by `StdOut` for job 732893.

## TODO

1. ~~better alias, automatic .bashrc updater.~~
2. ~~sinfo updater~~ done by https://github.com/postech-isoft/cluster-remains/pull/1#issue-1299865287
3. build setuptools 


---

1. using only shell script (remove python dependency)
