# FFI Spike: Rust → Swift via UniFFI

Technical spike validating that `pildora-crypto` can be called from Swift via
FFI. See [ADR-007](../../docs/adr/007-rust-swift-ffi-bridge.md) for the full
decision record.

## Quick start (macOS only)

### Prerequisites

- macOS with Xcode 15+ and command-line tools
- Rust toolchain with Apple targets:

  ```bash
  rustup target add aarch64-apple-ios aarch64-apple-ios-sim
  ```

### Build and run

```bash
# 1. From the repo root, build the XCFramework + generate Swift bindings
./ios/ffi-spike/build-xcframework.sh

# 2. Copy generated bindings into the spike app sources
cp ios/ffi-spike/generated/pildora_crypto_ffi.swift \
   ios/ffi-spike/PildoraCryptoSpike/Sources/

# 3. Run the spike
cd ios/ffi-spike/PildoraCryptoSpike
swift run
```

## What this validates

| Question | Answer |
|---|---|
| UniFFI vs cbindgen? | UniFFI — better Swift DX, automatic memory management |
| FFI overhead? | ~1–5 µs per call (well under 1 ms target) |
| Memory management? | UniFFI handles allocation/deallocation across boundary |
| Build integration? | `cargo build` → `uniffi-bindgen` → `xcodebuild -create-xcframework` |
| Swift Package? | Yes, XCFramework as SPM binary target |

## Architecture

```text
┌─────────────────────────────┐
│  PildoraCryptoSpike (Swift) │   ← This spike app
├─────────────────────────────┤
│  UniFFI-generated bindings  │   ← Auto-generated Swift code
├─────────────────────────────┤
│  pildora-crypto-ffi (Rust)  │   ← Thin FFI wrapper crate
├─────────────────────────────┤
│  pildora-crypto (safe Rust) │   ← Core crypto library
└─────────────────────────────┘
```

## Files

| File | Purpose |
|---|---|
| `build-xcframework.sh` | Builds Rust for Apple targets, generates Swift bindings, packages XCFramework |
| `PildoraCryptoSpike/` | Swift Package executable that tests FFI bridge + benchmarks |
| `generated/` | (created by build script) UniFFI-generated Swift bindings + C header |
| `PildoraCryptoFFI.xcframework/` | (created by build script) Universal XCFramework |

## Production hardening notes

This spike proves the FFI bridge works. Before production use:

- **Swift memory zeroization**: `Data` and `[UInt8]` in Swift are not
  guaranteed to be zeroized on deallocation. Sensitive key material should be
  wrapped in a Swift type that explicitly clears memory on `deinit`.
- **Xcode build phase**: Replace the standalone build script with an Xcode Run
  Script build phase that cross-compiles Rust as part of the normal build.
- **CI**: Add a macOS CI job that validates FFI compilation and binding
  generation.
- **watchOS**: Validate that the `staticlib` links correctly on watchOS
  (armv7k and arm64_32 architectures).

## Dependencies

- Blocked by: [#8](https://github.com/kafkade/pildora/issues/8) (item
  encryption — need a working crypto API to bridge)
- Implements: [#21](https://github.com/kafkade/pildora/issues/21)
