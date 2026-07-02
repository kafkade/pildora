# Pildora iOS / iPadOS / watchOS

Native Apple platform apps built with Swift and SwiftUI.

## Shared Codebase

The iOS, iPadOS, and watchOS apps share a common SwiftUI codebase with platform-specific adaptations:

- **iPhone**: Primary interface — Today View, medication management, dose confirmation
- **iPad**: Multi-column layout, dashboard with charts
- **Apple Watch**: Complications, haptic reminders, quick dose confirmation

## FFI Bridge (Rust → Swift)

The apps call `pildora-crypto` via a UniFFI-generated FFI bridge. See
[ADR-007](../docs/adr/007-rust-swift-ffi-bridge.md) for the architecture
decision and [`ffi-spike/`](ffi-spike/) for the technical validation.

Architecture:

```text
Swift/SwiftUI app
  → PildoraCrypto Swift Package
    → UniFFI-generated bindings
      → pildora-crypto-ffi (Rust, extern "C")
        → pildora-crypto (safe Rust)
```

The `pildora-crypto-ffi` crate (in `crypto-uniffi/`) is a thin wrapper that
exposes the crypto API across the FFI boundary. It is kept separate from the
core crypto crate to preserve the `unsafe_code = "deny"` invariant.

### Build integration

The app ([`app/`](app/)) compiles the Rust crypto library as part of the normal
Xcode build via a Run Script build phase — press `Cmd+B` and the active
SDK/architecture is cross-compiled, linked, and run with no manual step. See
[`app/README.md`](app/README.md) for setup. The standalone
[`ffi-spike/build-xcframework.sh`](ffi-spike/build-xcframework.sh) is retained
for CI (the **FFI (macOS)** job) and the pre-built XCFramework path.

## Dependencies

- `pildora-crypto` (Rust via UniFFI FFI) — encryption operations
- GRDB.swift + SQLCipher — on-device encrypted storage (see [`sqlcipher-spike/`](sqlcipher-spike/))
- HealthKit — Apple Health integration

## Status

🚧 Not yet implemented as a shipping app. Four technical spikes have been
validated, and the first Phase 1 feature slice has been built as a
standalone SwiftUI package:

- **FFI bridge** ([`ffi-spike/`](ffi-spike/), issue #21) — Rust→Swift via UniFFI
- **SQLCipher storage** ([`sqlcipher-spike/`](sqlcipher-spike/), issue #22) — GRDB.swift + encrypted SQLite
- **Notification rotation** ([`notification-spike/`](notification-spike/), issue #23) — 64-limit rotation strategy with priority-based scheduling
- **Accessibility baseline** ([`accessibility-spike/`](accessibility-spike/), issue #24) — SwiftUI + VoiceOver + Dynamic Type prototype
- **Design system foundation** ([`design-system/`](design-system/PildoraDesignSystem/), issue #43) — shared `PildoraDesignSystem` package: semantic color tokens (light + dark + high-contrast), a Dynamic-Type typography scale (to xxxLarge+), a 4pt/8pt spacing/radius grid, and a base component library (`PildoraButton`, `Card`, `PildoraTextField`, `ListRow`, `StatusBadge`, `SourceTag`) with icon-plus-text status (never color alone), 44pt tap targets, and VoiceOver labels. Includes a `DesignSystemCatalog` preview catalog; `medication-list` and `today-view` build on it. watchOS shares the color tokens. Documented in [`docs/ios-design-system.md`](../docs/ios-design-system.md).
- **Medication list + inventory** ([`medication-list/`](medication-list/PildoraMedicationList/), issues #50 / #48) — searchable, category-grouped medication list with drug reference display, manual inventory tracking with low-stock / refill reminders, and profile + JSON/PDF export. Now backed by the encrypted [data layer](data-layer/PildoraDataLayer/) with full **add / edit / delete** CRUD (#48) and drug-name autocomplete via the drug index (below), and built on the shared [design system](design-system/PildoraDesignSystem/) (#43).
- **Drug autocomplete index** ([`drug-index/`](drug-index/PildoraDrugIndex/), issue #48) — read-only `PildoraDrugIndex` package that opens the bundled FTS5 drug index (produced by the [`data/`](../data/) ETL) and returns `< 50 ms` prefix-matched drug + supplement suggestions. Public reference data only, queried entirely on-device (never sent to a server). Ships a schema-identical `DrugIndexBuilder` so tests and the app's dev seed can build a small index without the full pipeline.
- **Today view + dose confirmation** ([`today-view/`](today-view/PildoraTodayView/), issue #47) — chronological Today timeline with one-tap dose confirmation, swipe actions (taken/skip/snooze), PRN quick logging, and VoiceOver/Dynamic Type support. Self-contained against an in-memory sample store until schedule engine and persistence wiring land.
- **Secure memory wrapper** ([`secure-memory/`](secure-memory/PildoraSecureMemory/), issue #40) — `SecureBytes`, a move-only (`~Copyable`) type that zeroizes key material on release, resolving the Swift memory-zeroization hardening item from ADR-007. Pure Swift library; builds and tests with `swift test`.
- **Encrypted data layer** ([`data-layer/`](data-layer/PildoraDataLayer/), issue #44) — production SQLCipher persistence: five vault-scoped GRDB entities (`Vault`, `Medication`, `Schedule`, `DoseLog`, `InventoryRecord`), typed CRUD with cascade deletes, a versioned migration framework, and a one-vault-one-file manager. The SQLCipher key is derived from the vault key via the new `derive_sqlcipher_key` FFI (HKDF-SHA256), with a `DatabaseKeyDeriving` seam keeping the package testable standalone. Data model documented in [`docs/ios-data-model.md`](../docs/ios-data-model.md).
- **Schedule engine** ([`schedule-engine/`](schedule-engine/PildoraScheduleEngine/), issue #46) — pure-Swift, dependency-free computation layer that turns a medication's recurrence rule into concrete dose times. Supports daily, multi-daily, every-N-days, specific days, cycling (e.g. 21-on/7-off), and PRN, with explicit `"HH:mm"` times or configurable morning/afternoon/evening/bedtime windows. `nextDoses(count:)` (for notifications + Today view) and `occurrences(in:)` compute wall-clock times with correct timezone-travel and DST handling; `validate()` blocks impossible/overlapping schedules. Defines its own richer input model, independent of the persisted `Schedule` until a later wiring issue. Documented in [`docs/ios-schedule-engine.md`](../docs/ios-schedule-engine.md).
- **Xcode Rust build phase** ([`app/`](app/), issues #41 / #48) — Xcode app that cross-compiles `pildora-crypto-ffi` for the active SDK/arch via a Run Script build phase, so `Cmd+B` builds and runs with no manual step. Now hosts the medication UI ([`medication-list/`](medication-list/PildoraMedicationList/)) on the encrypted database — vault bootstrap via the crypto FFI + `VaultDatabaseManager`, vault key in the Keychain — with the FFI smoke test preserved behind a Diagnostics tab and XCUITests covering medication CRUD + autocomplete (#48). Generated with XcodeGen (`project.yml`).

Requires completion of `pildora-crypto` (Phase 0) before app development begins.
