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

## Dependencies

- `pildora-crypto` (Rust via UniFFI FFI) — encryption operations
- GRDB.swift + SQLCipher — on-device encrypted storage (see [`sqlcipher-spike/`](sqlcipher-spike/))
- HealthKit — Apple Health integration

## Status

🚧 Not yet implemented. Four technical spikes have been validated:

- **FFI bridge** ([`ffi-spike/`](ffi-spike/), issue #21) — Rust→Swift via UniFFI
- **SQLCipher storage** ([`sqlcipher-spike/`](sqlcipher-spike/), issue #22) — GRDB.swift + encrypted SQLite
- **Notification rotation** ([`notification-spike/`](notification-spike/), issue #23) — 64-limit rotation strategy with priority-based scheduling
- **Accessibility baseline** ([`accessibility-spike/`](accessibility-spike/), issue #24) — SwiftUI + VoiceOver + Dynamic Type prototype

Requires completion of `pildora-crypto` (Phase 0) before app development begins.
