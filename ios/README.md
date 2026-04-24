# Pildora iOS / iPadOS / watchOS

Native Apple platform apps built with Swift and SwiftUI.

## Shared Codebase

The iOS, iPadOS, and watchOS apps share a common SwiftUI codebase with platform-specific adaptations:

- **iPhone**: Primary interface — Today View, medication management, dose confirmation
- **iPad**: Multi-column layout, dashboard with charts
- **Apple Watch**: Complications, haptic reminders, quick dose confirmation

## Dependencies

- `pildora-crypto` (Rust via FFI) — encryption operations
- HealthKit — Apple Health integration
- Local SQLite — on-device encrypted storage

## Status

🚧 Not yet implemented. Requires completion of `pildora-crypto` (Phase 0).
