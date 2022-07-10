# 클러스터 남은 자리 찾기 자동화

## Usage

1. Clone Project

```
git clone https://github.com/postech-isoft/cluster-remains.git
```

2. Set alias on .bashrc
```
alias sremain="python ~/_YOUR_PATH_/cluster-remains/cluster_parser.py"
```
`source ~/.bashrc` for initialize

3. Run `sremain`
```
$ sremain

GPU             REMAIN         
------------------------------
2080ti          44/48             
TITANRTX        0/4              
A100            0/8              
4A100           0/8              
A100-pci        0/8              
A5000           0/48             
A100-80GB       1/16             

NODE            GPU             REMAIN         
---------------------------------------------
n1              2080ti          4/8              
n2              2080ti          8/8              
n3              2080ti          8/8              
n4              2080ti          8/8              
n5              2080ti          8/8              
n6              2080ti          8/8              
n12             A5000           8/8              
n19             A100-80GB       1/8          
```

## TODO

1. better alias, automatic .bashrc updater.
2. ~~sinfo updater~~ done by https://github.com/postech-isoft/cluster-remains/pull/1#issue-1299865287



---

1. using only shell script (remove python dependency)
