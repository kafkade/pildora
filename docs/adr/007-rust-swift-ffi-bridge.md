# ADR-007: Rust-to-Swift FFI Bridge

**Status:** Accepted
**Date:** 2026-05-29

## Context

Pildora's architecture depends on a single Rust crypto library (`pildora-crypto`)
compiled for every platform (ADR-001). The iOS/iPadOS/watchOS apps (Swift +
SwiftUI) need to call this library for key derivation, encryption, and
decryption. We need to choose an FFI bridging strategy that:

1. Provides a natural Swift developer experience
2. Adds minimal per-call overhead (target: <1 ms)
3. Handles memory management safely across the Rust/Swift boundary
4. Integrates cleanly into the Xcode build pipeline
5. Can be packaged as a Swift Package for distribution

## Decision

### Use UniFFI with proc macros in a dedicated `crypto-uniffi` crate

We chose [UniFFI](https://mozilla.github.io/uniffi-rs/) (Mozilla's multi-language
bindings generator) over cbindgen for the Rust → Swift bridge.

The FFI bridge lives in a **separate crate** (`pildora-crypto-ffi`) rather than
behind a feature flag in `pildora-crypto`. This preserves the core crypto
crate's `unsafe_code = "deny"` invariant — UniFFI's generated `extern "C"`
scaffolding necessarily uses unsafe, and isolating it keeps the audit surface
clean.

### UniFFI vs cbindgen

| Criterion | UniFFI | cbindgen |
|---|---|---|
| Swift DX | Generates idiomatic Swift types, enums, errors | Raw C pointers; manual Swift wrapper required |
| Error handling | Maps Rust `Result<T, E>` → Swift `throws` | Manual error code + out-parameter |
| Memory management | Automatic reference counting across boundary | Manual `free()` calls required |
| Type richness | Records, enums, strings, byte arrays, optionals | C-compatible types only |
| Setup complexity | Proc macros + bindgen CLI | Header generation only (simpler) |
| Kotlin support | Built-in (future Android port) | Not applicable |
| Community | Active Mozilla project; standard for Rust → mobile | Stable but lower-level |

**UniFFI wins on developer experience and correctness.** The automatic memory
management and error bridging eliminate an entire class of use-after-free and
leak bugs that cbindgen would require manual handling for.

### Architecture

```text
┌─────────────────────────────────────────┐
│             Swift / SwiftUI             │
│  (PildoraCrypto Swift Package)          │
├─────────────────────────────────────────┤
│    Generated UniFFI Swift bindings      │
│    (pildora_crypto_ffiFFI.swift)        │
├─────────────────────────────────────────┤
│    UniFFI scaffolding (extern "C")      │
│    (pildora-crypto-ffi crate)           │
├─────────────────────────────────────────┤
│         pildora-crypto (safe Rust)      │
│    AES-256-GCM · Argon2id · HKDF · …   │
└─────────────────────────────────────────┘
```

### Memory management

- **Byte arrays** cross the boundary as `Vec<u8>` (Rust) ↔ `Data` (Swift).
  UniFFI handles allocation/deallocation on both sides.
- **Strings** cross as `String` (Rust) ↔ `String` (Swift) with automatic
  UTF-8 validation.
- **Errors** are transmitted as UniFFI `Error` enums, mapped to Swift's
  `throws` mechanism.
- **No raw pointers** are exposed in the public API.

### Build integration

The Rust library is compiled for Apple targets and packaged as an XCFramework:

```bash
# Cross-compile for device and simulator
cargo build -p pildora-crypto-ffi --target aarch64-apple-ios --release
cargo build -p pildora-crypto-ffi --target aarch64-apple-ios-sim --release

# Generate Swift bindings from macOS build
cargo build -p pildora-crypto-ffi --release
cargo run -p pildora-crypto-ffi --features bindgen --bin uniffi-bindgen -- \
    generate --library target/release/libpildora_crypto_ffi.dylib \
    --language swift --out-dir generated/

# Package as XCFramework
xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libpildora_crypto_ffi.a \
        -headers generated/ \
    -library target/aarch64-apple-ios-sim/release/libpildora_crypto_ffi.a \
        -headers generated/ \
    -output PildoraCryptoFFI.xcframework
```

