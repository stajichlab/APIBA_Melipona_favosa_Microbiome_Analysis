#!/usr/bin/env python3
import os
from pathlib import Path
import argparse
import sys

# --------------------------------------------------
# Helper functions
# --------------------------------------------------

def read_config(config_path):
    """Read config.txt file and return dictionary of variables."""
    if not os.path.exists(config_path):
        print("Please create a config.txt file with the following variables:")
        print("FASTQSOURCE=/path/to/fastq/files")
        sys.exit(1)
    config = {}
    with open(config_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, val = line.split("=", 1)
            config[key.strip()] = val.strip()
    return config


def ensure_dir(path):
    """Create directory if it doesn't exist."""
    os.makedirs(path, exist_ok=True)


def link_file(src, dest):
    """Create a symbolic link if destination does not already exist."""
    if not dest.exists():
        dest.symlink_to(src)
        return True
    return False


# --------------------------------------------------
# Main pipeline
# --------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Symlink FASTQ files from FASTQSOURCE to a target folder."
    )
    parser.add_argument(
        "--config",
        "-c",
        default="config.txt",
        help="Path to configuration file (default: config.txt)",
    )
    parser.add_argument(
        "--target",
        "-t",
        default="input",
        help="Destination root folder (default: input)",
    )

    args = parser.parse_args()

    config = read_config(args.config)

    FASTQSOURCE = config.get("FASTQSOURCE")

    if not FASTQSOURCE or not os.path.isdir(FASTQSOURCE):
        sys.exit("Please set FASTQSOURCE in config.txt to the path of FASTQ directory")

    FASTQSOURCE = Path(FASTQSOURCE).resolve()
    target_root = Path(args.target).resolve()
    ensure_dir(target_root)

    total_created = 0
    for marker in ["16S", "ITS"]:
        src_dir = FASTQSOURCE / marker
        dest_dir = target_root / marker
        ensure_dir(dest_dir)

        if not src_dir.is_dir():
            print(f"WARNING: Source directory not found, skipping: {src_dir}")
            continue

        created = 0
        skipped = 0
        for src_file in sorted(src_dir.glob("*.gz")):
            dest_file = dest_dir / src_file.name
            if link_file(src_file.resolve(), dest_file):
                created += 1
            else:
                skipped += 1

        total_created += created
        print(f"{marker}: linked={created} skipped_existing={skipped} target={dest_dir}")

    print(f"Done. Total new symlinks created: {total_created}")


if __name__ == "__main__":
    main()
