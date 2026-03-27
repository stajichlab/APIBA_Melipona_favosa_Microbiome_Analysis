#!/usr/bin/env bash
#SBATCH --job-name=kaiju_report
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=2:00:00
#SBATCH --output=logs/kaiju_report_%j.log
#SBATCH --error=logs/kaiju_report_%j.log

# Generate per-sample taxonomic summary reports from combined kaiju output.
# Calls kaiju_report.py which produces:
#   results_kaiju/SAMPLE/SAMPLE.kaiju_report.tsv  — per-db + combined summary
#
# Usage (submitted by 03_submit_reports.sh):
#   SAMPLE_ID=5MMH_5 sbatch run_kaiju_report.sh

set -euo pipefail

: "${SAMPLE_ID:?ERROR: SAMPLE_ID must be set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="results_kaiju"
KAIJU_TAX_DIR="/srv/projects/db/kaiju/20260128/kaiju_nr_cluster/taxonomy"

module load kaiju/1.10.1

echo "[$(date)] Generating report for ${SAMPLE_ID}"

python3 "${SCRIPT_DIR}/kaiju_report.py" \
    --sample    "${SAMPLE_ID}" \
    --results   "${RESULTS_DIR}" \
    --taxdir    "${KAIJU_TAX_DIR}" \
    --threads   "${SLURM_CPUS_PER_TASK:-4}"

echo "[$(date)] Done."
