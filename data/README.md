# Pildora Drug Data Pipeline

ETL pipeline that downloads, parses, and exports drug and supplement reference
data for the Pildora app. Includes a SQLite FTS5 search index for fast
autocomplete.

## Quick Start

```bash
# Install (requires Python ≥ 3.11)
cd data/
pip install -e ".[dev]"

# Run the full pipeline
pildora-etl

# Run the pipeline and build the search index
pildora-etl --index

# Build the index without RxNorm API lookups
pildora-etl --index --skip-rxnorm

# Build + compress for distribution
pildora-etl --index --compress

# Or run as a module
python -m pildora_data.cli
```

## CLI Options

| Flag | Default | Description |
|---|---|---|
| `--cache-dir` | `cache/` | Directory for cached downloads |
| `--output-dir` | `output/` | Directory for JSONL output files |
| `-v, --verbose` | off | Enable debug logging |
| `--index` | off | Build the SQLite FTS5 search index after ETL |
| `--output-db` | `<output-dir>/pildora_drugs.sqlite` | Path for the SQLite index |
| `--skip-rxnorm` | off | Skip RxNorm API lookups during index build |
| `--compress` | off | Compress the index with gzip after building |
| `--tiered` | off | Build a **core** (compact, bundled) + **full** index split |
| `--core-limit` | `500` | Number of top drug concepts (by product count) kept in the core index |
| `--index-version` | today (`YYYY.MM.DD`) | Dataset version stamp written to `metadata` and the manifest |
| `--manifest` | off | Emit `manifest.json` with artifact hashes/sizes (implies `--tiered --compress`) |

## Tiered Index (core + full)

