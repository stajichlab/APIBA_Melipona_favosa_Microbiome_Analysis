#!/bin/bash
# run_microbiome_plots.sh
# Wrapper to run microbiome_plots.R for all amptk result folders.
#
# Usage:
#   bash scripts/run_microbiome_plots.sh             # run all auto-detected folders
#   bash scripts/run_microbiome_plots.sh BEEHONEY_16S_ASV  # run a single folder
#
# Requirements (R packages):
#   CRAN:   optparse phyloseq vegan ggplot2 dplyr tidyr tibble
#           patchwork RColorBrewer scales ggrepel
#   GitHub: KasperSkytte/microshade  (optional – installed automatically)
#
# The script assumes it is run from the amplicon/ project root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(dirname "$SCRIPT_DIR")"
R_SCRIPT="${SCRIPT_DIR}/microbiome_plots.R"
METADATA_DIR="${PROJ_ROOT}/metadata"

# ---------- locate amptk result folders -------------------------------------
if [[ $# -gt 0 ]]; then
  INPUT_FOLDERS=("$@")
else
  # Auto-detect: any directory matching BEEHONEY_*
  mapfile -t INPUT_FOLDERS < <(find "$PROJ_ROOT" -maxdepth 1 -type d -name 'BEEHONEY_*' | sort)
fi

if [[ ${#INPUT_FOLDERS[@]} -eq 0 ]]; then
  echo "No input folders found. Provide folder names as arguments or run from amplicon/ root."
  exit 1
fi

echo "Found ${#INPUT_FOLDERS[@]} folder(s) to process:"
printf '  %s\n' "${INPUT_FOLDERS[@]}"
echo ""

# ---------- select matching metadata ----------------------------------------
get_metadata() {
  local folder="$1"
  if echo "$folder" | grep -qi "16S"; then
    echo "${METADATA_DIR}/16S_metadata.tsv"
  elif echo "$folder" | grep -qi "ITS"; then
    echo "${METADATA_DIR}/ITS_metadata.tsv"
  else
    # Fall back: first metadata file found
    find "$METADATA_DIR" -name "*.tsv" | head -1
  fi
}

# ---------- SLURM or local? --------------------------------------------------
if command -v sbatch &>/dev/null; then
  USE_SLURM=true
  echo "SLURM detected – submitting jobs."
else
  USE_SLURM=false
  echo "No SLURM – running locally."
fi

# ---------- process each folder ---------------------------------------------
for INPUT in "${INPUT_FOLDERS[@]}"; do
  FOLDER_NAME="$(basename "$INPUT")"
  METADATA="$(get_metadata "$FOLDER_NAME")"

  if [[ ! -f "$METADATA" ]]; then
    echo "  [WARN] No metadata for $FOLDER_NAME – skipping."
    continue
  fi

  OUTDIR="${PROJ_ROOT}/results/${FOLDER_NAME}_plots"
  mkdir -p "$OUTDIR"

  CMD="Rscript ${R_SCRIPT} \
    --input    ${INPUT} \
    --metadata ${METADATA} \
    --outdir   ${OUTDIR} \
    --min_reads 1000 \
    --top_taxa  15"

  echo "-----------------------------------------------------------------------"
  echo "Input   : $INPUT"
  echo "Metadata: $METADATA"
  echo "Output  : $OUTDIR"

  if $USE_SLURM; then
    LOG_DIR="${PROJ_ROOT}/logs"
    mkdir -p "$LOG_DIR"
    sbatch --job-name="microbiome_${FOLDER_NAME}" \
           --output="${LOG_DIR}/${FOLDER_NAME}_plots_%j.log" \
           --time=2:00:00 \
           --mem=16G -p short \
           --cpus-per-task=4 \
           --wrap="$CMD"
  else
    echo "Running: $CMD"
    eval "$CMD"
  fi
done

echo ""
echo "All jobs submitted/completed."
