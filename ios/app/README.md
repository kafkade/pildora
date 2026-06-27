# Pildora iOS app

Minimal production-style Xcode app that integrates the Rust crypto library
(`pildora-crypto-ffi`) via an **Xcode Run Script build phase**. Pressing
`Cmd+B` cross-compiles the Rust code for the active SDK/architecture, links the
static library, and runs — no manual script step (resolves
[#41](https://github.com/kafkade/pildora/issues/41)).

> This app is intentionally tiny: it performs an encrypt → decrypt roundtrip
> through the FFI bridge to prove the build integration works end to end. It is
> the foundation the Phase 1 SwiftUI app is built on, not a finished product.

## Prerequisites

- macOS with Xcode 15+ (developed against Xcode 26).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) —
  the `.xcodeproj` is generated from `project.yml`, not committed.
- Rust toolchain with the Apple targets:

  ```bash
  rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
  ```

## Generate the project and build

```bash
cd ios/app
xcodegen generate          # creates Pildora.xcodeproj from project.yml
open Pildora.xcodeproj      # then press Cmd+B / Cmd+R
```

Or from the command line:

```bash
xcodebuild -project Pildora.xcodeproj -scheme Pildora \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

## How the build phase works

The target has one pre-build Run Script phase, **Build Rust crypto
(pildora-crypto-ffi)**, that runs [`Scripts/cargo-build-phase.sh`](Scripts/cargo-build-phase.sh).
Driven entirely by the environment Xcode exports, it:

1. Reads `$PLATFORM_NAME` (`iphoneos` / `iphonesimulator` / …) and each value in
   `$ARCHS`, and maps them to a Rust target triple:

   | Platform | Arch | Rust target |
   |---|---|---|
   | `iphoneos` | `arm64` | `aarch64-apple-ios` |
   | `iphonesimulator` | `arm64` | `aarch64-apple-ios-sim` |
   | `iphonesimulator` | `x86_64` | `x86_64-apple-ios` |

   (`macosx`, `watchos`, and `watchsimulator` are also mapped for future use.)
2. Maps `$CONFIGURATION` → cargo profile (`Release` builds with `--release`).
3. Runs `cargo build -p pildora-crypto-ffi --target <target>` for each arch.
4. `lipo`-combines multiple arch slices into one `libpildora_crypto_ffi.a`.
5. Copies the result into `$BUILT_PRODUCTS_DIR`, where the linker finds it via
   `LIBRARY_SEARCH_PATHS` + `OTHER_LDFLAGS = -lpildora_crypto_ffi`.

The script can also be run standalone for debugging by exporting the same
variables:

```bash
PLATFORM_NAME=iphonesimulator ARCHS=arm64 CONFIGURATION=Debug \
  BUILT_PRODUCTS_DIR=/tmp/out SRCROOT="$PWD" bash Scripts/cargo-build-phase.sh
```

### Incremental builds

`cargo` provides the real incremental compilation: the phase is a fast no-op
(typically well under a second) when no Rust source changed. The phase is
configured with **"Based on dependency analysis" unchecked** so it always runs
and lets cargo decide — this avoids stale builds when a new `.rs` file is added
that a static Xcode input file list would miss. The staged `.a` is declared as
the phase's output so the linker correctly depends on it.

> Alternative: if you prefer Xcode to gate the phase, populate an
> `.xcfilelist` of the Rust sources and wire it as `inputFileListPaths`
> (`SCRIPT_INPUT_FILE_LIST`) in `project.yml`, and re-enable dependency
> analysis.

### Sandboxing

`ENABLE_USER_SCRIPT_SANDBOXING = NO` is required: the phase shells out to
`cargo`, which reads the workspace and writes to `target/` outside the target's
sandbox.

## UniFFI Swift bindings

The Swift bindings under [`Pildora/Generated/`](Pildora/Generated/) are produced
by UniFFI and **committed**, so a fresh checkout builds without a manual
pre-step. The per-build phase only cross-compiles the static library.

Regenerate the bindings only when the Rust FFI surface
(`crypto-uniffi/src/`) changes:

```bash
cd ios/app
./Scripts/generate-bindings.sh
```

This produces `pildora_crypto_ffi.swift` (Swift bindings),
`pildora_crypto_ffiFFI.h` (C header), and `module.modulemap`. The Swift importer
finds the `pildora_crypto_ffiFFI` module via
`SWIFT_INCLUDE_PATHS = $(SRCROOT)/Pildora/Generated`.

## Relationship to `build-xcframework.sh`

[`../ffi-spike/build-xcframework.sh`](../ffi-spike/build-xcframework.sh) is
retained for CI (the **FFI (macOS)** job) and the pre-built XCFramework
distribution path. This app is the local-developer build integration: Rust is
compiled as part of the normal Xcode build instead of a separate artifact step.
