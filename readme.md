# 클러스터 남은 자리 찾기 자동화

## Installation

1. Clone Project

```
git clone https://github.com/postech-isoft/cluster-remains.git
```

2. Set alias on ~/.bashrc

```
echo alias sremain=\"python ~/___YOUR_PATH___/cluster-remains/cluster_parser.py\" >> ~/.bashrc
echo alias smp=\"bash ~/___YOUR_PATH___/cluster-remains/smp.sh\" >> ~/.bashrc
```
or 

```
vim ~/.bashrc

(Add line below at the end of file.)

alias sremain="python ~/_YOUR_PATH_/cluster-remains/cluster_parser.py"
alias smp="bash ~/___YOUR_PATH___/cluster-remains/smp.sh"
```



3. Initialize 

`source ~/.bashrc` for initialize

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

2. Run `smp`

Slurm My Priority: This command shows my priority. It is useful to check whether the submitted job can be pushed out.

⚠️Warning⚠️- 1회 사용 시 Priority 1 감소

```
[you@gsai-master]$ smp
My Priority: 4294899209
[you@gsai-master]$ smp
My Priority: 4294899208
```


https://user-images.githubusercontent.com/29483429/202845383-2c8db4b2-df64-4a90-b9d5-56f639a028f5.mov



## TODO

1. ~~better alias, automatic .bashrc updater.~~
2. ~~sinfo updater~~ done by https://github.com/postech-isoft/cluster-remains/pull/1#issue-1299865287



---

1. using only shell script (remove python dependency)
