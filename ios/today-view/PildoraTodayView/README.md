# PildoraTodayView

SwiftUI feature package for **issue #47** — the Phase 1 (S13) Today surface:
chronological dose timeline, one-tap confirmation, swipe actions (taken/skip/snooze),
PRN quick logging, and accessibility-first UI behavior.

## Status

🚧 Self-contained feature slice. Like other iOS feature slices, this package runs
against an in-memory sample store until shared dependencies land:

- schedule engine wiring
- medication CRUD/data layer (#44/#48)

UI is built on the shared
[`PildoraDesignSystem`](../../design-system/PildoraDesignSystem/) (#43) for
color/typography/spacing tokens.

The store and view model shapes are intentionally structured so encrypted SQLCipher
persistence can replace sample data without changing view contracts.

## Build & test

```sh
cd ios/today-view/PildoraTodayView
swift build
swift test
```

Builds on macOS toolchain. iOS-only integrations (haptics) are guarded with
`#if canImport(UIKit)` and no-op on macOS.

## Scope notes

- Dose states covered: upcoming, due now, overdue, taken, skipped, snoozed.
- Dose actions covered: one-tap taken, swipe skip, swipe snooze (+15m default).
- PRN medications are log-only quick actions (no auto scheduling).
- Empty state appears when all scheduled doses for today are resolved.

## Privacy / compliance notes

- **Zero-knowledge / local-first:** this package uses only local in-memory state.
- **No medical advice:** this surface tracks dose actions; it does not provide
  recommendations, diagnostics, or dosing guidance.
- **Multi-vault readiness:** user-health entities include `vaultId` to preserve
  one-vault-per-encryption-boundary modeling.
