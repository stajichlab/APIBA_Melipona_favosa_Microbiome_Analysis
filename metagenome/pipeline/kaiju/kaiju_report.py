#!/usr/bin/env python3
"""
kaiju_report.py — Generate taxonomic summary reports for a single sample.

Reads the combined gzip kaiju file produced by 02_merge_kaiju.sh:
    results_kaiju/SAMPLE/SAMPLE.kaiju.combined.gz

The combined file has columns (tab-separated):
    db_name  status  read_id  taxon_id  score  taxon_ids  accessions  matches

Produces two output files in results_kaiju/SAMPLE/:
    SAMPLE.kaiju_report.tsv     — per-database classified/unclassified counts
    SAMPLE.kaiju_taxonomy.tsv   — taxonomic read counts per taxon (all dbs merged)

It also runs kaiju2table (if available) via subprocess on extracted per-db
temporary files to generate lineage-aware tables at species/genus/family levels.

Usage:
    python3 kaiju_report.py --sample 5MMH_5 --results results_kaiju \
        --taxdir /srv/projects/db/kaiju/20260128/kaiju_nr_cluster/taxonomy
"""

import argparse
import collections
import gzip
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--sample",  required=True,  help="Sample ID")
    p.add_argument("--results", default="results_kaiju", help="Results root directory")
    p.add_argument("--taxdir",  required=True,
                   help="Directory containing nodes.dmp and names.dmp")
    p.add_argument("--threads", type=int, default=4,
                   help="Threads for kaiju2table (if available)")
    p.add_argument("--ranks",   nargs="+",
                   default=["species", "genus", "family", "order", "class", "phylum"],
                   help="Taxonomic ranks to report via kaiju2table")
    p.add_argument("--min-percent", type=float, default=0.0,
                   help="Minimum percent to include in kaiju2table output")
    return p.parse_args()


def has_kaiju2table():
    """Return True if kaiju2table is on PATH."""
    try:
        subprocess.run(["kaiju2table", "--help"],
                       capture_output=True, check=False)
        return True
    except FileNotFoundError:
        return False


def split_combined_to_tmpfiles(combined_gz: Path, tmp_dir: str) -> dict[str, str]:
    """
    Read combined.gz and write one temporary kaiju output file per database.
    Returns {db_name: tmp_file_path}.
    """
    handles: dict[str, object] = {}
    paths: dict[str, str] = {}

    with gzip.open(combined_gz, "rt") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t", 1)
            if len(parts) < 2:
                continue
            db_name, rest = parts
            if db_name not in handles:
                tmp_path = os.path.join(tmp_dir, f"{db_name}.kaiju.out")
                handles[db_name] = open(tmp_path, "w")
                paths[db_name] = tmp_path
            handles[db_name].write(rest + "\n")

    for fh in handles.values():
        fh.close()

    return paths


def count_classifications(kaiju_file: str) -> dict[str, int]:
    """Return {'C': N_classified, 'U': N_unclassified}."""
    counts: dict[str, int] = collections.defaultdict(int)
    with open(kaiju_file) as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            status = line.split("\t", 2)[0]
            counts[status] += 1
    return dict(counts)


def build_summary_report(sample: str, db_counts: dict[str, dict], out_path: Path):
    """Write per-database classified / unclassified summary TSV."""
    with open(out_path, "w") as fh:
        fh.write("database\tclassified\tunclassified\ttotal\tpct_classified\n")
        for db, counts in sorted(db_counts.items()):
            c = counts.get("C", 0)
            u = counts.get("U", 0)
            total = c + u
            pct = 100.0 * c / total if total > 0 else 0.0
            fh.write(f"{db}\t{c}\t{u}\t{total}\t{pct:.2f}\n")
    print(f"  Summary report: {out_path}")


def run_kaiju2table(sample: str, db_name: str, kaiju_file: str,
                    taxdir: str, rank: str, min_pct: float, out_path: Path):
    """Run kaiju2table for one db/rank combination."""
    nodes = os.path.join(taxdir, "nodes.dmp")
    names = os.path.join(taxdir, "names.dmp")
    cmd = [
        "kaiju2table",
        "-t", nodes,
        "-n", names,
        "-r", rank,
        "-m", str(min_pct),
        "-o", str(out_path),
        kaiju_file,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  WARNING: kaiju2table failed for {db_name}/{rank}: {result.stderr.strip()}",
              file=sys.stderr)
    else:
        print(f"  Taxonomy table: {out_path}")


def merge_taxonomy_tables(table_paths: list[Path], out_path: Path):
    """
    Combine per-db kaiju2table outputs into one TSV, prepending a db column.
    Expected kaiju2table columns: file  percent  reads  taxon_id  taxon_name
    """
    with open(out_path, "w") as out_fh:
        header_written = False
        for tbl_path in table_paths:
            if not tbl_path.exists():
                continue
            db_name = tbl_path.stem.split(".", 2)[1]  # SAMPLE.DB.rank.tsv
            with open(tbl_path) as fh:
                for i, line in enumerate(fh):
                    if i == 0:
                        if not header_written:
                            out_fh.write("database\t" + line)
                            header_written = True
                    else:
                        out_fh.write(db_name + "\t" + line)
    print(f"  Merged taxonomy table: {out_path}")


def main():
    args = parse_args()

    results_dir = Path(args.results)
    sample_dir  = results_dir / args.sample
    combined_gz = sample_dir / f"{args.sample}.kaiju.combined.gz"

    if not combined_gz.exists():
        sys.exit(f"ERROR: Combined kaiju file not found: {combined_gz}")

    print(f"Processing sample: {args.sample}")
    print(f"Combined file: {combined_gz}")

    use_kaiju2table = has_kaiju2table()
    if not use_kaiju2table:
        print("WARNING: kaiju2table not found — skipping lineage tables.")

    db_counts: dict[str, dict] = {}

    with tempfile.TemporaryDirectory() as tmp_dir:
        print("Splitting combined file into per-database temp files...")
        db_files = split_combined_to_tmpfiles(combined_gz, tmp_dir)
        print(f"  Databases found: {sorted(db_files.keys())}")

        # ── Per-db counts ─────────────────────────────────────────────────────
        for db_name, db_file in sorted(db_files.items()):
            db_counts[db_name] = count_classifications(db_file)

        # ── Summary report ────────────────────────────────────────────────────
        summary_path = sample_dir / f"{args.sample}.kaiju_report.tsv"
        build_summary_report(args.sample, db_counts, summary_path)

        # ── kaiju2table per db × rank ─────────────────────────────────────────
        if use_kaiju2table:
            for rank in args.ranks:
                rank_tables: list[Path] = []
                for db_name, db_file in sorted(db_files.items()):
                    out_tbl = sample_dir / f"{args.sample}.{db_name}.{rank}.tsv"
                    run_kaiju2table(
                        args.sample, db_name, db_file,
                        args.taxdir, rank, args.min_percent, out_tbl,
                    )
                    rank_tables.append(out_tbl)

                merged_tbl = sample_dir / f"{args.sample}.all_dbs.{rank}.tsv"
                merge_taxonomy_tables(rank_tables, merged_tbl)

    print("Done.")


if __name__ == "__main__":
    main()
