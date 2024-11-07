from doctest import FAIL_FAST
import os
import argparse
import re
from collections import defaultdict
from pprint import pprint

parser = argparse.ArgumentParser(description="Argparse Tutorial")
parser.add_argument("--all", "-a", action="store_true")
args = parser.parse_args()


class bcolors:
    HEADER = "\033[95m"
    OKBLUE = "\033[94m"
    OKCYAN = "\033[96m"
    OKGREEN = "\033[92m"
    WARNING = "\033[93m"
    FAIL = "\033[91m"
    ENDC = "\033[0m"
    BOLD = "\033[1m"
    UNDERLINE = "\033[4m"


def get_cluster_info(lines):
    cluster_info = {}
    for line in lines[1:]:
        parsed = line.strip().split()
        gpu_name = parsed[0].strip("*")  # for 2080ti*
        if gpu_name.startswith("cpu") or parsed[2].startswith("down"):
            continue
        if gpu_name not in cluster_info:
            cluster_info[gpu_name] = [int(parsed[4]) * int(parsed[8][-4]), int(parsed[1].split("/")[3])]
        else:
            cluster_info[gpu_name][0] += int(parsed[4]) * int(parsed[8][-4])
            cluster_info[gpu_name][1] += int(parsed[1].split("/")[3])

    return cluster_info


def get_node_info(lines):
    node_info = {}
    sorted_node_info = {}

    for line in lines[1:]:
        parsed = line.strip().split()
        gpu_name = parsed[0].strip("*")  # for 2080ti*
        gpu_num = int(parsed[8][-4])
        cpu_num = int(int(parsed[1].split("/")[3]) / int(parsed[4]))
        
        node_state = parsed[2]
        if gpu_name.startswith("cpu"):
            continue
        if node_state.startswith("down"):
            continue

        nodelist = parsed[3]
        assert nodelist.startswith("n")
        node_range_str = nodelist[1:].strip("[,]")

        # parse with , first
        gpu_nodes = []
        nodes = node_range_str.split(",")
        for n in nodes:
            nds = (
                list(range(int(n.split("-")[0]), int(n.split("-")[1]) + 1))
                if "-" in n
                else [int(n)]
            )
            gpu_nodes += nds

        for gnode in gpu_nodes:
            node_name = f"n{gnode}"
            if node_name not in node_info:
                node_info[node_name] = {
                    "name": gpu_name,
                    "num": gpu_num,
                    "cpu_num": cpu_num,
                    "state": node_state,
                }

    sorted_keys = sorted(node_info, key=lambda x: int(x[1:]))
    for k in sorted_keys:
        sorted_node_info[k] = node_info[k]

    return sorted_node_info


def init_accumulator(info_dict):
    init_dict = {}
    for k in info_dict:
        init_dict[k] = [0, 0]
    return init_dict


def main():
    # to get dynmaic info_dicts
    info_stream = os.popen('sinfo   -o "%16P %14C  %6t %25N %5D %15G  %10m %11l %30f"')
    info_lines = info_stream.readlines()

    criminal = defaultdict(int)
    pending_criminal = defaultdict(int)

    stream = os.popen(
        'squeue -o "%6i %12j  %9T %12u %8g %15P %4D %20R %4C %13b %8m %11l %11L"'
    )
    output = stream.readlines()
    # lines = "".join(output[1:])
    # print(lines)

    total_cnt = 0
    pending_cnt = 0
    lines = output[1:]
    for line in lines:
        splited = line.strip().split()
        partition = splited[5]
        node = splited[7]
        user = splited[3]


        state = None
        # it's Running  
        if node[0] == "n":
            state = "running"
        # it's Pending
        if node == "(Priority)" or node == "(Resources)" or node[0]=="(":
            state = "pending"

        gpu_num = splited[9]
        cpu_num = splited[8]

        if gpu_num.startswith("gres/gpu"):
            gpu_num = gpu_num[-1]
        else:
            gpu_num = 0

        if partition.startswith("cpu"):
            continue

        # for the case like n[16-17]
        nodes = [node]
        if node[0] != "(" and ((len(node.split("-")) >= 2) or (len(node.split(",")) >= 2)):
            nodes = re.findall(r"\d+", node)  # reinit with node numbers
            nodes = ["n" + x for x in nodes]
            print(nodes)
        gpu_num = int(gpu_num) / len(nodes)
        
        if state == "running":
            cpu_num = int(cpu_num) / len(nodes)

        # print(user, nodes, gpu_num, cpu_num, partition)

        if state == "running":
            criminal[user] += int(gpu_num)
            total_cnt+=int(gpu_num)

        if state == "pending":
            pending_criminal[user] += int(gpu_num)
            pending_cnt+=int(gpu_num)



    criminal  = dict(sorted(criminal.items(), key=lambda item: item[1], reverse=True))
    # print(criminal)
    print(f"User{1:<15}Num_GPUs")
    for k, v in criminal.items():
        print(f"{k:<15}\t\t{v}", end="")
        if v > total_cnt*0.1:
            print(f" <--- criminal !!! {100*v/total_cnt:.2f}% use",  end=" ")
        
        print(f"  Queued: {pending_criminal[k]} GPUS", end="")
        if pending_criminal[k] > 50:
            print(" <--- WTF", end="")
        print()
        # print(f"User \t Num_GPUs")

    
if __name__ == "__main__":
    main()
