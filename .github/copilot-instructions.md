# Copilot Instructions for Pildora

## Project Overview

Pildora is a zero-knowledge encrypted medication and supplement tracker. "Meds" always means both prescription/OTC medications AND dietary supplements/vitamins. The project is currently in the planning stage — no working software exists yet, only documentation and repo structure.

## Non-Negotiable Constraints

Every code contribution, architecture decision, and feature design must uphold these:

1. **Zero-knowledge E2E encryption** — User health data is encrypted on-device before any sync. The server must never see plaintext health data. There is no phase where plaintext user data exists on a server.
2. **User data ownership** — Never monetize, sell, share, or mine user data.
3. **No medical advice** — The app is a tracking/information tool. All drug data, interaction warnings, and health correlations must include disclaimers. Never generate dosing recommendations or diagnostic suggestions.
4. **Local-first** — The app must work fully offline. Cloud sync is optional and always encrypted.

## Architecture

Monorepo with 6 components sharing a single crypto library:

- `crypto/` — Shared Rust encryption library (`pildora-crypto`). Compiled to native (iOS/macOS/Watch via FFI) and WASM (web). This is the critical path dependency for all other components.
- `ios/` — iPhone + iPad + Watch apps (Swift + SwiftUI, shared codebase)
- `web/` — Web app (Next.js + TypeScript, uses crypto via WASM)
- `cli/` — CLI tool (Rust, shares crypto crate directly)
- `server/` — Sync server (Rust + Axum). Thin — stores/retrieves encrypted blobs only. Cannot read user data.
- `data/` — Drug data ETL pipeline (Python). Builds bundled local SQLite index from openFDA + RxNorm.

### Encryption Model

```text
Master Password → Argon2id → Master Unlock Key (MUK)
  → MUK wraps per-vault Vault Keys (AES-256-GCM)
    → Each Vault Key encrypts all items within that vault
```

Key primitives: AES-256-GCM, X25519, Argon2id, HKDF-SHA256, SRP-6a.

### Data Boundary Rule

| Data Type | Encryption | Where Processed |
|---|---|---|
| User health data (meds, schedules, doses, inventory) | Encrypted (per-vault key) | On-device only |
| Drug reference data (FDA, RxNorm, interactions) | Plaintext (public data) | Bundled locally or CDN |
| Drug autocomplete queries | N/A | Local index only — never sent to server |
| Interaction checking | N/A | On-device against local database |
| OCR (prescription labels) | N/A | On-device only (Apple Vision) |
| Health correlations (moonshot) | Encrypted | On-device only (Core ML) |

### Notifications

Local notifications only (no server-side push for dose reminders). This preserves zero-knowledge — the server never knows when doses are scheduled. iOS supports 64 scheduled local notifications, which is sufficient for most users.

## Feature Risk Classification

When proposing or implementing features that touch health data, classify them:

- 🟢 **Low risk** — Pure tracking, no clinical interpretation
- 🟡 **Informational** — Displays published reference data with source attribution
- 🔴 **Medically sensitive** — Could be interpreted as clinical guidance; requires legal review
- ⛔ **Not recommended** — Regulatory or liability risk too high (e.g., dosing recommendations, diagnostic suggestions)

## Conventions

- **License**: AGPL-3.0 — all contributions must be compatible
- **Vault architecture**: Design all data models with multi-vault support from day one, even if multi-vault UX ships later. One vault = one encryption boundary.
- **Disclaimers**: Every piece of drug reference data displayed must show source + date. Interaction warnings must include "This is informational only. Consult your healthcare provider."
- **Privacy metadata**: When adding any feature that communicates with a server, document what metadata is exposed (timing, IP, blob sizes) and how it's mitigated.
- **PR title format**: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`

## Git Policy

**Never execute Git commands that modify history or submit code.** This includes `git commit`, `git push`, `git rebase`, `git merge`, `git reset`, `git cherry-pick`, `git revert`, and `git tag`. Read-only commands like `git status`, `git diff`, `git log`, and `git branch` are fine. The maintainer must always review and commit changes themselves.

## CI / Infrastructure Dependency

**Branch protection for this repo is managed via Terraform in `kafkade/github-infra` (`repo_pildora.tf`).** The `required_status_checks` list must match the job names in `.github/workflows/validate.yml`. If you rename, add, or remove CI jobs that are used as merge gates (currently `Validate`), the corresponding IaC config must be updated or PRs will be permanently blocked. Always flag this when proposing workflow changes.

## Reference Documents

The full product roadmap with architecture decisions, data model, competitive analysis, and phased milestones is in `docs/roadmap.md`.
