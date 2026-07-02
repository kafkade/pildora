# watchOS FFI Spike: `pildora-crypto-ffi` on watchOS

Validates that `pildora-crypto-ffi` (the UniFFI static library) compiles, links,
and runs on watchOS architectures. Follow-up to the iOS FFI spike
([`../ffi-spike`](../ffi-spike/), issue #21) and closes issue #42.

See [ADR-007](../../docs/adr/007-rust-swift-ffi-bridge.md) for the FFI decision
record.

## Quick start (macOS only)

### Prerequisites

- macOS with Xcode 15+ and the **watchOS SDK** + a **watchOS simulator runtime**
- Rust toolchain (stable). The watchOS targets are installed automatically by
  the build script, or manually:

  ```bash
  rustup target add aarch64-apple-watchos aarch64-apple-watchos-sim
  ```

### Run

```bash
# From the repo root — builds the XCFramework (with watchOS slices),
# stages bindings, boots a watchOS simulator, and runs the tests.
./ios/watchos-ffi-spike/run-watchos-tests.sh
```

## What this validates (spike questions from #42)

| Question | Answer |
|---|---|
| Does `pildora-crypto-ffi` compile for watchOS? | ✅ **Yes on stable Rust** for `aarch64-apple-watchos` (device) and `aarch64-apple-watchos-sim` (simulator). |
| Do the UniFFI Swift bindings work on watchOS? | ✅ Yes — the same generated bindings compile and the encrypt/decrypt roundtrip runs on the watchOS simulator. |
| Does Argon2id 64 MiB work on Apple Watch? | ⚠️ **Unverified on real hardware.** The simulator uses host RAM and cannot exercise the watch memory ceiling. A reduced-parameter fallback is available and tested (see below). |
| Can the XCFramework include watchOS slices? | ✅ Yes — `build-xcframework.sh` now emits `watchos-arm64` + `watchos-arm64-simulator` alongside the iOS slices. |

## Architecture support & the `arm64_32` follow-up

| watchOS Rust target | Apple Watch models | Toolchain | Status |
|---|---|---|---|
| `aarch64-apple-watchos` | Series 9+, Ultra 2+ (device) | **stable** (`rustup target add`) | ✅ Built + packaged |
| `aarch64-apple-watchos-sim` | simulator (Apple Silicon) | **stable** | ✅ Built + packaged + tested |
| `arm64_32-apple-watchos` | Series 4–8 (device) | **nightly + `-Zbuild-std`** (Tier 3) | ⛔ Not built here — see below |
| `armv7k-apple-watchos` | Series 3 & earlier | Tier 3 | N/A — below the watchOS 10+ floor |

> **Follow-up decision (deferred).** `docs/roadmap.md` sets a watchOS 10+ floor,
> which still includes Apple Watch Series 4–8. Those watches run the 32-bit
> pointer target `arm64_32-apple-watchos`, which is Tier 3 in Rust: there is no
> prebuilt `std`, so it requires a **nightly** toolchain built with
> `-Zbuild-std`. This spike deliberately validates only the stable `arm64`
> targets. Before shipping the watch app, the maintainer must choose one of:
>
> 1. **Adopt nightly + `-Zbuild-std`** in the Xcode build phase and CI to cover
>    Series 4–8 (`cargo build -Z build-std=std,panic_abort --target
>    arm64_32-apple-watchos`), or
> 2. **Raise the watch deployment floor to Series 9+** (arm64 only) and stay on
>    stable Rust.
>
> `ios/app/Scripts/cargo-build-phase.sh` already maps `arm64_32` → the Rust
> triple, so on a Series 4–8 build it will currently fail until option 1 is
> configured.

## Argon2id on watchOS

The default parameters are 64 MiB memory, 3 iterations, parallelism 1
(ADR-001). Third-party watchOS apps run under tight memory limits, so a 64 MiB
allocation may be rejected on-device even though it succeeds in the simulator
(which uses host RAM).

- `testDefaultArgon2idTimingSample` prints a simulator timing sample — **for
  reference only**, not a memory-ceiling test.
- `testReducedArgon2idParamsDeriveValidKey` verifies that a constrained profile
  (e.g. 16 MiB) still derives a valid, deterministic 32-byte key via
  `deriveMasterKeyWithParams(...)`.

**Requirement:** because different Argon2id parameters produce a different key
for the same password, the parameters used **must be persisted in vault
metadata** so the key can be re-derived on unlock. If the watch app ever uses a
reduced profile, it must read the parameters stored at vault creation — never
assume the default.

**Action before shipping:** profile `deriveMasterKey` on a physical Apple Watch
to confirm whether 64 MiB is viable, and pick a shared parameter set if not.

## Files

| File | Purpose |
|---|---|
| `run-watchos-tests.sh` | Builds the XCFramework, stages bindings, boots a watchOS simulator, runs `xcodebuild test` |
| `PildoraCryptoWatchSpike/Package.swift` | SwiftPM package: watchOS platform, XCFramework binary target, XCTest target |
| `PildoraCryptoWatchSpike/Tests/PildoraCryptoWatchTests/CryptoFFITests.swift` | FFI validation tests (encrypt/decrypt, wrap/unwrap, sqlcipher key, Argon2id) |

The XCFramework and generated bindings are shared with
[`../ffi-spike`](../ffi-spike/) and produced by
`../ffi-spike/build-xcframework.sh` (both are git-ignored build output).

## Dependencies

- Implements: [#42](https://github.com/kafkade/pildora/issues/42)
- Builds on: [#21](https://github.com/kafkade/pildora/issues/21) (iOS FFI spike)
