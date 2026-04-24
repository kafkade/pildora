# Pildora Drug Data Pipeline

ETL pipeline for building the local drug reference index.

## Data Sources

| Source | Type | License | Status |
|---|---|---|---|
| openFDA | Prescription & OTC drugs | Public domain | Planned |
| RxNorm (NLM) | Drug naming, relationships | Free (UMLS license) | Planned |
| DailyMed (NLM) | Drug labeling | Free | Planned |
| NIH ODS | Supplement fact sheets | Free | Planned |
| Curated list | Top 200 supplements | Manual curation | Planned |

## Output

SQLite database bundled with the app containing:

- Drug names, NDC codes, RxNorm CUIs
- Common supplement names
- Basic interaction data
- Side effects, contraindications, food interactions

Target: ~80MB compressed, <100ms autocomplete search on iPhone 12.

## Status

🚧 Not yet implemented. Part of Phase 0 technical spikes.
