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
- HealthKit — Apple Health integration
- Local SQLite — on-device encrypted storage

## Status

🚧 Not yet implemented. The FFI bridge has been validated in a
[technical spike](ffi-spike/) (see issue #21). Requires completion of
`pildora-crypto` (Phase 0) before app development begins.
