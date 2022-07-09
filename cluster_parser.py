cluster_info = {
    "2080ti": 48,
    "TITANRTX": 4,
    "A100": 8,
    "4A100": 8,
    "A100-pci": 8,
    "A5000": 48,
    "A100-80GB": 16,
}

node_info = {
    "n1": {"name": "2080ti", "num": 8},
    "n2": {"name": "2080ti", "num": 8},
    "n3": {"name": "2080ti", "num": 8},
    "n4": {"name": "2080ti", "num": 8},
    "n5": {"name": "2080ti", "num": 8},
    "n6": {"name": "2080ti", "num": 8},
    "n7": {"name": "TITANRTX", "num": 4},
    "n8": {"name": "A100", "num": 8},
    "n9": {"name": "4A100", "num": 8},
    "n10": {"name": "A100-pci", "num": 4},
    "n11": {"name": "A100-pci", "num": 4},
    "n13": {"name": "A5000", "num": 8},
    "n14": {"name": "A5000", "num": 8},
    "n15": {"name": "A5000", "num": 8},
    "n16": {"name": "A5000", "num": 8},
    "n18": {"name": "A5000", "num": 8},
    "n17": {"name": "A5000", "num": 8},
    "n19": {"name": "A100-80GB", "num": 8},
    "n20": {"name": "A100-80GB", "num": 8},
}


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


if __name__ == "__main__":
    f = open("./cluster_state.txt", "r")
    lines = f.readlines()[1:]
    gpu_accumulator = {
        "2080ti": 0,
        "TITANRTX": 0,
        "A100": 0,
        "4A100": 0,
        "A100-pci": 0,
        "A5000": 0,
        "A100-80GB": 0,
    }
    node_accumulator = {
        "n1": 0,
        "n2": 0,
        "n3": 0,
        "n4": 0,
        "n5": 0,
        "n6": 0,
        "n7": 0,
        "n8": 0,
        "n9": 0,
        "n10": 0,
        "n11": 0,
        "n12": 0,
        "n13": 0,
        "n14": 0,
        "n15": 0,
        "n16": 0,
        "n18": 0,
        "n17": 0,
        "n19": 0,
        "n20": 0,
    }
    for line in lines:
        splited = line.strip().split()
        name = splited[5]
        node = splited[7]
        gpu_num = splited[9][-1]
        gpu_accumulator[name] += int(gpu_num)
        node_accumulator[node] += int(gpu_num)

    for (k, v) in cluster_info.items():
        remains = v - gpu_accumulator[k]
        if remains != 0:
            print(bcolors.OKGREEN, k, remains, "장 남음", bcolors.ENDC)
        else:
            print(bcolors.FAIL, k, remains, "장 남음", bcolors.ENDC)

    for (k, v) in node_info.items():
        remains = v["num"] - node_accumulator[k]
        if remains != 0:
            print(k, "node에", v["name"], remains, "장 남음")
