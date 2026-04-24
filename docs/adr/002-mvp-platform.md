# ADR-002: MVP Platform Choice

**Status:** Accepted
**Date:** 2026-04-24

## Context

Pildora targets 5 platforms: iPhone, iPad, Apple Watch, Web, and CLI. Building
all simultaneously as a solo developer is infeasible. We need to choose one
platform for the MVP to validate the core experience before expanding.

## Decision

**iPhone (iOS 17+) first, using native Swift and SwiftUI.**

## Rationale

- **HealthKit integration** — iOS provides the richest health data API. This
  is a key differentiator for future health signal correlation features.
- **Keychain + Secure Enclave** — Best-in-class key storage for the
  zero-knowledge encryption model. Hardware-backed biometric unlock.
- **Local notifications** — iOS supports up to 64 scheduled local
  notifications, sufficient for the MVP notification architecture (ADR-003).
- **SwiftUI code sharing** — SwiftUI code written for iPhone shares directly
  with iPad and Apple Watch with platform-specific adaptations, reducing
  future expansion cost.
- **App Store distribution** — Primary acquisition channel for consumer
  health apps. ASO for "medication tracker privacy" keywords.
- **Persona alignment** — The wedge persona (ADHD/forgetful user) primarily
  uses iPhone and Apple Watch.

## Alternatives Considered

**Web-first:** Would reach more platforms immediately but loses HealthKit,
Keychain, Watch, and native notification reliability. WebCrypto + IndexedDB
is less mature than iOS Keychain for key storage. No App Store distribution.

**Cross-platform (React Native / Flutter):** Gains Android but watchOS
support is poor in both frameworks. Still requires native modules for
HealthKit, Keychain, and notifications. Adds a runtime layer between the
app and the crypto library. Android is not in the initial platform list.

**CLI-first:** Appeals to the biohacker persona but is too niche for user
validation. No notification or health data integration.

## Consequences

- Users on other platforms must wait until Phase 4.
- The developer must have (or acquire) Swift/SwiftUI proficiency.
- iPad and Watch expansion in Phase 4 will be lower-cost due to SwiftUI
  code sharing.
- Android is explicitly not planned — this is an Apple ecosystem product.
