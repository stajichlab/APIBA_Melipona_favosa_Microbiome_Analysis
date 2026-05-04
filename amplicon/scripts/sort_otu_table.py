#!/usr/bin/env python3
"""Sort an OTU table by the first column in natural numeric order.

Example ordering: OTU1, OTU2, OTU10, OTU100.
The first line is preserved as the header and is not sorted.
"""

from __future__ import annotations

import argparse
import re
from typing import List, Sequence


def sort_key(first_col: str) -> tuple[int, str]:
    """Return a key that sorts by the first integer in the first column."""
    match = re.search(r"\d+", first_col)
    if match:
        return int(match.group()), first_col
    return float("inf"), first_col


def sort_otu_table(input_path: str, output_path: str) -> None:
    with open(input_path, "r", encoding="utf-8") as infile:
        lines = infile.readlines()

    if not lines:
        with open(output_path, "w", encoding="utf-8"):
            return

    header = lines[0]
    body = lines[1:]

    rows = [line.rstrip("\n").split("\t") for line in body if line.strip()]
    rows.sort(key=lambda cols: sort_key(cols[0] if cols else ""))

    with open(output_path, "w", encoding="utf-8") as outfile:
        outfile.write(header)
        for cols in rows:
            outfile.write("\t".join(cols) + "\n")


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Sort an OTU table by first-column numeric order while preserving "
            "the first line as header."
        ),
        epilog=(
            "Example:\n"
            "  python3 scripts/sort_otu_table.py "
            "BEEHONEY_ITS_OTU/BEEHONEY_ITS_OTU.cluster.otu_table.taxonomy.txt "
            "BEEHONEY_ITS_OTU/BEEHONEY_ITS_OTU.cluster.otu_table.taxonomy.sorted.txt"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("input", help="Path to input otu_table.taxonomy.txt (or similar)")
    parser.add_argument("output", help="Path to write sorted output table")
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args()
    sort_otu_table(args.input, args.output)


if __name__ == "__main__":
    main()
