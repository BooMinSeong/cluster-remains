#!/bin/sh
#SBATCH -J dummy
#SBATCH -p 4A100
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -e train.err
#SBATCH -o train.out
#SBATCH --time 3-00:00:00
#SBATCH --gres=gpu:8