# ADR-006: Tech Stack Consolidation

**Status:** Accepted
**Date:** 2026-04-25
**Supersedes:** Roadmap Section 8 (tech stack recommendations)

## Context

The original roadmap recommended 5 programming languages across 6 components:
Rust (crypto), Swift (iOS), Go (server), TypeScript (CLI, web, server alt),
and Python (data pipeline). For a solo developer, this spread is unsustainable
— each additional language adds toolchain complexity, context-switching cost,
and maintenance burden.

Additionally, the roadmap and ADR-001 had a conflict: ADR-001 chose Rust for
the shared crypto library, while the roadmap recommended TypeScript for the
CLI and Go for the sync server. With the CLI moved to Phase 0 as the first
consumer of the Rust crypto crate, the Rust-heavy direction was already
emerging.

## Decision

**Consolidate to 3 primary languages, maximizing Rust:**

| Component | Language | Framework / Tooling |
|---|---|---|
| `crypto/` | Rust | RustCrypto crates or ring, compiled to native + WASM |
| `cli/` | Rust | clap (CLI parsing), ratatui (TUI), shares crypto crate |
| `server/` | Rust | Axum (HTTP), SQLx (database), shares crypto crate |
| `ios/` | Swift | SwiftUI, pildora-crypto via FFI (UniFFI or cbindgen) |
| `web/` | TypeScript | Next.js + React, pildora-crypto via WASM |
| `data/` | Python | ETL scripts (openFDA, RxNorm), batch processing |

**Rust** covers 3 of 6 components and the shared crypto core used by all
platforms. **Swift** is non-negotiable for Apple platforms (HealthKit, Keychain,
Watch). **TypeScript** handles the web app where the React/Next.js ecosystem
is vastly more mature than Rust WASM UI frameworks. **Python** remains for the
drug data ETL pipeline where it excels at data wrangling.

### Changes from previous plans

| Component | Before | After | Rationale |
|---|---|---|---|
| CLI | TypeScript + Commander.js | Rust + clap | Shares crypto crate directly, no FFI layer |
| Server | Go (Hono was an alt) | Rust + Axum | Eliminates Go from the stack entirely; Axum is production-grade |
| Web | TypeScript + Next.js | TypeScript + Next.js | Unchanged — but crypto runs as WASM, not JS reimplementation |
| Data | Python | Python | Unchanged — best tool for ETL |
| Crypto | Rust | Rust | Unchanged |

### Why not Rust WASM for the web UI?

Evaluated Leptos, Dioxus, and Yew. All are promising but have blocking issues
for a solo developer shipping a product:

1. **SSR/SEO** — marketing pages need server-side rendering. Next.js handles
   this maturely; Rust WASM SSR is still maturing.
2. **Browser API integration** — WebCrypto, IndexedDB, service workers, and
   offline support are JS-first APIs. Orchestrating them from Rust adds
   friction without clear benefit.
3. **Ecosystem** — React has vastly more component libraries, accessibility
   tooling, and battle-tested patterns for forms, auth flows, and responsive
   design.
4. **Cognitive budget** — already learning Swift for iOS. Adding a less mature
   Rust web framework is avoidable risk.

The crypto-heavy work (encryption, key derivation, vault operations) runs in
Rust WASM. The UI shell, routing, SSR, and browser integration use TypeScript.
This captures the main benefit (shared crypto implementation) without the risk.

### Server: why Rust + Axum over Go

1. **Language elimination** — Go was the only reason Go was in the stack. Axum
   is a mature, production-grade HTTP framework for Rust.
2. **Shared crate access** — the server can import `pildora-crypto` directly
   for SRP-6a verification and encrypted blob validation, with no FFI layer.
3. **Deployment** — compiles to a single static binary. Deploy anywhere:
   Docker, Fly.io, Railway, bare metal.
4. **Type safety** — Rust's type system catches more bugs at compile time than
   Go's interface-based approach.

The server is intentionally thin (store/retrieve encrypted blobs, SRP auth).
Axum handles this with minimal code.

## Consequences

- **Cargo workspace** encompasses `crypto/`, `cli/`, and `server/` — all
  share dependencies and build together.
- **Two build systems:** Cargo (Rust) and Swift Package Manager (Apple). No
  pnpm workspaces needed since the TypeScript CLI was eliminated.
- **Web app** uses pnpm/npm for Next.js, with pildora-crypto WASM as an npm
  package (built from the Cargo workspace).
- **CI/CD** needs Rust + Python + Node.js runners. No Go toolchain.
- The monorepo structure in the roadmap (Section 8) is superseded by this ADR.