The XCFramework is consumed as a Swift Package binary target, or embedded
directly in the Xcode project via a Run Script build phase.

### Swift Package structure

```text
PildoraCrypto/
  Package.swift           # SPM manifest
  Sources/
    PildoraCrypto/
      PildoraCrypto.swift  # High-level Swift API (optional convenience layer)
  generated/
    pildora_crypto_ffi.swift      # UniFFI-generated bindings
    pildora_crypto_ffiFFI.h       # C header
    pildora_crypto_ffiFFI.modulemap
```

### Performance

FFI call overhead targets (validated during spike):

| Operation | Target | Notes |
|---|---|---|
| `generate_salt()` | <0.1 ms | No allocation beyond 16 bytes |
| `generate_vault_key()` | <0.1 ms | 32-byte random key |
| `item_encrypt` (1 KB) | <1 ms | AES-256-GCM + key wrapping |
| `item_decrypt` (1 KB) | <1 ms | AES-256-GCM + key unwrapping |
| `derive_master_key` | ~500 ms | Argon2id 64 MiB (intentionally slow) |

The per-call FFI overhead (data marshaling across boundary) is negligible
compared to the cryptographic operations themselves. UniFFI adds approximately
1–5 µs per call for argument serialization/deserialization.

## Security considerations

### Swift memory lifecycle

UniFFI handles memory allocation and deallocation, but **Swift `Data` and
`[UInt8]` are not guaranteed to be zeroized on deallocation.** Key material
that crosses the FFI boundary into Swift memory may persist in deallocated
pages.

**Production hardening items:**

- Wrap sensitive byte arrays in a Swift type that calls `memset_s` /
  `bzero` on `deinit`
- Use `withUnsafeMutableBytes` for in-place operations where possible
- Minimize the lifetime of decrypted plaintext in Swift memory
- Document which API calls return sensitive material

This is acceptable for the initial implementation since iOS provides hardware
memory encryption (Secure Enclave) and per-app address space isolation. It
should be addressed before production launch.

**Resolution (issue #40):** the
[`PildoraSecureMemory`](../../ios/secure-memory/PildoraSecureMemory/) package
provides `SecureBytes`, a move-only (`~Copyable`) wrapper that securely zeroizes
key material on `deinit`, exposes scoped `withUnsafeBytes` /
`withUnsafeMutableBytes` accessors, and documents which FFI calls return
sensitive material. It should be adopted at the FFI call sites when the iOS app
target is assembled.

## Alternatives considered

**cbindgen (C header generation):** Lower-level, requires manual Swift
wrappers, manual memory management, and manual error handling. More flexible
but significantly higher implementation effort and higher risk of memory bugs.

**Feature flag in pildora-crypto:** Simpler single-crate approach, but would
require allowing `unsafe` in the core crypto crate — weakening its safety
guarantees and complicating auditing.

**Swift CryptoKit (rewrite crypto in Swift):** Rejected in ADR-001. A second
implementation of the same crypto spec increases divergence risk and doubles
the audit surface.

## Consequences

- The `pildora-crypto-ffi` crate is now a workspace member and must be kept in
  sync with `pildora-crypto` API changes.
- Rust cross-compilation toolchains for Apple targets (`aarch64-apple-ios`,
  `aarch64-apple-ios-sim`) are required for iOS builds.
- The UniFFI bindgen step must run on macOS (loads the compiled `.dylib`).
- CI should include a macOS job that validates FFI compilation and binding
  generation.
- Future Kotlin/Android support can reuse the same `pildora-crypto-ffi` crate
  with UniFFI's Kotlin backend.
