#!/usr/bin/bash -l
#SBATCH --job-name=qiimeITS_asv
#SBATCH --output=logs/qiimeITS_asv.%A.log
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --time=7-0:00:00
#SBATCH --mem=64G

set -euo pipefail

CPU=${SLURM_CPUS_PER_TASK:-1}
module load qiime2/2025.7-amplicon

# ------------------------------
# User-tunable settings
# ------------------------------
INPUT_DIR=${INPUT_DIR:-input/ITS}
OUTDIR=${OUTDIR:-qiime_ITS_ASV}
METADATA=${METADATA:-metadata/ITS_metadata.tsv}

# ITSxpress settings
ITS_REGION=${ITS_REGION:-ITS1}
ITS_TAXA=${ITS_TAXA:-F}
ITSXPRESS_CLUSTER_ID=${ITSXPRESS_CLUSTER_ID:-1.0}

# DADA2 settings
TRUNC_LEN_F=${TRUNC_LEN_F:-0}
TRUNC_LEN_R=${TRUNC_LEN_R:-0}
TRIM_LEFT_F=${TRIM_LEFT_F:-0}
TRIM_LEFT_R=${TRIM_LEFT_R:-0}

# Optional post-ASV clustering (e.g. 0.99). Leave unset to keep pure ASV output.
CLUSTER_IDENTITY=${CLUSTER_IDENTITY:-}

# UNITE database settings
UNITE_DB_DIR=${UNITE_DB_DIR:-/srv/projects/db/UNITE/qiime/2025-02-19}
UNITE_DB_VERSION=${UNITE_DB_VERSION:-ver10_dynamic_19.02.2025_dev}
UNITE_CLASSIFIER=${UNITE_CLASSIFIER:-${UNITE_DB_DIR}/${UNITE_DB_VERSION}-classifier.qza}
UNITE_TAXONOMY=${UNITE_TAXONOMY:-${UNITE_DB_DIR}/${UNITE_DB_VERSION}-taxonomy.qza}
UNITE_SEQS=${UNITE_SEQS:-${UNITE_DB_DIR}/${UNITE_DB_VERSION}-sequences.qza}

# Set RUN_BLAST_CLASSIFIER=1 to also run classify-consensus-blast in addition to sklearn.
RUN_BLAST_CLASSIFIER=${RUN_BLAST_CLASSIFIER:-0}

mkdir -p "$OUTDIR" "$OUTDIR/export" "$OUTDIR/01_import" "$OUTDIR/02_itsxpress" "$OUTDIR/03_dada2" "$OUTDIR/04_taxonomy"

if [ ! -d "$INPUT_DIR" ]; then
  echo "ERROR: Input directory not found: $INPUT_DIR"
  exit 1
fi

INPUT_DIR=$(realpath "$INPUT_DIR")
MANIFEST="$OUTDIR/manifest.tsv"
DEMUX_QZA="$OUTDIR/01_import/paired-end-demux.qza"
TRIMMED_QZA="$OUTDIR/02_itsxpress/trimmed_exact.qza"
TABLE_QZA="$OUTDIR/03_dada2/table.qza"
REP_SEQS_QZA="$OUTDIR/03_dada2/representative_sequences.qza"
STATS_QZA="$OUTDIR/03_dada2/denoising_stats.qza"

echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTDIR"
echo "Using CPUs: $CPU"

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
    echo "ERROR: UNITE sequence artifact not found: $UNITE_SEQS"
    exit 1
  fi
fi

if ! qiime info | grep -qi "itsxpress"; then
  echo "ERROR: q2-itsxpress plugin is not available in this QIIME2 environment"
  exit 1
fi

