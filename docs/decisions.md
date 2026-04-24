# Decision Log

Key project decisions with rationale. Newest first.

## 2026-04-24 — Markdown Linting Configuration

**Decision:** Disable MD060 (table pipe spacing) in markdownlint config.

**Context:** markdownlint v0.40 introduced MD060 which enforces spacing around
table pipes. This flagged 254 errors across the repo for compact GFM tables
like `|---|---|` which are valid and widely used.

**Rationale:** Compact pipe style is intentional and renders correctly on
GitHub. Enforcing spacing would bloat tables without improving readability.

## 2026-04-24 — Repository Infrastructure

**Decision:** Adopt PR template with privacy checklist, issue templates with
component selectors, Copilot skills for markdown linting and PR preparation.

**Context:** Modeled after existing kafkade projects (Kite, Anvil) with
Pildora-specific additions.

**Pildora-specific additions:**

- PR template includes a **Privacy Checklist** requiring every PR to confirm
  zero-knowledge compliance
- Feature request template warns that features requiring server access to
  plaintext data will not be accepted
- Bug report template warns against including personal health data in logs
- Copilot instructions encode the encryption model and data boundary rules so
  every AI session starts with the right constraints

## 2026-04-24 — License: AGPL-3.0

**Decision:** License the entire project under AGPL-3.0 (GNU Affero General
Public License v3.0).

**Alternatives considered:**

- **Open core** (crypto MIT, apps closed) — rejected because the primary
  selling point is trust, and partial openness undermines "you can verify
  everything"
- **Source-available** (BSL) — rejected because it discourages community
  contributions
- **Closed source** — rejected because it contradicts the trust-first
  positioning

**Rationale:** Trust is the main competitive advantage. Users should be able to
verify every line of code that handles their health data. AGPL ensures that
anyone running a modified version as a network service must also release their
modifications — preventing competitors from forking and closing the source.

Additionally, this project serves as a career showcase. A fully open-source,
well-architected multi-platform health app with E2E encryption demonstrates
skills better than closed-source work nobody can see.

Revenue is not the primary goal. The Bitwarden model (AGPL + paid managed
hosting) proves that full open-source and sustainable revenue are compatible.

## 2026-04-24 — Project Name: Pildora

**Decision:** Name the project "Pildora."

**Meaning:** Spanish for "pill." Subtle, personal, culturally rooted. Does not
explicitly call out encryption or medication tracking in the name — the brand
communicates warmth and personal ownership rather than clinical function.

**Domain availability (checked 2026-04-24):**

- pildora.com — taken
- pildora.app — available
- pildora.io — available
- pildora.dev — available
- pildora.health — available

**Name requirements met:**

- Works as a CLI command: `pildora`
- Works as an App Store listing
- Spans medications and supplements without sounding clinical
- Short, memorable, globally pronounceable

**Alternatives rejected:** MedVault (medvault.com taken, "vault" overused in
tech), DoseKey, Capsule (too common), Remedium (pronunciation issues),
various invented names (Tendwell, Sanalok, Klovida — felt too artificial).
