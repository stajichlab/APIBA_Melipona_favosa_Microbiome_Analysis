#!/usr/bin/env python3
"""
Generate QIIME2 manifest and metadata files from input/16S and input/ITS directories.
Outputs:
  manifests/16S_manifest.tsv
  manifests/ITS_manifest.tsv
  metadata/16S_metadata.tsv
  metadata/ITS_metadata.tsv
"""

import os
import re
import sys
from pathlib import Path

# Project root = one level up from this script
PROJECT_ROOT = Path(__file__).resolve().parent.parent
INPUT_ROOT   = PROJECT_ROOT / "input"
MANIFEST_DIR = PROJECT_ROOT / "manifests"
METADATA_DIR = PROJECT_ROOT / "metadata"

MANIFEST_DIR.mkdir(exist_ok=True)
METADATA_DIR.mkdir(exist_ok=True)


def parse_samples(amplicon: str) -> list[dict]:
    """
    Scan input/{amplicon}/ and pair R1/R2 files into sample records.
    Returns list of dicts with keys: sample_id, forward, reverse
    """
    indir = INPUT_ROOT / amplicon
    if not indir.exists():
        print(f"[WARNING] Directory not found: {indir}", file=sys.stderr)
        return []

    r1_files = sorted(indir.glob("*_R1_001.fastq.gz"))
    samples = []
    for r1 in r1_files:
        r2 = Path(str(r1).replace("_R1_001.fastq.gz", "_R2_001.fastq.gz"))
        if not r2.exists():
            print(f"[WARNING] Missing R2 for {r1.name}", file=sys.stderr)
            continue

        # Strip _16S_S{n} or _ITS_S{n} suffix to get biological sample ID
        stem = r1.name.replace("_R1_001.fastq.gz", "")
        sample_id = re.sub(rf"_{amplicon}_S\d+$", "", stem)

        samples.append({
            "sample_id": sample_id,
            "forward":   str(r1.resolve()),
            "reverse":   str(r2.resolve()),
        })
    return samples


def parse_metadata_fields(sample_id: str) -> dict:
    """
    Extract generic metadata fields from BeeGut sample IDs.
    Naming convention (as observed):
      B-{code1}-{code2}
    Groups identified:
      B-SVH{n}-Q{n}      → sample_group=SVH,  sample_type=queen_colony
      B-VEN-{well}        → sample_group=VEN,  sample_type=vendor
      B-{n}{loc}-{n}{suf} → sample_group=colony, infer H/P suffix
    """
    parts = sample_id.lstrip("B-").split("-")  # remove leading "B-"
    # re-split on the original id for clarity
    m = re.match(r"^B-([^-]+)-(.+)$", sample_id)
    if not m:
        return {
            "sample_group": "unknown",
            "location_code": "unknown",
            "sample_suffix": "unknown",
            "host": "Bee",
            "project": "BeeGut",
            "description": "BeeGut sample - metadata pending",
        }

    code1, code2 = m.group(1), m.group(2)

    # Vendor group
    if code1 == "VEN":
        return {
            "sample_group": "VEN",
            "location_code": code2,
            "sample_suffix": "NA",
            "host": "Bee",
            "project": "BeeGut",
            "description": "Vendor bee gut sample - metadata pending",
        }

    # SVH queen-colony group
    if code1.startswith("SVH"):
        num = re.sub(r"[^0-9]", "", code1)
        return {
            "sample_group": "SVH",
            "location_code": f"SVH{num}",
            "sample_suffix": "NA",
            "host": "Bee",
            "project": "BeeGut",
            "description": "SVH colony sample - metadata pending",
        }

    # Numbered colony samples – last letter(s) of code1 indicate type
    # e.g. 11SVH → loc=SVH, 11SVP → loc=SVP, 10PP → loc=PP
    num_prefix = re.match(r"^(\d+)(.*)$", code1)
    if num_prefix:
        num_part = num_prefix.group(1)
        loc_part = num_prefix.group(2) if num_prefix.group(2) else code1
        # H/P suffix convention (Hive vs Pollen, or other - TBD)
        suffix_match = re.search(r"([HP])$", loc_part)
        suffix = suffix_match.group(1) if suffix_match else "NA"
        loc_base = loc_part.rstrip("HP") if suffix != "NA" else loc_part
        return {
            "sample_group": f"colony_{num_part}",
            "location_code": loc_base if loc_base else loc_part,
            "sample_suffix": suffix,
            "host": "Bee",
            "project": "BeeGut",
            "description": "Colony bee gut sample - metadata pending",
        }

    # Fallback
    return {
        "sample_group": code1,
        "location_code": code2,
        "sample_suffix": "NA",
        "host": "Bee",
        "project": "BeeGut",
        "description": "BeeGut sample - metadata pending",
    }


METADATA_COLUMNS = [
    "sample-id", "sample_group", "location_code", "sample_suffix",
    "host", "project", "description",
]
# QIIME2 type directive row
QIIME2_TYPES = {
    "sample-id": "sample-id",
    "sample_group": "categorical",
    "location_code": "categorical",
    "sample_suffix": "categorical",
    "host": "categorical",
    "project": "categorical",
    "description": "categorical",
}


def write_manifest(samples: list[dict], path: Path) -> None:
    with open(path, "w") as fh:
        fh.write("sample-id\tforward-absolute-filepath\treverse-absolute-filepath\n")
        for s in samples:
            fh.write(f"{s['sample_id']}\t{s['forward']}\t{s['reverse']}\n")
    print(f"Wrote manifest: {path}  ({len(samples)} samples)")


def write_metadata(samples: list[dict], path: Path) -> None:
    rows = []
    for s in samples:
        fields = parse_metadata_fields(s["sample_id"])
        row = {"sample-id": s["sample_id"], **fields}
        rows.append(row)

    with open(path, "w") as fh:
        fh.write("\t".join(METADATA_COLUMNS) + "\n")
        fh.write("\t".join(QIIME2_TYPES[c] for c in METADATA_COLUMNS) + "\n")
        for row in rows:
            fh.write("\t".join(str(row.get(c, "NA")) for c in METADATA_COLUMNS) + "\n")
    print(f"Wrote metadata: {path}  ({len(rows)} samples)")


def main():
    for amplicon in ("16S", "ITS"):
        samples = parse_samples(amplicon)
        if not samples:
            print(f"[ERROR] No samples found for {amplicon}", file=sys.stderr)
            continue
        write_manifest(samples, MANIFEST_DIR / f"{amplicon}_manifest.tsv")
        write_metadata(samples, METADATA_DIR / f"{amplicon}_metadata.tsv")


if __name__ == "__main__":
    main()
