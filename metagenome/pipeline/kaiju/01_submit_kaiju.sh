#!/usr/bin/env bash
# Submit one SLURM array job per sample × database combination.
# After all classification jobs complete, submits merge jobs (one per sample)
# that depend on the array jobs finishing.
#
# Usage:
#   cd /bigdata/stajichlab/shared/projects/BeeGut/metagenome
#   bash pipeline/kaiju/01_submit_kaiju.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SAMPLES_CSV="${PROJECT_DIR}/samples.csv"
KAIJU_DB_DIR="/srv/projects/db/kaiju/20260128/kaiju_nr_cluster/kaiju_indexes"
JOBS_TSV="${PROJECT_DIR}/logs/kaiju_jobs.tsv"
DRY_RUN=0

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

mkdir -p "${PROJECT_DIR}/logs"

# ── Collect databases ─────────────────────────────────────────────────────────
mapfile -t DATABASES < <(ls "${KAIJU_DB_DIR}"/*.fmi | xargs -n1 basename | sed 's/\.fmi$//')
echo "Found ${#DATABASES[@]} databases: ${DATABASES[*]}"

# ── Build jobs table (sample_id TAB db_name TAB read_pattern) ─────────────────
# Skip header line of CSV
> "${JOBS_TSV}"
while IFS=',' read -r SAMPLE_ID READ_PATTERN; do
    [[ "${SAMPLE_ID}" == "sample" ]] && continue   # skip CSV header
    [[ -z "${SAMPLE_ID}" ]]          && continue   # skip blank lines
    for DB in "${DATABASES[@]}"; do
        printf '%s\t%s\t%s\n' "${SAMPLE_ID}" "${DB}" "${READ_PATTERN}" >> "${JOBS_TSV}"
    done
done < "${SAMPLES_CSV}"

NUM_JOBS=$(wc -l < "${JOBS_TSV}")
echo "Total jobs (sample × db): ${NUM_JOBS}"

if [[ "${NUM_JOBS}" -eq 0 ]]; then
    echo "ERROR: No jobs generated. Check ${SAMPLES_CSV} and ${KAIJU_DB_DIR}."
    exit 1
fi

ARRAY_END=$((NUM_JOBS - 1))

# ── Submit classification array job ──────────────────────────────────────────
if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] Would submit array 0-${ARRAY_END} with JOBS_TSV=${JOBS_TSV}"
    CLASSIFY_JOB_ID="DRY_RUN"
else
    CLASSIFY_JOB_ID=$(sbatch \
        --array="0-${ARRAY_END}" \
        --export=JOBS_TSV="${JOBS_TSV}" \
        --parsable \
        "${SCRIPT_DIR}/run_kaiju_classify.sh")
    echo "Submitted classification array job: ${CLASSIFY_JOB_ID}"
fi

# ── Submit one merge job per sample, dependent on classify array completion ───
while IFS=',' read -r SAMPLE_ID READ_PATTERN; do
    [[ "${SAMPLE_ID}" == "sample" ]] && continue
    [[ -z "${SAMPLE_ID}" ]]          && continue

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "[dry-run] Would submit merge for ${SAMPLE_ID} after job ${CLASSIFY_JOB_ID}"
    else
        MERGE_JOB_ID=$(sbatch \
            --job-name="kaiju_merge_${SAMPLE_ID}" \
            --dependency="afterok:${CLASSIFY_JOB_ID}" \
            --export=SAMPLE_ID="${SAMPLE_ID}" \
            --parsable \
            "${SCRIPT_DIR}/02_merge_kaiju.sh")
        echo "Submitted merge job for ${SAMPLE_ID}: ${MERGE_JOB_ID}"
    fi
done < "${SAMPLES_CSV}"
