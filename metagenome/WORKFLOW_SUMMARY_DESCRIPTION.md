# Methods: Shotgun Metagenomic Analysis

## Samples

Three shotgun metagenomic samples (`5MMH_5`, `6PEH_6`, `SVH11_Q11`) were sequenced as
paired-end Illumina reads (sample manifest: `samples.csv`).

## Read quality control

Raw paired-end reads were quality- and adapter-trimmed using fastp (Chen et al. 2018)
prior to all downstream analyses.

## Genome-resolved metagenomics

Trimmed reads were assembled and binned using the metashot Nextflow workflow suite
(metashot/mag; Singularity containers), with MEGAHIT used as the assembler. Draft
genome bins were quality-filtered using CheckM and GUNC, with completeness ≥50% and
contamination ≤10% thresholds, followed by dereplication at 95% average nucleotide
identity (ANI). Taxonomy was assigned to surviving bins using GTDB-Tk against the
GTDB R226 reference database. Assembled scaffolds and genome bins were additionally
searched against the UniProt SwissProt and UniRef50 databases using MMseqs2 for
functional and taxonomic annotation, and coding sequences were predicted from
assemblies using Prodigal.

## Read-based taxonomic profiling

Community taxonomic composition was estimated directly from quality-trimmed reads,
independent of assembly, using Kraken2 (Wood et al. 2019) with the PlusPFP reference
database (k-mer-based classification of paired reads against bacterial, archaeal,
viral, fungal, protozoan, and plant genomes). Kraken2 reports were used to re-estimate
taxon abundances with Bracken (Lu et al. 2017) at the species, genus, family, and
phylum ranks, correcting for genome-length bias in the raw k-mer read assignments.

As a complementary/cross-validation approach, reads were also classified by
translated-search protein alignment using Kaiju (Menzel et al. 2016), both against a
partitioned set of domain-specific reference databases (Archaea, Bacteria,
Fungi_others, Metazoa_Choano, Other_Euk, Plants, Viruses) and against the
comprehensive NCBI RefSeq NR database. Bracken-corrected Kraken2 abundances were
used as the primary read-based taxonomic profile for downstream visualization and
interpretation.

## Data visualization

Per-sample, per-rank Bracken abundance tables were aggregated across all three
samples and visualized as stacked bar charts of relative read abundance (top 15 taxa
plus an aggregated "Other" category) at the phylum, genus, and species ranks using a
custom Python script (pandas/matplotlib). Taxonomic abundance tables were also
imported into R as a `phyloseq` object, and comparative stacked-bar composition plots
were generated using the `microshades` package (color-vision-deficiency-safe
palettes) to visualize and compare taxonomic composition across the three samples.

## Software versions and databases

| Tool | Purpose | Database / notes |
|---|---|---|
| fastp | read QC/trimming | — |
| metashot (Nextflow/Singularity) | assembly, binning | MEGAHIT assembler |
| CheckM, GUNC | bin quality filtering | completeness ≥50%, contamination ≤10% |
| GTDB-Tk | bin taxonomic classification | GTDB R226 |
| MMseqs2 | scaffold/bin annotation | UniProt SwissProt, UniRef50 |
| Prodigal | gene prediction | assembled contigs |
| Kraken2 | read-level k-mer taxonomic classification | PlusPFP |
| Bracken | abundance re-estimation | species/genus/family/phylum, read length 150 bp |
| Kaiju | translated-search read classification (cross-check) | multi-domain DBs; RefSeq NR |
| pandas / matplotlib | abundance visualization | stacked bar charts |
| phyloseq / microshades (R) | comparative abundance visualization | CVD-safe stacked bar charts |
