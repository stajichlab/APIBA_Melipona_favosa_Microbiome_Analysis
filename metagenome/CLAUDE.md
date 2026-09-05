# BeeGut Metagenome Pipeline

## Project layout

```
input/               — raw paired-end reads (fastq.gz)
samples.csv          — sample manifest (col1: sample_id, col2: R? glob pattern)
results_kaiju/       — kaiju multi-db classification output, one subfolder per sample
results_refseq_nr/   — kaiju refseq_nr classification output, one subfolder per sample
logs/                — SLURM job logs
pipeline/kaiju/      — kaiju multi-db pipeline scripts (see below)
pipeline/refseq_nr/  — kaiju refseq_nr pipeline scripts (see below)
```

## Kaiju taxonomic classification pipeline

### Databases

Seven FM-index databases located in `/srv/projects/db/kaiju/20260128/kaiju_nr_cluster/kaiju_indexes/`:
`Archaea`, `Bacteria`, `Fungi_others`, `Metazoa_Choano`, `Other_Euk`, `Plants`, `Viruses`.
Taxonomy (nodes.dmp / names.dmp / merged.dmp) is in the sibling `taxonomy/` directory.
New `.fmi` files dropped into the index directory are picked up automatically.

### Scripts — `pipeline/kaiju/`

| Script | Role |
|---|---|
| `01_submit_kaiju.sh` | Entry point. Builds `logs/kaiju_jobs.tsv` (one row per sample×db), submits classification array job, then submits one merge job per sample with `--dependency=afterok` on the array. |
| `run_kaiju_classify.sh` | SLURM array worker (short queue, 192 GB, 16 CPUs, 2 h). Resolves sample/DB from array index via `JOBS_TSV`. Runs `kaiju` and writes `results_kaiju/SAMPLE/SAMPLE.DBNAME.kaiju.out`. |
| `02_merge_kaiju.sh` | SLURM job (short queue, 8 GB). Concatenates all per-DB `.kaiju.out` files for a sample, prepending the DB name as column 1, into a single `SAMPLE.kaiju.combined.gz`. Deletes raw per-DB files afterward. |
| `03_submit_reports.sh` | Submits one report job per sample (run manually after merges complete). |
| `run_kaiju_report.sh` | SLURM wrapper (short queue, 16 GB, 4 CPUs). Calls `kaiju_report.py`. |
| `kaiju_report.py` | Python script. Splits `combined.gz` into per-db temp files, writes a C/U summary TSV, then runs `kaiju2table` at multiple ranks (species → phylum) and merges outputs into `SAMPLE.all_dbs.RANK.tsv`. |

### Running the pipeline

```bash
cd /bigdata/stajichlab/shared/projects/BeeGut/metagenome

# Step 1: classify all samples against all databases + auto-merge
bash pipeline/kaiju/01_submit_kaiju.sh

# (optional dry-run to preview jobs without submitting)
bash pipeline/kaiju/01_submit_kaiju.sh --dry-run

# Step 2: generate reports after all merge jobs finish
bash pipeline/kaiju/03_submit_reports.sh
```

### Output per sample

```
results_kaiju/SAMPLE/
  SAMPLE.kaiju.combined.gz          — all databases merged (db_name prepended as col 1)
  SAMPLE.kaiju_report.tsv           — classified/unclassified counts per database
  SAMPLE.DB.RANK.tsv                — kaiju2table output per db/rank
  SAMPLE.all_dbs.RANK.tsv           — merged taxonomy table across all databases
```

---

## Kaiju refseq_nr pipeline

Single-database classification against the NCBI RefSeq NR index. Fully automated
dependency chain: classify → per-sample reports (kaiju2table + Krona) → aggregate
R/phyloseq barchart PDF.

### Database

```
/srv/projects/db/kaiju/20260128/refseq_nr/kaiju_db_refseq_nr.fmi
/srv/projects/db/kaiju/20260128/refseq_nr/taxonomy/   — nodes.dmp / names.dmp
```

### Scripts — `pipeline/refseq_nr/`

| Script | Role |
|---|---|
| `01_submit_refseq_nr.sh` | Entry point. Builds `logs/refseq_nr_jobs.tsv` (one row per sample), submits classification array, submits per-sample report jobs with `afterok`, then submits aggregate plot job after all reports. Supports `--dry-run`. |
| `run_refseq_nr_classify.sh` | SLURM array worker (short queue, 120 GB, 24 CPUs, 6 h). Runs `kaiju` and writes `results_refseq_nr/SAMPLE/SAMPLE.refseq_nr.kaiju.out`. |
| `run_refseq_nr_report.sh` | SLURM job (short queue, 16 GB, 4 CPUs, 1 h). Runs `kaiju2table` at species→phylum plus genus with `-p` (full lineage for R). Runs `kaiju2krona` + `ktImportText` to produce `SAMPLE.krona.html`. |
| `run_refseq_nr_plot.sh` | SLURM wrapper (short queue, 32 GB, 4 CPUs, 1 h) that calls the R script. |
| `plot_taxonomy_microshades.R` | Reads all per-sample genus lineage TSVs, builds a `phyloseq` object, and generates a CVD-safe stacked barchart PDF using `microshades` palettes. |

### Running the pipeline

```bash
cd /bigdata/stajichlab/shared/projects/VitLab_HoneyPollen_Microbiome/metagenome

# Optional dry-run to preview jobs
bash pipeline/refseq_nr/01_submit_refseq_nr.sh --dry-run

# Submit full pipeline (classify → reports → barchart PDF)
bash pipeline/refseq_nr/01_submit_refseq_nr.sh
```

### Output per sample

```
results_refseq_nr/SAMPLE/
  SAMPLE.refseq_nr.kaiju.out              — raw kaiju classification
  SAMPLE.refseq_nr.RANK.tsv              — kaiju2table at each rank (species→phylum)
  SAMPLE.refseq_nr.genus.lineage.tsv     — genus table with full lineage (-p flag)
  SAMPLE.krona.txt                        — kaiju2krona intermediate
  SAMPLE.krona.html                       — Krona interactive plot
results_refseq_nr/
  refseq_nr_taxonomy_barchart.pdf         — microshades stacked barchart (all samples)
```

### R package dependencies

Install once interactively before the first run:

```r
install.packages(c("optparse","dplyr","tidyr","readr","ggplot2","cowplot","patchwork"))
BiocManager::install("phyloseq")
remotes::install_github("KarstensLab/microshades")
```
