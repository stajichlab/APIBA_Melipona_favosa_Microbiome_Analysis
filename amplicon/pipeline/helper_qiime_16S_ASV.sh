#!/usr/bin/bash -l
#SBATCH --job-name=qiime16S_asv
#SBATCH --output=logs/qiime16S_asv.%A.log
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
INPUT_DIR=${INPUT_DIR:-input/16S}
OUTDIR=${OUTDIR:-qiime_16S_ASV}
METADATA=${METADATA:-metadata/16S_metadata.tsv}
TRUNC_LEN_F=${TRUNC_LEN_F:-0}
TRUNC_LEN_R=${TRUNC_LEN_R:-0}
TRIM_LEFT_F=${TRIM_LEFT_F:-0}
TRIM_LEFT_R=${TRIM_LEFT_R:-0}

# Optional post-ASV clustering (e.g. 0.99). Leave unset to keep pure ASV output.
CLUSTER_IDENTITY=${CLUSTER_IDENTITY:-}

# Greengenes2 inputs (defaulting to md5 namespace; works well with DADA2 feature IDs)
GG2_VERSION=${GG2_VERSION:-2024.09}
GG2_DB_DIR=${GG2_DB_DIR:-/srv/projects/db/greengenes2}
GG2_TAXONOMY=${GG2_TAXONOMY:-${GG2_DB_DIR}/${GG2_VERSION}.taxonomy.md5.tsv.qza}
GG2_TREE=${GG2_TREE:-${GG2_DB_DIR}/${GG2_VERSION}.phylogeny.md5.nwk.qza}

mkdir -p "$OUTDIR" "$OUTDIR/export" "$OUTDIR/01_import" "$OUTDIR/02_dada2" "$OUTDIR/03_taxonomy"

if [ ! -d "$INPUT_DIR" ]; then
  echo "ERROR: Input directory not found: $INPUT_DIR"
  exit 1
fi

INPUT_DIR=$(realpath "$INPUT_DIR")
MANIFEST="$OUTDIR/manifest.tsv"
DEMUX_QZA="$OUTDIR/01_import/paired-end-demux.qza"
TABLE_QZA="$OUTDIR/02_dada2/table.qza"
REP_SEQS_QZA="$OUTDIR/02_dada2/representative_sequences.qza"
STATS_QZA="$OUTDIR/02_dada2/denoising_stats.qza"

echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTDIR"
echo "Using CPUs: $CPU"

if [ ! -s "$GG2_TAXONOMY" ]; then
  echo "ERROR: Greengenes2 taxonomy artifact not found: $GG2_TAXONOMY"
  exit 1
fi

if [ ! -s "$GG2_TREE" ]; then
  echo "ERROR: Greengenes2 tree artifact not found: $GG2_TREE"
  exit 1
fi

if ! qiime info | grep -qi "greengenes2"; then
  echo "ERROR: q2-greengenes2 plugin is not available in this QIIME2 environment"
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

qiime dada2 denoise-paired \
  --i-demultiplexed-seqs "$DEMUX_QZA" \
  --p-trim-left-f "$TRIM_LEFT_F" \
  --p-trim-left-r "$TRIM_LEFT_R" \
  --p-trunc-len-f "$TRUNC_LEN_F" \
  --p-trunc-len-r "$TRUNC_LEN_R" \
  --p-n-threads "$CPU" \
  --output-dir "$OUTDIR/02_dada2"

if [ -s "$METADATA" ]; then
  qiime feature-table summarize \
    --i-table "$TABLE_QZA" \
    --o-visualization "$OUTDIR/02_dada2/table-summary.qzv" \
    --m-sample-metadata-file "$METADATA"
else
  echo "WARNING: Metadata file not found, table summary will not include metadata: $METADATA"
  qiime feature-table summarize \
    --i-table "$TABLE_QZA" \
    --o-visualization "$OUTDIR/02_dada2/table-summary.qzv"
fi

qiime feature-table tabulate-seqs \
  --i-data "$REP_SEQS_QZA" \
  --o-visualization "$OUTDIR/02_dada2/rep-seqs.qzv"

TARGET_TABLE="$TABLE_QZA"
TARGET_REP_SEQS="$REP_SEQS_QZA"

if [ -n "$CLUSTER_IDENTITY" ]; then
  echo "Running optional ASV clustering with identity=$CLUSTER_IDENTITY"
  qiime vsearch cluster-features-de-novo \
    --i-table "$TABLE_QZA" \
    --i-sequences "$REP_SEQS_QZA" \
    --p-perc-identity "$CLUSTER_IDENTITY" \
    --o-clustered-table "$OUTDIR/02_dada2/table.clustered.qza" \
    --o-clustered-sequences "$OUTDIR/02_dada2/rep-seqs.clustered.qza"

  TARGET_TABLE="$OUTDIR/02_dada2/table.clustered.qza"
  TARGET_REP_SEQS="$OUTDIR/02_dada2/rep-seqs.clustered.qza"
fi

qiime greengenes2 taxonomy-from-table \
  --i-reference-taxonomy "$GG2_TAXONOMY" \
  --i-table "$TARGET_TABLE" \
  --o-classification "$OUTDIR/03_taxonomy/classification.gg2.qza"

qiime greengenes2 taxonomy-from-features \
  --i-reference-taxonomy "$GG2_TAXONOMY" \
  --i-reads "$TARGET_REP_SEQS" \
  --o-classification "$OUTDIR/03_taxonomy/classification.gg2.from_features.qza"

qiime greengenes2 filter-features \
  --i-feature-table "$TARGET_TABLE" \
  --i-reference "$GG2_TREE" \
  --o-filtered-table "$OUTDIR/03_taxonomy/table.gg2.filtered.qza"

qiime tools export \
  --input-path "$OUTDIR/03_taxonomy/classification.gg2.qza" \
  --output-path "$OUTDIR/03_taxonomy/export"

qiime feature-table filter-seqs \
  --i-data "$TARGET_REP_SEQS" \
  --i-table "$OUTDIR/03_taxonomy/table.gg2.filtered.qza" \
  --o-filtered-data "$OUTDIR/03_taxonomy/rep-seqs.gg2.filtered.qza"

if [ -s "$METADATA" ]; then
  qiime taxa barplot \
    --i-table "$TARGET_TABLE" \
    --i-taxonomy "$OUTDIR/03_taxonomy/classification.gg2.qza" \
    --m-metadata-file "$METADATA" \
    --o-visualization "$OUTDIR/03_taxonomy/taxa-barplot.gg2.qzv"
else
  echo "WARNING: Skipping taxa barplot because metadata file is missing: $METADATA"
fi

qiime tools export \
  --input-path "$TARGET_TABLE" \
  --output-path "$OUTDIR/export/table"

qiime tools export \
  --input-path "$TARGET_REP_SEQS" \
  --output-path "$OUTDIR/export/rep_seqs"

qiime tools export \
  --input-path "$STATS_QZA" \
  --output-path "$OUTDIR/export/dada2_stats"

echo "Run complete. Key outputs:"
echo "  - DADA2 table: $TARGET_TABLE"
echo "  - DADA2 rep seqs: $TARGET_REP_SEQS"
echo "  - Greengenes2 taxonomy: $OUTDIR/03_taxonomy/classification.gg2.qza"
echo "  - Taxa barplot: $OUTDIR/03_taxonomy/taxa-barplot.gg2.qzv"

