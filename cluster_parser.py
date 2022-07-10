import os


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
            cluster_info[gpu_name] = int(parsed[4]) * int(parsed[5][-1])
        else:
            cluster_info[gpu_name] += int(parsed[4]) * int(parsed[5][-1])

    return cluster_info


def get_node_info(lines):
    node_info = {}
    sorted_node_info = {}

    for line in lines[1:]:
        parsed = line.strip().split()
        gpu_name = parsed[0].strip("*")  # for 2080ti*
        gpu_num = int(parsed[5][-1])
        node_state = parsed[2]
        if gpu_name.startswith("cpu"):
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
                    "state": node_state,
                }

    sorted_keys = sorted(node_info, key=lambda x: int(x[1:]))
    for k in sorted_keys:
        sorted_node_info[k] = node_info[k]

    return sorted_node_info


def init_accumulator(info_dict):
    init_dict = {}
    for k in info_dict:
        init_dict[k] = 0
    return init_dict


if __name__ == "__main__":
    # to get dynmaic info_dicts
    info_stream = os.popen('sinfo   -o "%16P %14C  %6t %15N %5D %15G  %10m %11l %14f"')
    info_lines = info_stream.readlines()

    # get dict and init infos
    cluster_info = get_cluster_info(info_lines)
    node_info = get_node_info(info_lines)
    gpu_accumulator = init_accumulator(cluster_info)
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
        gpu_num = splited[9][-1]
        gpu_accumulator[name] += int(gpu_num)
        node_accumulator[node] += int(gpu_num)

    print()
    print((bcolors.HEADER + "{:<15} {:<15}" + bcolors.ENDC).format("GPU", "REMAIN"))
    print("-" * 30)
    for (k, v) in cluster_info.items():
        remains = v - gpu_accumulator[k]
        if remains != 0:
            print((bcolors.OKGREEN + "{:<15} {:<15}" + bcolors.ENDC).format(k, remains))
        else:
            print((bcolors.FAIL + "{:<15} {:<15}" + bcolors.ENDC).format(k, remains))

    print()
    print(
        (bcolors.HEADER + "{:<15} {:<15} {:<15}" + bcolors.ENDC).format(
            "NODE", "GPU", "REMAIN"
        )
    )
    print("-" * 45)
    for (k, v) in node_info.items():
        remains = v["num"] - node_accumulator[k]
        if remains != 0:
            print(
                (bcolors.OKGREEN + "{:<15} {:<15} {:<15}" + bcolors.ENDC).format(
                    k, v["name"], remains
                )
            )
    print()
