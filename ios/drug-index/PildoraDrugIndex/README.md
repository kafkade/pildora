# PildoraDrugIndex

Read-only, on-device **drug-name autocomplete** for the Pildora iOS app —
**issue #48**. Opens the bundled FTS5 drug index produced by the
[`data/`](../../../data/) ETL pipeline (openFDA + RxNorm) and returns fast,
prefix-matched drug and supplement suggestions for the medication editor.

## Status

✅ Implemented and unit-tested (`swift test`), including a `< 50 ms` latency
assertion against a fixture index. Consumed by
[`medication-list`](../../medication-list/PildoraMedicationList/) and the
[`app/`](../../app/) target.

## Privacy

This package reads **public reference data only** — drug and supplement names
from openFDA / RxNorm. It is stored in plaintext by design and is kept entirely
separate from the encrypted vault database.

**Zero-knowledge:** autocomplete runs against this local index only. Query text
is never sent to a server (there is no network path in this package).

## Architecture

```text
Bundled FTS5 index (schema-identical to the data/ ETL output)
  → DrugIndex (GRDB, read-only DatabaseQueue)
    → FTSQuery sanitizes user input into a safe prefix MATCH ("token"*)
      → search(_:limit:) merges drug_fts + supplement_fts by rank
        → [DrugSuggestion]  (displayName, genericName, rxcui, kind)
```

The schema (tables `drug_concepts`, `drug_aliases`, `drug_products`,
`supplements`; virtual tables `drug_fts`, `supplement_fts`; `metadata`) matches
the Python builder in `data/src/pildora_data/index_builder.py` **byte-for-byte**,
so `DrugIndex` reads the production ETL index and a locally built one
interchangeably.

## Components

| Type | Role |
| --- | --- |
| `DrugIndex` | Opens an index file (or a `DatabaseQueue`) and runs `search(_:limit:)`. |
| `DrugSuggestion` | Result value: `displayName`, `genericName?`, `rxcui?`, `kind` (drug/supplement), `subtitle`. |
| `FTSQuery` | Sanitizes free text into a safe FTS5 prefix query (quotes tokens, escapes embedded quotes, appends `*`). |
| `DrugIndexBuilder` | Builds a small, schema-identical index from `DrugEntry` / `SupplementEntry` — used by tests and the app's first-launch dev seed. |

## Usage

```swift
let index = try DrugIndex(path: bundledIndexPath, readonly: true)
let matches = try index.search("ibup", limit: 8)
// → [DrugSuggestion(displayName: "Ibuprofen", genericName: "ibuprofen", kind: .drug), …]
```

The production index ships from the ETL. Until that bundled artifact is wired
into the app resources, the app builds a small curated seed on first launch via
`DrugIndexBuilder` (see `ios/app/Pildora/App/DrugSeed.swift`).

## Testing

```sh
cd ios/drug-index/PildoraDrugIndex
swift test
```

Tests build a fixture index with `DrugIndexBuilder` and assert prefix matching,
brand↔generic hits, supplement hits, query sanitization, and autocomplete
latency `< 50 ms`.
