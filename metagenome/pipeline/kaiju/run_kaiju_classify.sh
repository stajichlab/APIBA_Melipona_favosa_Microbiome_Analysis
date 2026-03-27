#!/usr/bin/env bash
#SBATCH --job-name=kaiju_classify
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=64G
#SBATCH --time=2:00:00
#SBATCH --output=logs/kaiju_classify_%A_%a.log
#SBATCH --error=logs/kaiju_classify_%A_%a.log

# Generic kaiju classification script for one sample against one database.
# Submit via 01_submit_kaiju.sh which builds the jobs.tsv and calls sbatch --array.
#
# Usage (called via sbatch array, reads JOBS_TSV env var):
#   sbatch --array=0-N --export=JOBS_TSV=... run_kaiju_classify.sh
#
# Or run a single pair directly:
#   SAMPLE_ID=5MMH_5 DB_NAME=Bacteria JOBS_TSV="" sbatch run_kaiju_classify.sh

set -euo pipefail

module load kaiju/1.10.1

KAIJU_DB_DIR="/srv/projects/db/kaiju/20260128/kaiju_nr_cluster/kaiju_indexes"
KAIJU_TAX_DIR="/srv/projects/db/kaiju/20260128/kaiju_nr_cluster/taxonomy"
INPUT_DIR="input"
RESULTS_DIR="results_kaiju"
SAMPLES_CSV="samples.csv"

# ── Resolve sample and database from array index or env vars ─────────────────
if [[ -n "${SLURM_ARRAY_TASK_ID:-}" && -n "${JOBS_TSV:-}" ]]; then
    LINE=$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" "${JOBS_TSV}")
    SAMPLE_ID=$(echo "${LINE}" | cut -f1)
    DB_NAME=$(echo   "${LINE}" | cut -f2)
    READ_PATTERN=$(echo "${LINE}" | cut -f3)
elif [[ -n "${SAMPLE_ID:-}" && -n "${DB_NAME:-}" && -n "${READ_PATTERN:-}" ]]; then
    : # already set via environment
else
    echo "ERROR: Must set JOBS_TSV + SLURM_ARRAY_TASK_ID, or SAMPLE_ID + DB_NAME + READ_PATTERN."
    exit 1
fi

echo "Sample:   ${SAMPLE_ID}"
echo "Database: ${DB_NAME}"
echo "Pattern:  ${READ_PATTERN}"

# ── Locate reads ──────────────────────────────────────────────────────────────
R1=$(ls "${INPUT_DIR}"/${READ_PATTERN/\?/1} 2>/dev/null | head -1)
R2=$(ls "${INPUT_DIR}"/${READ_PATTERN/\?/2} 2>/dev/null | head -1)

if [[ -z "${R1}" || -z "${R2}" ]]; then
    echo "ERROR: Could not find R1/R2 files matching ${READ_PATTERN} in ${INPUT_DIR}/"
    exit 1
fi

echo "R1: ${R1}"
echo "R2: ${R2}"

# ── Set up output directory ───────────────────────────────────────────────────
OUT_DIR="${RESULTS_DIR}/${SAMPLE_ID}"
mkdir -p "${OUT_DIR}"

DB_FMI="${KAIJU_DB_DIR}/${DB_NAME}.fmi"
OUT_FILE="${OUT_DIR}/${SAMPLE_ID}.${DB_NAME}.kaiju.out"

if [[ ! -f "${DB_FMI}" ]]; then
    echo "ERROR: Database index not found: ${DB_FMI}"
    exit 1
fi

# ── Run kaiju ─────────────────────────────────────────────────────────────────
echo "[$(date)] Starting kaiju against ${DB_NAME}"
kaiju \
    -t "${KAIJU_TAX_DIR}/nodes.dmp" \
    -f "${DB_FMI}" \
    -i "${R1}" \
    -j "${R2}" \
    -z "${SLURM_CPUS_PER_TASK:-8}" \
    -o "${OUT_FILE}" \
    -v

echo "[$(date)] Finished: ${OUT_FILE}"
