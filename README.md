# Pildora

> [!IMPORTANT]
> **This project is in the early planning stage.** There is no working software yet — only documentation, architecture decisions, and a product roadmap. If you're interested in following along or contributing, star the repo and watch for updates.

**Your health data is yours. We can't see it even if we wanted to.**

Pildora is a multi-platform medication and supplement tracker with zero-knowledge, end-to-end encryption. Your medications, schedules, and health data are encrypted on your device before they ever leave it. Our servers store only encrypted data that we cannot read.

## Principles

1. **User Data Ownership** — You own 100% of your data. We will never monetize, sell, share, or mine it.
2. **Zero-Knowledge Architecture** — End-to-end encrypted, modeled after 1Password's vault design. If our servers were fully compromised, your health data remains protected.
3. **No Medical Advice** — Pildora is a tracking and information tool, not a substitute for professional medical guidance.
4. **Local-First** — Works fully offline. Cloud sync is optional, always encrypted.

## Platforms

| Platform | Technology | Status |
|---|---|---|
| iPhone / iPad | Swift + SwiftUI | Planned |
| Apple Watch | Swift + SwiftUI | Planned |
| Web | Next.js + TypeScript | Planned |
| CLI | Rust | Planned |
| Sync Server | Go | Planned |

## Architecture

```text
Master Password
  → Argon2id → Master Unlock Key
    → Wraps per-vault Vault Keys (AES-256-GCM)
      → Each vault encrypts all items within it
```

- **Encryption**: AES-256-GCM, X25519, Argon2id, HKDF-SHA256
- **Auth**: SRP-6a (zero-knowledge — server never sees your password)
- **Shared crypto library**: Rust → native (iOS/macOS/Watch via FFI) + WASM (web)
- **Drug data**: Bundled local index (openFDA + RxNorm) — autocomplete never leaves your device

## Features

### Core

- Medication & supplement tracking (prescriptions, OTC, vitamins, supplements)
- Flexible scheduling & local notifications
- Drug interaction checking (on-device)
- Authoritative drug data with source attribution
- Inventory & supply tracking
- Full data export at any time

### Multi-Profile Vaults

- Personal, dependent (family), and pet medication tracking
- Encrypted vault sharing with role-based access (owner / editor / viewer)
- Vaccination tracker

### Moonshots

- Health signal correlation (Apple Health integration, on-device analysis)
- Performance signal tracking

## Project Documents

- [`docs/roadmap.md`](docs/roadmap.md) — Full product roadmap (assumptions, architecture, features, phased milestones, competitive analysis, monetization)
- [`docs/decisions.md`](docs/decisions.md) — Decision log with rationale for key project choices

## Development

> 🚧 This project is in the planning phase. Development has not started yet.

### Monorepo Structure (Planned)

```text
pildora/
├── crypto/          # Shared Rust encryption library (pildora-crypto)
├── ios/             # iPhone + iPad + Watch app (SwiftUI)
├── web/             # Web app (Next.js)
├── cli/             # CLI tool (Rust)
├── server/          # Sync server (Go)
├── data/            # Drug data ETL pipeline (Python)
├── docs/            # Project documentation
└── .github/         # CI/CD workflows
```

### Prerequisites

- Rust (for crypto library + CLI)
- Xcode 16+ (for iOS/iPad/Watch)
- Go 1.22+ (for sync server)
- Node.js 20+ (for web app)
- Python 3.12+ (for data pipeline)

## License

This project is licensed under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0).

This means:

- ✅ You can use, modify, and distribute this software freely
- ✅ You can run it for personal or commercial purposes
- ⚠️ If you modify and distribute it (or run a modified version as a network service), you must release your modifications under AGPL-3.0
- ⚠️ You must preserve copyright notices and license terms

## Disclaimer

Pildora is a tracking and information tool. It does not provide medical advice. All drug data, interaction warnings, and health correlations are informational only and not a substitute for professional medical guidance. Always consult your healthcare provider before making changes to your medication regimen.
