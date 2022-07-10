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

 2080ti 43 장 남음 
 TITANRTX 0 장 남음 
 A100 0 장 남음 
 4A100 0 장 남음 
 A100-pci 7 장 남음 
 A5000 8 장 남음 
 A100-80GB 7 장 남음 
n1 node에 2080ti 8 장 남음
n2 node에 2080ti 5 장 남음
n3 node에 2080ti 8 장 남음
n4 node에 2080ti 8 장 남음
n5 node에 2080ti 8 장 남음
n6 node에 2080ti 6 장 남음
n10 node에 A100-pci 4 장 남음
n11 node에 A100-pci 3 장 남음
n15 node에 A5000 4 장 남음
n18 node에 A5000 4 장 남음
n19 node에 A100-80GB 1 장 남음
n20 node에 A100-80GB 6 장 남음

```

## TODO

1. better alias, automatic .bashrc updater.
2. sinfo updater



---

1. using only shell script (remove python dependency)
