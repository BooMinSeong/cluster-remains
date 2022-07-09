squeue -o "%6i %12j  %9T %12u %8g %15P %4D %20R %4C %13b %8m %11l %11L" > ./cluster_state.txt

python ./cluster_parser.py