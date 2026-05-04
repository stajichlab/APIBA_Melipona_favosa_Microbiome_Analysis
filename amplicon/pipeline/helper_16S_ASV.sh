#!/usr/bin/bash -l

#SBATCH --time=14-0:00:00
#SBATCH -N 1 -n 1 -c 48
#SBATCH --mem=64gb
#SBATCH --out logs/ASV_vsearch.%A.log

set -euo pipefail

CPU=${SLURM_CPUS_ON_NODE:-2}
INPUT_DIR=${INPUT_DIR:-input/16S}
RUNNAME=${RUNNAME:-BEEHONEY_16S_ASV_$(date +'%Y%m%d')}
BASE=$RUNNAME

if [ ! -d "$INPUT_DIR" ]; then
  echo "ERROR: Input directory not found: $INPUT_DIR"
  exit 1
fi
INPUT_DIR=$(realpath "$INPUT_DIR")

module load amptk
module load usearch

mkdir -p "$BASE"
pushd "$BASE" >/dev/null

if [ ! -s "$BASE.demux.fq.gz" ]; then
  amptk illumina \
    -i "$INPUT_DIR" \
    --merge_method vsearch \
    -f 515FB \
    -r 806RB \
    --require_primer off \
    -o "$BASE" \
    --usearch usearch9 \
    --cpus "$CPU" \
    --rescue_forward on \
    --primer_mismatch 2 \
    -l 300 \
    --cleanup
fi

if [ ! -s "$BASE.otu_table.txt" ]; then
  amptk dada2 \
    -i "$BASE.demux.fq.gz" \
    -o "$BASE" \
    --uchime_ref 16S \
    --usearch usearch9 \
    -e 0.9 \
    --cpus "$CPU"
fi

if [ ! -s "$BASE.ASVs.taxonomy.txt" ]; then
  amptk taxonomy \
    -f "$BASE.ASVs.fa" \
    -i "$BASE.otu_table.txt" \
    -d 16S \
    -o "$BASE.ASVs"
fi

if [ -s "$BASE.cluster.otus.fa" ] && [ -s "$BASE.cluster.otu_table.txt" ] && [ ! -s "$BASE.cluster.taxonomy.txt" ]; then
  amptk taxonomy \
    -f "$BASE.cluster.otus.fa" \
    -i "$BASE.cluster.otu_table.txt" \
    -d 16S \
    -o "$BASE.cluster"
fi

popd >/dev/null
module unload usearch
module unload amptk

echo "Completed 16S ASV workflow in $BASE"
