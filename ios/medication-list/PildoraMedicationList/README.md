# PildoraMedicationList

SwiftUI feature package for **issues #50 / #48** — the Phase 1 (S13) medication
management surface: medication list with search, add / edit / delete CRUD with
drug-name autocomplete, basic drug reference data display, manual inventory
tracking with low-stock / refill alerts, and a profile screen with JSON + PDF
(Doctor Mode) data export.

## Status

✅ CRUD + autocomplete landed (#48). The package now builds directly on the
[`PildoraDataLayer`](../../data-layer/PildoraDataLayer/) model types (its former
duplicate models were removed) and persists mutations through a
`MedicationRepository` seam. Drug-name autocomplete is provided by
[`PildoraDrugIndex`](../../drug-index/PildoraDrugIndex/). UI is built on the
shared [`PildoraDesignSystem`](../../design-system/PildoraDesignSystem/) (#43);
the former local `DesignSystem/` token subset has been removed.

- **Persistence:** `MedicationStore` routes add / update / delete and inventory
  writes through `MedicationRepository`. `DatabaseMedicationRepository` (used by
  the app) is backed by the encrypted `AppDatabase` with cascade deletes;
  `InMemoryMedicationRepository` backs previews and unit tests.
- **Autocomplete:** the editor queries the local FTS5 index via the injectable
  `DrugSuggesting` seam. Suggestions are debounced and run off the main actor.

## Build & test

```sh
cd ios/medication-list/PildoraMedicationList
swift build
swift test
```

Builds on the macOS toolchain (same bar as the `ios/` spikes). iOS-only APIs
(`UNUserNotificationCenter`, `UIGraphicsPDFRenderer`) are guarded with
`#if os(iOS)` / `#if canImport(UIKit)` and backed by a simulated
implementation on macOS. Under `swift test` the data layer runs on plain
SQLite; SQLCipher encryption is exercised in the `app/` target.

## Wiring points (for later issues)

| Concern | Today (this package) | Swap-in |
|---|---|---|
| Persistence | `DatabaseMedicationRepository` over `PildoraDataLayer` (#44) | — done (#48) |
| CRUD | `MedicationStore` add / edit / delete + autocomplete | — done (#48) |
| Design tokens | Shared `PildoraDesignSystem` (#43) | — done (#43) |
| Drug reference | `SampleData` reference entries | Local FTS5 drug index (ETL output) |

## Privacy / compliance notes

- **Zero-knowledge / local-first:** all user data stays on-device. Drug-name
  autocomplete queries the local index only — never a server. JSON and PDF
  export are generated entirely on-device.
- **Local notifications only:** refill reminders use local notifications so
  the server never learns dose/refill timing.
- **Disclaimers:** every drug reference datum displays its **source + date**,
  and reference sections carry the informational-only disclaimer
  ("This is informational only. Consult your healthcare provider.").

## Scope notes

- Inventory here is **manual** (user edits the count) per the issue's
  acceptance criteria. Automatic decrement on dose confirmation belongs with
  dose logging and is out of scope.
- Models carry a `vaultId` (one vault = one encryption boundary) per repo
  convention, even though the UI currently shows a single active vault.
