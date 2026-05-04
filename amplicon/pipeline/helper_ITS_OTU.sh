#!/usr/bin/bash -l

#SBATCH --time=4-0:00:00
#SBATCH -N 1 -n 1 -c 48
#SBATCH --mem=96gb
#SBATCH --out logs/amptk_OTU_vsearch.%A.log

set -euo pipefail

CPU=${SLURM_CPUS_ON_NODE:-2}
INPUT_DIR=${INPUT_DIR:-input/ITS}
RUNNAME=${RUNNAME:-BEEHONEY_ITS_OTU_$(date +'%Y%m%d')}
BASE=$RUNNAME

UNITE_DB_DIR=${UNITE_DB_DIR:-/srv/projects/db/UNITE/qiime/2025-02-19}
UNITE_DB_VERSION=${UNITE_DB_VERSION:-ver10_dynamic_19.02.2025_dev}
UNITE_CLASSIFIER=${UNITE_CLASSIFIER:-${UNITE_DB_DIR}/${UNITE_DB_VERSION}-classifier.qza}
UNITE_TAXONOMY=${UNITE_TAXONOMY:-${UNITE_DB_DIR}/${UNITE_DB_VERSION}-taxonomy.qza}
UNITE_SEQS=${UNITE_SEQS:-${UNITE_DB_DIR}/${UNITE_DB_VERSION}-sequences.qza}

RUN_QIIME_CLASSIFIERS=${RUN_QIIME_CLASSIFIERS:-1}
RUN_BLAST_CLASSIFIER=${RUN_BLAST_CLASSIFIER:-1}

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
    -f ITS1-F \
    -r ITS2 \
    --require_primer off \
    -o "$BASE" \
    --usearch usearch9 \
    --rescue_forward on \
    --primer_mismatch 2 \
    -l 250 \
    --cpus "$CPU" \
    --cleanup
fi

if [ ! -s "$BASE.otu_table.txt" ]; then
  amptk cluster \
    -i "$BASE.demux.fq.gz" \
    -o "$BASE" \
    --uchime_ref ITS \
    --usearch usearch9 \
    -e 0.9 \
    --cpus "$CPU"
fi

if [ ! -s "$BASE.cluster.taxonomy.txt" ]; then
  amptk taxonomy \
    -f "$BASE.cluster.otus.fa" \
    -i "$BASE.otu_table.txt" \
    -d ITS1 \
    -o "$BASE.cluster"
fi

module unload usearch
module unload amptk

if [ "$RUN_QIIME_CLASSIFIERS" = "1" ]; then
  module load qiime2/2025.7-amplicon

  if [ ! -s "$UNITE_CLASSIFIER" ]; then
    echo "ERROR: UNITE classifier not found: $UNITE_CLASSIFIER"
    exit 1
  fi

  if [ "$RUN_BLAST_CLASSIFIER" = "1" ]; then
    if [ ! -s "$UNITE_TAXONOMY" ]; then
      echo "ERROR: UNITE taxonomy artifact not found: $UNITE_TAXONOMY"
      exit 1
    fi
    if [ ! -s "$UNITE_SEQS" ]; then
      echo "ERROR: UNITE sequences artifact not found: $UNITE_SEQS"
      exit 1
    fi
  fi

  if [ ! -s "$BASE.cluster.otus.uc.fa" ] || [ "$BASE.cluster.otus.fa" -nt "$BASE.cluster.otus.uc.fa" ]; then
    perl -pe 'tr/a-z/A-Z/' "$BASE.cluster.otus.fa" > "$BASE.cluster.otus.uc.fa"
  fi

  if [ ! -s "$BASE.cluster.otus.qza" ] || [ "$BASE.cluster.otus.uc.fa" -nt "$BASE.cluster.otus.qza" ]; then
    qiime tools import \
      --input-path "$BASE.cluster.otus.uc.fa" \
      --output-path "$BASE.cluster.otus.qza" \
      --type 'FeatureData[Sequence]'
  fi

  OTU_SK_DIR="./$BASE.OTUs_taxonomy_bayesianclassifier"
  if [ ! -s "$OTU_SK_DIR/classification.qza" ]; then
    qiime feature-classifier classify-sklearn \
      --i-classifier "$UNITE_CLASSIFIER" \
      --i-reads "$BASE.cluster.otus.qza" \
      --output-dir "$OTU_SK_DIR"
  fi

  if [ ! -s "$OTU_SK_DIR/export/taxonomy.tsv" ]; then
    qiime tools export \
      --input-path "$OTU_SK_DIR/classification.qza" \
      --output-path "$OTU_SK_DIR/export"
  fi

  module load amptk
  amptk taxonomy \
    -f "$BASE.cluster.otus.fa" \
    -i "$BASE.otu_table.txt" \
    -t "$OTU_SK_DIR/export/taxonomy.tsv" \
    -o "$BASE.cluster.otus.qiime_bayesian_taxonomy" \
    --cpus "$CPU" \
    --db ITS1
  module unload amptk

  if [ "$RUN_BLAST_CLASSIFIER" = "1" ]; then
    OTU_BL_DIR="./$BASE.OTUs_taxonomy_BLAST"
    if [ ! -s "$OTU_BL_DIR/classification.qza" ]; then
      qiime feature-classifier classify-consensus-blast \
        --i-query "$BASE.cluster.otus.qza" \
        --i-reference-taxonomy "$UNITE_TAXONOMY" \
        --i-reference-reads "$UNITE_SEQS" \
        --output-dir "$OTU_BL_DIR" \
        --p-perc-identity 0.80 \
        --p-maxaccepts 1 \
        --p-num-threads "$CPU"
    fi

    if [ ! -s "$OTU_BL_DIR/export/taxonomy.tsv" ]; then
      qiime tools export \
        --input-path "$OTU_BL_DIR/classification.qza" \
        --output-path "$OTU_BL_DIR/export"
    fi

    module load amptk
    amptk taxonomy \
      -f "$BASE.cluster.otus.fa" \
      -i "$BASE.otu_table.txt" \
      -t "$OTU_BL_DIR/export/taxonomy.tsv" \
      -o "$BASE.cluster.otus.qiime_blast_taxonomy" \
      --cpus "$CPU" \
      --db ITS1
    module unload amptk
  fi
fi

popd >/dev/null

echo "Completed ITS OTU workflow in $BASE"