The iOS app ships a compact **core** index inside the app bundle and downloads
the **full** index on first launch (issue #68). Build both plus a manifest:

```bash
pildora-etl --index --manifest              # core + full + gzip + manifest.json
pildora-etl --index --tiered --core-limit 800   # custom core size, no manifest
```

Tiered output (in `output/`):

- **`pildora_drugs_full.sqlite`(`.gz`)** — full index (target `< 150MB`), downloaded on first launch
- **`pildora_drugs_core.sqlite`(`.gz`)** — compact core (top-N common drugs + all supplements), bundled in the app
- **`manifest.json`** — the ETL↔app contract: `index_version`, per-tier `sha256`/`size_bytes` for the compressed `.gz` and the decompressed `.sqlite`

The **core** is a strict subset of the **full** index (same schema, same rows for
the drugs it contains), selected by NDC/product prevalence. Both tiers share one
`index_version` so the app can detect when a newer full index is available and
download it without an app update. The app verifies the compressed hash, gunzips,
then verifies the uncompressed hash before atomically installing the full index;
any failure leaves the bundled core in place (graceful offline fallback).

## Data Sources

| Source | Type | License | Status |
|---|---|---|---|
| [openFDA NDC Directory](https://open.fda.gov/apis/drug/ndc/) | Prescription & OTC drugs | Public domain (CC0) | ✅ Implemented |
| [DailyMed SPL API](https://dailymed.nlm.nih.gov/dailymed/app-support-web-services.cfm) | Dietary supplements | Free (public domain) | ✅ Implemented |
| [RxNorm REST API](https://rxnav.nlm.nih.gov/REST/) | Drug naming, RxCUI normalization | Free (no UMLS license needed) | ✅ Implemented |
| NIH ODS | Supplement fact sheets | Free | Planned |

## Output Format

The pipeline produces JSONL files (one JSON object per line):

- **`output/drugs.jsonl`** — Drug products from openFDA NDC data
- **`output/supplements.jsonl`** — Supplements from DailyMed
- **`output/quality_report.txt`** — Coverage and quality statistics
- **`output/pildora_drugs.sqlite`** — SQLite FTS5 search index (with `--index`)
- **`output/pildora_drugs.sqlite.gz`** — Compressed index (with `--compress`)
- **`output/pildora_drugs_{core,full}.sqlite`(`.gz`)** — Tiered indexes (with `--tiered`)
- **`output/manifest.json`** — Tiered distribution manifest (with `--manifest`)

## Search Index

The `--index` flag builds a SQLite database with FTS5 full-text search for
fast drug and supplement autocomplete. The index uses a concept-based model:

### Schema Overview

```text
drug_concepts       — One row per unique drug (deduplicated by generic name)
  ├── drug_aliases   — Brand names, generic names, synonyms
  ├── drug_products  — Individual NDC-level products
  └── drug_fts       — FTS5 virtual table for autocomplete

supplements         — One row per supplement
  └── supplement_fts — FTS5 virtual table for autocomplete

metadata            — Build info (schema version, date, counts)
```

### Concept Deduplication

Products with the same generic name are grouped into a single concept:

- **LIPITOR** (brand) + generic atorvastatin → one concept "Atorvastatin Calcium"
- **ADVIL** + **MOTRIN** (brands) + generic ibuprofen → one concept "Ibuprofen"

### RxNorm Normalization

When `--skip-rxnorm` is not set, the pipeline queries the
[RxNorm REST API](https://rxnav.nlm.nih.gov/REST/) to attach RxCUI identifiers
to drug concepts. This enables cross-referencing with other clinical databases.

- Only the top ~200 most common drugs (by NDC count) are looked up
- Results are cached in `cache/rxnorm_cache.json`
- The API is free and requires no license, but is rate-limited

### Search Usage (Python)

```python
from pathlib import Path
from pildora_data.search import search_drugs, search_supplements, search_all

db = Path("output/pildora_drugs.sqlite")

# Drug search (supports FTS5 syntax including prefix*)
results = search_drugs(db, "atorva*")
results = search_drugs(db, "lipitor")

# Supplement search
results = search_supplements(db, "vitamin d*")
results = search_supplements(db, "melatonin")

# Combined search (drugs + supplements)
results = search_all(db, "aspirin", limit=5)
```

### FTS5 Tokenization

The index uses `unicode61 remove_diacritics 2` tokenization, which handles
accented characters and Unicode normalization. Prefix searches use `*` suffix
(e.g., `atorva*`).

## Drug Product Schema

```json
{
  "ndc": "0002-0800",
  "drug_name": "LIPITOR",
  "generic_name": "ATORVASTATIN CALCIUM",
  "brand_name": "LIPITOR",
  "dosage_form": "TABLET, FILM COATED",
  "strength": "10 mg/1",
  "route": "ORAL",
  "manufacturer": "Pfizer Laboratories",
  "product_type": "HUMAN PRESCRIPTION DRUG",
  "source": "openfda"
}
```

## Supplement Schema

```json
{
  "id": "aaa-bbb-001",
  "name": "Vitamin D3",
  "ingredients": ["CHOLECALCIFEROL"],
  "manufacturer": "Nature Made",
  "dosage_form": "CAPSULE",
  "source": "dailymed"
}
```

## Development

```bash
# Lint
ruff check src/ tests/

# Test
pytest

# Lint + test
ruff check src/ tests/ && pytest
```

## Project Structure

```text
data/
├── pyproject.toml
├── src/
│   └── pildora_data/
│       ├── cli.py            — CLI entry point
│       ├── compress.py       — Gzip compression for distribution
│       ├── download.py       — Data source downloaders
│       ├── index_builder.py  — SQLite FTS5 index builder (+ core/full split)
│       ├── manifest.py       — Tiered distribution manifest (hashes/sizes)
│       ├── models.py         — DrugProduct & Supplement dataclasses
│       ├── output.py         — JSONL writer & quality report
│       ├── rxnorm.py         — RxNorm REST API client
│       ├── search.py         — FTS5 search functions
│       └── parsers/
│           ├── openfda.py    — openFDA NDC parser
│           └── dailymed.py   — DailyMed supplement parser
├── tests/
│   ├── fixtures/             — Sample data for tests
│   ├── test_compress.py
│   ├── test_dailymed.py
│   ├── test_index_builder.py
│   ├── test_models.py
│   ├── test_openfda.py
│   ├── test_output.py
│   ├── test_search.py
│   └── test_tiered.py       — core/full split + manifest
└── output/                   — Generated output (gitignored)
```
