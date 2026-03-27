#!/usr/bin/env bash
#SBATCH --job-name=kaiju_merge
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=2:00:00
#SBATCH --output=logs/kaiju_merge_%j.log
#SBATCH --error=logs/kaiju_merge_%j.log

# Merge per-database kaiju output files for a single sample into one
# gzip-compressed file: results_kaiju/SAMPLE/SAMPLE.kaiju.combined.gz
#
# The merged file preserves all columns from each per-DB file and prepends
# the database name as an extra column so origin is traceable:
#   <db_name>  <C|U>  <read_id>  <taxon_id>  <score>  <taxon_ids>  <accessions>  <matches>
#
# After merging, per-database raw files are removed to save space.
#
# Usage (typically submitted by 01_submit_kaiju.sh):
#   SAMPLE_ID=5MMH_5 sbatch 02_merge_kaiju.sh
#
# Or run manually:
#   bash 02_merge_kaiju.sh

set -euo pipefail

: "${SAMPLE_ID:?ERROR: SAMPLE_ID must be set}"

RESULTS_DIR="results_kaiju"
OUT_DIR="${RESULTS_DIR}/${SAMPLE_ID}"
COMBINED="${OUT_DIR}/${SAMPLE_ID}.kaiju.combined.gz"

echo "[$(date)] Merging kaiju results for ${SAMPLE_ID}"

shopt -s nullglob
DB_FILES=("${OUT_DIR}/${SAMPLE_ID}".*.kaiju.out)

if [[ "${#DB_FILES[@]}" -eq 0 ]]; then
    echo "ERROR: No .kaiju.out files found in ${OUT_DIR}/"
    exit 1
fi

echo "Found ${#DB_FILES[@]} per-database files:"
printf '  %s\n' "${DB_FILES[@]}"

# Stream all files through awk to prepend the db name, pipe into gzip
{
    for F in "${DB_FILES[@]}"; do
        # Extract db name from filename: SAMPLE.DBNAME.kaiju.out
        BASENAME=$(basename "${F}")
        DB_NAME="${BASENAME#${SAMPLE_ID}.}"
        DB_NAME="${DB_NAME%.kaiju.out}"
        awk -v db="${DB_NAME}" '{print db "\t" $0}' "${F}"
    done
} | gzip -c > "${COMBINED}"

echo "[$(date)] Combined file written: ${COMBINED}"
echo "  Size: $(du -h "${COMBINED}" | cut -f1)"
echo "  Lines (approx): $(zcat "${COMBINED}" | wc -l)"

# Remove per-database raw files to free disk space
echo "Removing per-database raw files..."
rm -f "${DB_FILES[@]}"
echo "[$(date)] Done."
