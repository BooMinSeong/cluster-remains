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
cd cluster-remain
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

GGPU             REMAIN          CPU_REMAIN     
---------------------------------------------
2080ti          0/48            24/120         
TITANRTX        0/4             40/48          
3090            61/162          445/832        
A5000           2/56            312/448        
A6000           19/40           188/240        
A100-pci        8/8             128/128        
4A100           0/8             240/256        
A100-40GB       8/8             256/256        
A100-80GB       31/72           439/576        

NODE            GPU             REMAIN          CPU_REMAIN     
------------------------------------------------------------
n1              2080ti          0/8             4/20         
n2              2080ti          0/8             4/20         
n3              2080ti          0/8             4/20         
n4              2080ti          0/8             4/20         
n5              2080ti          0/8             4/20         
n6              2080ti          0/8             4/20         
n7              TITANRTX        0/4             40/48         
n8              3090            1/4             12/32         
n9              3090            2/4             16/32         
n10             3090            0/4             16/32         
n11             3090            1/4             20/32         
n12             3090            0/4             16/32         
n13             3090            0/4             16/32         
n14             3090            1/4             20/32         
n15             3090            1/4             20/32         
n16             3090            0/4             16/32         
n17             3090            0/4             19/32         
n18             3090            3/8             15/32         
n19             3090            6/8             16/32         
n20             3090            4/8             16/32         
n21             3090            4/8             16/32         
n22             3090            6/8             16/32         
n23             3090            4/8             16/32         
n24             3090            0/8             24/32         
n26             3090            4/8             16/32         
n27             3090            3/8             15/32         
n28             3090            4/8             16/32         
n29             3090            4/8             16/32         
n30             3090            4/8             16/32         
n31             3090            0/8             24/32         
n32             3090            4/8             16/32         
n33             3090            3/5             16/32         
n34             3090            2/5             20/32         
n35             A5000           2/8             40/64         
n36             A5000           0/8             32/64         
n37             A5000           0/8             56/64         
n38             A5000           0/8             56/64         
n39             A5000           0/8             32/64         
n40             A5000           0/8             48/64         
n41             A5000           0/8             48/64         
n42             A6000           0/8             32/48         
n43             A6000           6/8             40/48         
n44             A6000           7/8             44/48         
n45             A6000           6/8             40/48         
n46             A6000           0/8             32/48         
n47             A100-pci        4/4             64/64         
n48             A100-pci        4/4             64/64         
n49             A100-40GB       8/8             256/256        
n50             4A100           0/8             240/256        
n51             A100-80GB       1/8             47/64         
n52             A100-80GB       7/8             63/64         
n53             A100-80GB       7/8             63/64         
n54             A100-80GB       0/8             48/64         
n55             A100-80GB       4/8             0/64         
n56             A100-80GB       4/8             48/64         
n57             A100-80GB       7/8             63/64         
n58             A100-80GB       1/8             55/64         
n59             A100-80GB       0/8             52/64         
```

--- 


https://user-images.githubusercontent.com/29483429/202845383-2c8db4b2-df64-4a90-b9d5-56f639a028f5.mov



## TODO

1. ~~better alias, automatic .bashrc updater.~~
2. ~~sinfo updater~~ done by https://github.com/postech-isoft/cluster-remains/pull/1#issue-1299865287
3. ~~build setuptools~~


---

1. using only shell script (remove python dependency)
