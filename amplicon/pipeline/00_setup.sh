#!/usr/bin/bash -l
#SBATCH -o logs/setup.log -p short -c 8 -n 1 -N 1 --mem 8gb

python scripts/setup_rename_fastq.py --config config.txt 