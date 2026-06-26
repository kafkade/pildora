# PildoraMedicationList

SwiftUI feature package for **issue #50** — the Phase 1 (S13) medication
management surface: medication list with search, basic drug reference data
display, manual inventory tracking with low-stock / refill alerts, and a
profile screen with JSON + PDF (Doctor Mode) data export.

## Status

🚧 Self-contained feature slice. Because its dependencies are still open
(#43 design system, #44 SQLCipher data layer, #48 CRUD), this package ships
against an **in-memory sample store** and a **minimal local design-token
subset** so the screens are buildable, previewable, and testable today. The
store and notification scheduler are protocol-/`ObservableObject`-backed so
the real persistence and design system can be swapped in later.

## Build & test

```sh
cd ios/medication-list/PildoraMedicationList
swift build
swift test
```

Builds on the macOS toolchain (same bar as the `ios/` spikes). iOS-only APIs
(`UNUserNotificationCenter`, `UIGraphicsPDFRenderer`) are guarded with
`#if os(iOS)` / `#if canImport(UIKit)` and backed by a simulated
implementation on macOS.

## Wiring points (for later issues)

| Concern | Today (this package) | Swap-in |
|---|---|---|
| Persistence | `MedicationStore` in-memory sample data | GRDB + SQLCipher data layer (#44) |
| CRUD | `MedicationStore` mutators (inventory, settings) | Full CRUD + autocomplete (#48) |
| Design tokens | `DesignSystem/` minimal subset | Full design system (#43) |
| Drug reference | `SampleData` reference entries | Local FTS5 drug index (ETL output) |

## Privacy / compliance notes

- **Zero-knowledge / local-first:** all user data stays on-device. JSON and
  PDF export are generated entirely on-device — no server involvement.
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
