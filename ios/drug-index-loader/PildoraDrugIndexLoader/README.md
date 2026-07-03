# PildoraDrugIndexLoader

Tiered loading for the Pildora drug autocomplete index (issue #68).

The app ships a compact **core** index in its bundle and downloads the **full**
index from a public CDN on first launch. Autocomplete works fully offline from
the core index at all times; the full index transparently takes over once it is
downloaded, verified, and installed. Any failure is non-fatal — the app keeps
serving suggestions from the core index and retries later.

This package owns all networking so the read-only
[`PildoraDrugIndex`](../../drug-index/PildoraDrugIndex) reader stays offline-only.

## Architecture

```text
                 ┌── bundled core-index.db (offline, from core-seed.json) ─────────┐
TieredDrugIndexProvider ┤                                                            ├─→ DrugIndex (GRDB, read-only)
                 └── installed full-index.db (downloaded, verified, App Support) ────┘
        │
        └─ FullIndexDownloader
             GET manifest.json → check schema + version → GET *.sqlite.gz
             → verify sha256 + size (compressed) → gunzip → verify sha256 + size
             → open-validate schema → atomic install → swap active tier to .full
             (any failure ⇒ stay on core)
```

### Types

- `IndexTier` — `.core` / `.full`.
- `IndexManifest` / `ArtifactDescriptor` — the CDN manifest contract (below).
- `InstalledIndexStore` — owns the installed full index + version marker in
  Application Support; installs atomically; excluded from backup.
- `IndexDownloadClient` — network seam (`URLSessionDownloadClient` in production,
  mockable in tests). Streams large downloads to disk with progress + resume.
- `FullIndexDownloader` — orchestrates fetch → verify → gunzip → verify → install.
- `Gunzip` / `IndexIntegrity` — zlib gzip decompression and SHA-256 verification.
- `TieredDrugIndexProvider` — `@MainActor` observable façade. Serves autocomplete
  from the active tier, publishes `activeTier` + download `state` for the UI, and
  hot-swaps core → full when a download succeeds.

## Manifest contract

The `data/` ETL publishes `manifest.json` alongside the compressed index
artifacts. All keys are snake_case; the loader decodes with
`.convertFromSnakeCase`.

```json
{
  "schema_version": "1.0",
  "index_version": "2026.07.02",
  "generated_at": "2026-07-02T00:00:00Z",
  "tiers": {
    "core": {
      "filename": "pildora_drugs_core.sqlite.gz",
      "sha256": "<hex sha256 of the .gz>",
      "size_bytes": 12345,
      "uncompressed_sha256": "<hex sha256 of the .sqlite>",
      "uncompressed_size_bytes": 67890
    },
    "full": {
      "filename": "pildora_drugs_full.sqlite.gz",
      "sha256": "…",
      "size_bytes": 111111,
      "uncompressed_sha256": "…",
      "uncompressed_size_bytes": 222222
    }
  }
}
```

- `schema_version` **must** match the reader's schema (`DrugIndexBuilder.schemaVersion`)
  or the download is rejected.
- `index_version` is compared against the installed full index; an unchanged
  version is a no-op (`.upToDate`).
- Hashes/sizes are checked for **both** the compressed download and the
  decompressed database before install. The index is then opened and its schema
  re-checked before it can replace the live index.

`filename` resolves against a configurable base URL (set via the app's
`PildoraDrugIndexBaseURL` Info.plist key). An empty base URL keeps the app in
core-only mode with no network access.

## Bundled core index

The core index is generated from a checked-in JSON seed
(`ios/app/Pildora/Resources/core-seed.json`) rather than committing a binary:

- At **build time**, `Scripts/generate-core-index.sh` runs the
  `pildora-core-index-tool` executable (in `PildoraDrugIndex`) to emit a
  `core-index.db` app resource. The generated `.db` is git-ignored.
- At **runtime**, if no prebuilt `core-index.db` is bundled, the app builds one
  from `core-seed.json` on first launch. Either way the result is
  schema-identical to the ETL output.

> **Two notions of "core".** The *release* core is the ETL-produced (~30 MB)
> top-N artifact swapped in at release time. The *repo/CI* core is the small one
> generated from `core-seed.json` (CI can't run the full ETL or commit a 30 MB
> binary). Both are schema-identical.

## Privacy / metadata exposure

Zero-knowledge is preserved: **autocomplete queries never leave the device** —
they run entirely against the local index. The only network activity is the
one-time full-index download, which is an anonymous `GET` of a **single static,
public file that is identical for every user**.

| Observable | Exposed to | Notes / mitigation |
|---|---|---|
| Client IP | CDN operator, ISP | Standard for any download; no IP-based analytics. |
| Request timing | CDN operator | Reveals only that the app fetched the public drug DB (typically once, at first launch). |
| TLS SNI hostname | On-path observer | The CDN hostname; frontable behind a shared CDN. |
| Blob size | On-path observer | Fixed public file size — same for all users. |
| **Query text / health data** | **Nobody** | **Never sent.** No search terms, medications, doses, or vault data touch the network. |

Mitigations baked in: no auth, cookies, or credentials on the request
(`URLSession` ephemeral config); no per-user URL or parameters; version-only
cache-busting; the payload is public plaintext reference data. The download is
kept entirely separate from the encrypted vault database (per the repo's Data
Boundary Rule).

See also the roadmap Metadata Exposure Matrix (§2.5).

## Reference-data disclaimer

The drug/supplement data served by this index is **public reference information**
(openFDA + RxNorm) shown for identification and search only. It is **informational
only and not medical advice**. Displayed reference data must carry its source and
date, and interaction/warning surfaces must state: *"This is informational only.
Consult your healthcare provider."*

## Testing

```sh
swift test --package-path ios/drug-index-loader/PildoraDrugIndexLoader
```

Tests use a mock `IndexDownloadClient` and synthesize gzip fixtures, covering
core-only/offline mode, successful tier swap, every verification failure mode
(schema, compressed/decompressed hash + size, corrupt gzip), transient-failure
retry, version checks, and a `< 50 ms` autocomplete latency budget.
