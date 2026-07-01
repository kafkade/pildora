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
- **Medication list + inventory** ([`medication-list/`](medication-list/PildoraMedicationList/), issue #50) — medication list with search, drug reference display, manual inventory tracking with low-stock / refill reminders, and profile + JSON/PDF export. Self-contained against an in-memory sample store until the data layer (#44), CRUD (#48), and design system (#43) land.
- **Today view + dose confirmation** ([`today-view/`](today-view/PildoraTodayView/), issue #47) — chronological Today timeline with one-tap dose confirmation, swipe actions (taken/skip/snooze), PRN quick logging, and VoiceOver/Dynamic Type support. Self-contained against an in-memory sample store until schedule engine and persistence wiring land.
- **Secure memory wrapper** ([`secure-memory/`](secure-memory/PildoraSecureMemory/), issue #40) — `SecureBytes`, a move-only (`~Copyable`) type that zeroizes key material on release, resolving the Swift memory-zeroization hardening item from ADR-007. Pure Swift library; builds and tests with `swift test`.
- **Encrypted data layer** ([`data-layer/`](data-layer/PildoraDataLayer/), issue #44) — production SQLCipher persistence: five vault-scoped GRDB entities (`Vault`, `Medication`, `Schedule`, `DoseLog`, `InventoryRecord`), typed CRUD with cascade deletes, a versioned migration framework, and a one-vault-one-file manager. The SQLCipher key is derived from the vault key via the new `derive_sqlcipher_key` FFI (HKDF-SHA256), with a `DatabaseKeyDeriving` seam keeping the package testable standalone. Data model documented in [`docs/ios-data-model.md`](../docs/ios-data-model.md).
- **Xcode Rust build phase** ([`app/`](app/), issue #41) — minimal Xcode app that cross-compiles `pildora-crypto-ffi` for the active SDK/arch via a Run Script build phase, so `Cmd+B` builds and runs the FFI bridge with no manual script step. Generated with XcodeGen (`project.yml`).

Requires completion of `pildora-crypto` (Phase 0) before app development begins.
