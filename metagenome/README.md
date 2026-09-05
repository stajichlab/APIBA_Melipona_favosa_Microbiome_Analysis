# BeeGut Metagenome

Shotgun metagenome analysis pipeline for BeeGut samples.

## Sample manifest

`samples.csv` — two columns, no spaces:

| column | content |
|--------|---------|
| `sample` | Sample ID (e.g. `5MMH_5`) |
| `shotgun` | Read file glob pattern using `?` as R1/R2 wildcard (e.g. `JS_5MMH_5_S4_L006_R?_001.fastq.gz`) |

Raw reads live in `input/`.

## Pipelines

### Kaiju taxonomic classification (`pipeline/kaiju/`)

Classifies each sample against seven reference databases (Archaea, Bacteria,
Fungi\_others, Metazoa\_Choano, Other\_Euk, Plants, Viruses) in parallel using
SLURM array jobs, then merges results per sample.

**Quick start:**

```bash
# Classify all samples × all databases (one SLURM job per combination)
bash pipeline/kaiju/01_submit_kaiju.sh

# After all jobs complete, generate per-sample reports
bash pipeline/kaiju/03_submit_reports.sh
```

**Key scripts:**

| Script | What it does |
|--------|-------------|
| `01_submit_kaiju.sh` | Builds job table, submits classification array + dependent merge jobs |
| `run_kaiju_classify.sh` | SLURM worker — runs `kaiju` for one sample × one database (192 GB, 16 CPUs) |
| `02_merge_kaiju.sh` | Concatenates per-DB outputs into `SAMPLE.kaiju.combined.gz` |
| `03_submit_reports.sh` | Submits report jobs after merging |
| `run_kaiju_report.sh` | SLURM wrapper for the Python report script |
| `kaiju_report.py` | Generates C/U summary and `kaiju2table` taxonomy tables at multiple ranks |

**Output** written to `results_kaiju/SAMPLE/`:

```
SAMPLE.kaiju.combined.gz        all databases merged (db name as col 1)
SAMPLE.kaiju_report.tsv         classified / unclassified counts per database
SAMPLE.all_dbs.RANK.tsv         taxonomy counts merged across all databases
SAMPLE.DB.RANK.tsv              per-database kaiju2table output
```

Databases are auto-discovered from `/srv/projects/db/kaiju/20260128/kaiju_nr_cluster/kaiju_indexes/*.fmi`.

### Kaiju refseq_nr classification (`pipeline/refseq_nr/`)

Classifies each sample against the NCBI RefSeq NR database. Fully automated
dependency chain submitted by a single entry-point script:
classify array → per-sample reports (kaiju2table + Krona HTML) → aggregate
stacked barchart PDF (phyloseq + microshades).

**Quick start:**

```bash
# Dry run to preview jobs without submitting
bash pipeline/refseq_nr/01_submit_refseq_nr.sh --dry-run

# Submit full pipeline
bash pipeline/refseq_nr/01_submit_refseq_nr.sh
```

**Key scripts:**

| Script | What it does |
|--------|-------------|
| `01_submit_refseq_nr.sh` | Builds job table, submits classify array + dependent report jobs + aggregate plot job |
| `run_refseq_nr_classify.sh` | SLURM worker — runs `kaiju` against refseq_nr for one sample (120 GB, 24 CPUs) |
| `run_refseq_nr_report.sh` | Runs `kaiju2table` (species→phylum + genus with full lineage) and `kaiju2krona` / `ktImportText` |
| `run_refseq_nr_plot.sh` | SLURM wrapper for the R plotting script |
| `plot_taxonomy_microshades.R` | Builds a `phyloseq` object from all samples, plots CVD-safe microshades barchart PDF |

**Output** written to `results_refseq_nr/SAMPLE/`:

```
SAMPLE.refseq_nr.kaiju.out             raw kaiju classification
SAMPLE.refseq_nr.RANK.tsv             kaiju2table at each rank (species → phylum)
SAMPLE.refseq_nr.genus.lineage.tsv    genus table with full semicolon lineage
SAMPLE.krona.html                      Krona interactive plot
results_refseq_nr/refseq_nr_taxonomy_barchart.pdf   aggregate PDF (all samples)
```

Database: `/srv/projects/db/kaiju/20260128/refseq_nr/kaiju_db_refseq_nr.fmi`

R packages required (install once): `phyloseq` (Bioconductor),
`microshades` (`remotes::install_github("KarstensLab/microshades")`),
`optparse`, `dplyr`, `tidyr`, `readr`, `ggplot2`, `cowplot`, `patchwork`.

### Other pipelines

| Directory | Pipeline |
|-----------|---------|
| `pipeline/nf-metashot/` | Metashot Nextflow workflows (assembly, binning, QC, classification) |
| `pipeline/mg-read-profile/` | Read-level profiling |