echo "Building manifest: $MANIFEST"
echo -e "sample-id\tforward-absolute-filepath\treverse-absolute-filepath" > "$MANIFEST"
for r1 in "$INPUT_DIR"/*_R1_001.fastq.gz; do
  [ -e "$r1" ] || continue
  r2=${r1/_R1_001.fastq.gz/_R2_001.fastq.gz}
  if [ ! -s "$r2" ]; then
    echo "WARNING: Missing R2 for $r1, skipping"
    continue
  fi

  base=$(basename "$r1")
  sample_id=${base%%_NoCode_L001_R1_001.fastq.gz}
  if [ "$sample_id" = "$base" ]; then
    sample_id=${base%%_R1_001.fastq.gz}
  fi

  echo -e "${sample_id}\t${r1}\t${r2}" >> "$MANIFEST"
done

if [ "$(wc -l < "$MANIFEST")" -le 1 ]; then
  echo "ERROR: Manifest has no samples: $MANIFEST"
  exit 1
fi

qiime tools import \
  --type 'SampleData[PairedEndSequencesWithQuality]' \
  --input-path "$MANIFEST" \
  --output-path "$DEMUX_QZA" \
  --input-format PairedEndFastqManifestPhred33V2

qiime demux summarize \
  --i-data "$DEMUX_QZA" \
  --o-visualization "$OUTDIR/01_import/demux-summary.qzv"

qiime itsxpress trim-pair-output-unmerged \
  --i-per-sample-sequences "$DEMUX_QZA" \
  --p-region "$ITS_REGION" \
  --p-taxa "$ITS_TAXA" \
  --p-cluster-id "$ITSXPRESS_CLUSTER_ID" \
  --p-threads "$CPU" \
  --o-trimmed "$TRIMMED_QZA" \
  --verbose

qiime demux summarize \
  --i-data "$TRIMMED_QZA" \
  --o-visualization "$OUTDIR/02_itsxpress/trimmed-summary.qzv"

qiime dada2 denoise-paired \
  --i-demultiplexed-seqs "$TRIMMED_QZA" \
  --p-trim-left-f "$TRIM_LEFT_F" \
  --p-trim-left-r "$TRIM_LEFT_R" \
  --p-trunc-len-f "$TRUNC_LEN_F" \
  --p-trunc-len-r "$TRUNC_LEN_R" \
  --p-n-threads "$CPU" \
  --output-dir "$OUTDIR/03_dada2"

if [ -s "$METADATA" ]; then
  qiime feature-table summarize \
    --i-table "$TABLE_QZA" \
    --o-visualization "$OUTDIR/03_dada2/table-summary.qzv" \
    --m-sample-metadata-file "$METADATA"
else
  echo "WARNING: Metadata file not found, table summary will not include metadata: $METADATA"
  qiime feature-table summarize \
    --i-table "$TABLE_QZA" \
    --o-visualization "$OUTDIR/03_dada2/table-summary.qzv"
fi

qiime feature-table tabulate-seqs \
  --i-data "$REP_SEQS_QZA" \
  --o-visualization "$OUTDIR/03_dada2/rep-seqs.qzv"

qiime metadata tabulate \
  --m-input-file "$STATS_QZA" \
  --o-visualization "$OUTDIR/03_dada2/denoising-stats.qzv"

TARGET_TABLE="$TABLE_QZA"
TARGET_REP_SEQS="$REP_SEQS_QZA"

if [ -n "$CLUSTER_IDENTITY" ]; then
  echo "Running optional ASV clustering with identity=$CLUSTER_IDENTITY"
  qiime vsearch cluster-features-de-novo \
    --i-table "$TABLE_QZA" \
    --i-sequences "$REP_SEQS_QZA" \
    --p-perc-identity "$CLUSTER_IDENTITY" \
    --o-clustered-table "$OUTDIR/03_dada2/table.clustered.qza" \
    --o-clustered-sequences "$OUTDIR/03_dada2/rep-seqs.clustered.qza"

  TARGET_TABLE="$OUTDIR/03_dada2/table.clustered.qza"
  TARGET_REP_SEQS="$OUTDIR/03_dada2/rep-seqs.clustered.qza"
fi

qiime feature-classifier classify-sklearn \
  --i-classifier "$UNITE_CLASSIFIER" \
  --i-reads "$TARGET_REP_SEQS" \
  --output-dir "$OUTDIR/04_taxonomy/sklearn"

qiime tools export \
  --input-path "$OUTDIR/04_taxonomy/sklearn/classification.qza" \
  --output-path "$OUTDIR/04_taxonomy/sklearn/export"

if [ "$RUN_BLAST_CLASSIFIER" = "1" ]; then
  qiime feature-classifier classify-consensus-blast \
    --i-query "$TARGET_REP_SEQS" \
    --i-reference-taxonomy "$UNITE_TAXONOMY" \
    --i-reference-reads "$UNITE_SEQS" \
    --output-dir "$OUTDIR/04_taxonomy/blast" \
    --p-perc-identity 0.8 \
    --p-maxaccepts 1 \
    --p-num-threads "$CPU"

  qiime tools export \
    --input-path "$OUTDIR/04_taxonomy/blast/classification.qza" \
    --output-path "$OUTDIR/04_taxonomy/blast/export"
fi

if [ -s "$METADATA" ]; then
  qiime taxa barplot \
    --i-table "$TARGET_TABLE" \
    --i-taxonomy "$OUTDIR/04_taxonomy/sklearn/classification.qza" \
    --m-metadata-file "$METADATA" \
    --o-visualization "$OUTDIR/04_taxonomy/taxa-barplot.sklearn.qzv"

  if [ "$RUN_BLAST_CLASSIFIER" = "1" ]; then
    qiime taxa barplot \
      --i-table "$TARGET_TABLE" \
      --i-taxonomy "$OUTDIR/04_taxonomy/blast/classification.qza" \
      --m-metadata-file "$METADATA" \
      --o-visualization "$OUTDIR/04_taxonomy/taxa-barplot.blast.qzv"
  fi
else
  echo "WARNING: Skipping taxa barplots because metadata file is missing: $METADATA"
fi

qiime tools export \
  --input-path "$TARGET_TABLE" \
  --output-path "$OUTDIR/export/table"

if command -v biom >/dev/null 2>&1; then
  biom convert \
    -i "$OUTDIR/export/table/feature-table.biom" \
    -o "$OUTDIR/export/table/feature-table.tsv" \
    --to-tsv
fi

qiime tools export \
  --input-path "$TARGET_REP_SEQS" \
  --output-path "$OUTDIR/export/rep_seqs"

qiime tools export \
  --input-path "$STATS_QZA" \
  --output-path "$OUTDIR/export/dada2_stats"

echo "Run complete. Key outputs:"
echo "  - ITSxpress-trimmed reads: $TRIMMED_QZA"
echo "  - DADA2 table: $TARGET_TABLE"
echo "  - DADA2 rep seqs: $TARGET_REP_SEQS"
echo "  - UNITE taxonomy (sklearn): $OUTDIR/04_taxonomy/sklearn/classification.qza"
if [ "$RUN_BLAST_CLASSIFIER" = "1" ]; then
  echo "  - UNITE taxonomy (blast): $OUTDIR/04_taxonomy/blast/classification.qza"
fi
