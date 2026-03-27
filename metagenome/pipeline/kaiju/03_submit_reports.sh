#!/usr/bin/env bash
# Submit kaiju report jobs — one per sample — after merging is complete.
# Can be run manually after 01_submit_kaiju.sh finishes, or chained via
# --dependency on the merge jobs.
#
# Usage:
#   cd /bigdata/stajichlab/shared/projects/BeeGut/metagenome
#   bash pipeline/kaiju/03_submit_reports.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SAMPLES_CSV="${PROJECT_DIR}/samples.csv"
DRY_RUN=0

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

while IFS=',' read -r SAMPLE_ID READ_PATTERN; do
    [[ "${SAMPLE_ID}" == "sample" ]] && continue
    [[ -z "${SAMPLE_ID}" ]]          && continue

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "[dry-run] Would submit report for ${SAMPLE_ID}"
    else
        JOB_ID=$(sbatch \
            --job-name="kaiju_report_${SAMPLE_ID}" \
            --export=SAMPLE_ID="${SAMPLE_ID}" \
            --parsable \
            "${SCRIPT_DIR}/run_kaiju_report.sh")
        echo "Submitted report job for ${SAMPLE_ID}: ${JOB_ID}"
    fi
done < "${SAMPLES_CSV}"
