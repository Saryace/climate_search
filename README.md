## Búsqueda en bases de datos OpenAlex, WoS y Scopus

Búsqueda sistemática de literatura sobre adaptación al cambio climático en contextos urbanos de Centro y Sudamérica entre 2021–2025.

Bases de datos utilizadas: Web of Science, Scopus y OpenAlex
Idiomas: inglés, español y portugués
Eliminación de duplicados: solo coincidencia exacta por DOI

---

## estructura del proyecto (carpetas y archivos)

```
climate_search/
├── climate_search.Rproj
├── run_pipeline.R            ← código central que ejecuta todo
├── PACKAGES.R                ← instalaciones + API key
├── R/
│   ├── queries.R             ← búsqueda Booleana en base a paper Cortés and Quiroga 2023
│   ├── 01_retrieve_openalex.R   openalexR — gratis, hay que poner correo electrónico
│   ├── 02_retrieve_wos.R        API (rwosstarter) O descargar manual de WoS exportando un .txt 
│   ├── 03_retrieve_scopus.R     API (rscopus) O o descargar manual de Scopus exportando un .csv
│   ├── 04_merge_and_dedup.R     Revisión de DOI entre las 3 bases de dato
│   ├── 05_tag_doctype.R         revisar si son paper review / research paper / otro
│   ├── 06_screen.R              Doble revisar country + concept 
│   └── 07_report.R              PRISMA counts, distribuciones
├── data/
│   ├── raw/                  ← Acá lo que arrojan las búsquuedas/API + acá deben ir los datos descargador manualmente
│   └── processed/            ← Datos limpios, eliminación de duplicados
├── output/
│   ├── screened/
│   ├── prisma_flow.csv
│   ├── report_summary.csv
│   ├── doctype_distribution.csv
│   ├── doctype_by_database.csv
│   ├── doctype_unmatched.csv
│   ├── top_journals.csv
│   └── year_distribution.csv
└── logs/
```

---

## Quick start

### 1. Install packages

```r
source("PACKAGES.R")
```

### 2. Set up API keys

Add to `~/.Renviron` (open with `usethis::edit_r_environ()`):

```
WOS_STARTER_KEY="your_wos_key_here"
Elsevier_API="your_scopus_key_here"
```

Restart R after saving.

| Key | Where to get it | Restrictions |
|-----|----------------|--------------|
| `WOS_STARTER_KEY` | [developer.clarivate.com](https://developer.clarivate.com) | Free; 1 req/sec; max 1000 records/query |
| `Elsevier_API` | [dev.elsevier.com](https://dev.elsevier.com) | Institutional subscription required; IP-bound — use campus network or VPN |

Set your email for OpenAlex in `R/01_retrieve_openalex.R`:
```r
options(openalexR.mailto = "your@email.com")
```

### 3. Run

```r
source("run_pipeline.R")
```

Or individual steps:
```r
source("R/02_retrieve_wos.R")       # re-run WoS only
source("R/04_merge_and_dedup.R")    # re-merge after any retrieval change
source("R/06_screen.R")             # re-screen after editing patterns
```

---

## WoS and Scopus: API vs manual import

Both scripts auto-detect which mode to use based on what's available:

| Condition | Mode |
|-----------|------|
| API key set + package installed | **API** (automatic, paginated) |
| No API key, export files present | **Manual import** (from `data/raw/`) |
| Neither | Warning, empty file written, pipeline continues |

### Manual export instructions

**Web of Science** — run each language query, then:
- Export → Other File Formats → Tab-delimited (Win/Mac)
- Include: Title, Abstract, DOI, Publication Year, Authors, Source,
  Document Type, Language, Accession Number
- Save as:
  - `data/raw/wos_export_english.txt`
  - `data/raw/wos_export_spanish.txt`
  - `data/raw/wos_export_portuguese.txt`

**Scopus** — run each language query, then:
- Export → CSV → check all fields including Abstract, DOI, EID
- Save as:
  - `data/raw/scopus_export_english.csv`
  - `data/raw/scopus_export_spanish.csv`
  - `data/raw/scopus_export_portuguese.csv`

---

## Workflow

```
  OpenAlex API  ──→ 01_retrieve_openalex.R ──→ data/raw/openalex_raw.csv
  WoS API/files ──→ 02_retrieve_wos.R      ──→ data/raw/wos_raw.csv
  Scopus API/files → 03_retrieve_scopus.R  ──→ data/raw/scopus_raw.csv

                   ▼
          04_merge_and_dedup.R
          DOI exact match (case-insensitive)
          → keeps record with longest abstract per DOI
          → records without DOI kept as-is
          → found_in_dbs column tracks database overlap
          data/processed/unique_records.csv

                   ▼
          05_tag_doctype.R
          doc_type field + title keyword fallback
          → review | research_paper | other
          data/processed/unique_records_tagged.csv

                   ▼
          06_screen.R
          Screen A1: bare country name match
          Screen A2: country name within 80 chars of study-context word
          Screen B:  urban/city concept match
          output/screened/screened_pass.csv        (bare, high recall)
          output/screened/screened_pass_strict.csv (context, recommended)
          output/screened/screened_weak.csv        (flagged incidental mentions)

                   ▼
          07_report.R
          output/prisma_flow.csv
          output/doctype_distribution.csv
          output/top_journals.csv
          output/year_distribution.csv
```

---

## Deduplication

**Exact DOI only** (case-insensitive, normalised to lowercase):
- Records sharing a DOI: keep the one with the longest abstract
- `found_in_dbs` column lists all contributing databases
- Records without DOI: kept as-is — no fuzzy matching

---

## Document type tagging (`doc_type_tag`)

| Tag | Meaning |
|-----|---------|
| `review` | Systematic/scoping/narrative review, meta-analysis, bibliometric |
| `research_paper` | Original article, conference paper, letter, note |
| `other` | Editorial, book chapter, unknown |

---

## Country screening (two-tier)

| Flag | Meaning |
|------|---------|
| `screen_country` | Any country name anywhere in title/abstract (broad) |
| `screen_country_context` | Country name within ~80 chars of a study-context word (strict) |
| `screen_country_weak` | Broad match but not strict — likely incidental mention |

**`screened_pass_strict.csv`** is the recommended set for manual review.
**`screened_weak.csv`** lists records to prioritise for false-positive checking.

---

## API limits

| Database | Package | Limit |
|----------|---------|-------|
| OpenAlex | `openalexR` | None (free, auto-paginated) |
| WoS | `rwosstarter` | 1000 records/query — warns if exceeded; split by year if needed |
| Scopus | `rscopus` | ~5000 records/query — warns if exceeded |

---

*Search strategies: `README_search_strategies.md`*  
*Last updated: May 2026*
