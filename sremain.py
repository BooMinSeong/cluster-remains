from doctest import FAIL_FAST
import os
import argparse
import re

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
        if gpu_name.startswith("cpu") or parsed[2].startswith("down") or parsed[2].startswith("drain"):
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
        if node_state.startswith("drain"):
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

    # get dict and init infos
    cluster_info = get_cluster_info(info_lines)
    node_info = get_node_info(info_lines)  # type: dict

    device_accumulator = init_accumulator(cluster_info)
    node_accumulator = init_accumulator(node_info)

    stream = os.popen(
        'squeue -o "%6i %12j  %9T %12u %8g %15P %4D %20R %4C %13b %8m %11l %11L"'
    )
    output = stream.readlines()
    # lines = "".join(output[1:])
    # print(lines)
    lines = output[1:]
    for line in lines:
        splited = line.strip().split()
        name = splited[5]
        node = splited[7]
        if node[0] != "n":
            continue
        gpu_num = splited[9]
        cpu_num = splited[8]

        if gpu_num.startswith("gres/gpu"):
            gpu_num = gpu_num[-1]
        else:
            gpu_num = 0

        if name.startswith("cpu"):
            continue

        # for the case like n[16-17]
        nodes = [node]
        if (len(node.split("-")) >= 2) or (len(node.split(",")) >= 2):
            nodes = re.findall(r"\d+", node)  # reinit with node numbers
            nodes = ["n" + x for x in nodes]
        gpu_num = int(gpu_num) / len(nodes)
        cpu_num = int(cpu_num) / len(nodes)

        device_accumulator[name][0] += int(gpu_num)
        device_accumulator[name][1] += int(cpu_num)

        for node in nodes:
            node_accumulator[node][0] += int(gpu_num)
            node_accumulator[node][1] += int(cpu_num)

    print()
    print((bcolors.HEADER + "{:<15} {:<15} {:<15}" + bcolors.ENDC).format("GPU", "REMAIN", "CPU_REMAIN"))
    print("-" * 45)
    for (k, v) in cluster_info.items():
        gpu_remains = v[0] - device_accumulator[k][0]
        cpu_remains = v[1] - device_accumulator[k][1]
        gpu_len = len(str(gpu_remains) + "/")
        cpu_len = len(str(cpu_remains) + "/")
        if gpu_remains != 0:
            print((bcolors.OKGREEN + f"{k:<15} {gpu_remains}/{v[0]:<{15 - gpu_len}} {cpu_remains}/{v[1]:<{15 - cpu_len}}" + bcolors.ENDC))
        else:
            print((bcolors.FAIL + f"{k:<15} {gpu_remains}/{v[0]:<{15 - gpu_len}} {cpu_remains}/{v[1]:<{15 - cpu_len}}" + bcolors.ENDC))

    print()
    print(
        (bcolors.HEADER + "{:<15} {:<15} {:<15} {:<15}" + bcolors.ENDC).format(
            "NODE", "GPU", "REMAIN", "CPU_REMAIN"
        )
    )
    print("-" * 60)
    for (k, v) in node_info.items():
        gpu_remains = v["num"] - node_accumulator[k][0]
        cpu_remains = v["cpu_num"] - node_accumulator[k][1]
        gpu_len = len(str(gpu_remains) + "/")
        if args.all or gpu_remains != 0 :
            name = v["name"]
            num = v["num"]
            cpu_num = v["cpu_num"]
            
            if gpu_remains == 0:
                color = bcolors.FAIL
            elif cpu_remains == 0:
                color = bcolors.WARNING
            else:
                color = bcolors.OKGREEN
                
            print((color + f"{k:<15} {name:<15} {gpu_remains}/{num:<{15 - gpu_len}} {cpu_remains}/{cpu_num:<{15 - cpu_len}}" + bcolors.ENDC))

            # print(
            #     (bcolors.OKGREEN + "{:<15} {:<15} {:<15}" + bcolors.ENDC).format(
            #         k, v["name"], remains
            #     )
            # )
    print()
if __name__ == "__main__":
    main()
