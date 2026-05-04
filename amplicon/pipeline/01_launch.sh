#!/usr/bin/bash -l
#SBATCH -p short --out logs/01_launch.log -n 1 -N 1 -c 1

set -euo pipefail

CONFIG_FILE=${CONFIG_FILE:-config.txt}
LAUNCH_AMPTK=${LAUNCH_AMPTK:-1}
LAUNCH_QIIME=${LAUNCH_QIIME:-1}

mkdir -p logs

if [ ! -s "$CONFIG_FILE" ]; then
  echo "Please create $CONFIG_FILE with at least FASTQSOURCE and METADATA"
  exit 1
fi

echo "Using configuration from $CONFIG_FILE"
# shellcheck disable=SC1090
source "$CONFIG_FILE"

if [ -z "${METADATA:-}" ] || [ ! -s "${METADATA}" ]; then
  echo "Please set METADATA in $CONFIG_FILE to an existing metadata TSV"
  exit 1
fi

# Default metadata files used by QIIME helpers; can be overridden in config.txt.
METADATA_16S=${METADATA_16S:-metadata/16S_metadata.tsv}
METADATA_ITS=${METADATA_ITS:-metadata/ITS_metadata.tsv}

echo "Launch settings:"
echo "  LAUNCH_AMPTK=$LAUNCH_AMPTK"
echo "  LAUNCH_QIIME=$LAUNCH_QIIME"
echo "  METADATA=$METADATA"
echo "  METADATA_16S=$METADATA_16S"
echo "  METADATA_ITS=$METADATA_ITS"

submit_job() {
  local script=$1
  local jobname=$2
  local logfile=$3
  local exports=$4

  sbatch --export="$exports" -o "$logfile" -J "$jobname" "$script"
}

if [ "$LAUNCH_AMPTK" = "1" ]; then
  echo "Submitting AMPTK jobs"

  RUNNAME=BEEHONEY_16S_ASV
  submit_job \
    "pipeline/helper_16S_ASV.sh" \
    "16S_ASV" \
    "logs/16S_ASV.log" \
    "ALL,RUNNAME=$RUNNAME"

  RUNNAME=BEEHONEY_ITS_OTU
  ITS_OTU_SUBMIT=$(submit_job \
    "pipeline/helper_ITS_OTU.sh" \
    "ITS_OTU" \
    "logs/ITS_OTU.log" \
    "ALL,RUNNAME=$RUNNAME")
  ITS_OTU_JOBID=$(echo "$ITS_OTU_SUBMIT" | awk '{print $4}')

  # Keep ITS ASV after ITS OTU to avoid resource contention in shared environments.
  RUNNAME=BEEHONEY_ITS_ASV
  sbatch --dependency="afterok:${ITS_OTU_JOBID}" \
    --export="ALL,RUNNAME=$RUNNAME" \
    -o "logs/ITS_ASV.log" \
    -J "ITS_ASV" \
    "pipeline/helper_ITS_ASV.sh"
fi

if [ "$LAUNCH_QIIME" = "1" ]; then
  echo "Submitting QIIME jobs"

  submit_job \
    "pipeline/helper_qiime_16S_ASV.sh" \
    "q2_16S_ASV" \
    "logs/qiime_16S_ASV.log" \
    "ALL,METADATA=$METADATA_16S"

  submit_job \
    "pipeline/helper_qiime_ITS_ASV.sh" \
    "q2_ITS_ASV" \
    "logs/qiime_ITS_ASV.log" \
    "ALL,METADATA=$METADATA_ITS"
fi

echo "Launch complete"
