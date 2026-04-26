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
│       ├── index_builder.py  — SQLite FTS5 index builder
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
│   └── test_search.py
└── output/                   — Generated output (gitignored)
```
