#!/usr/bin/env bash
# build-xcframework.sh — Build pildora-crypto-ffi for Apple targets and
# generate Swift bindings + XCFramework.
#
# Prerequisites:
#   - macOS with Xcode command-line tools
#   - Rust toolchain with Apple targets:
#       rustup target add aarch64-apple-ios aarch64-apple-ios-sim
#     watchOS slices additionally need (auto-installed by this script if the
#     watchOS SDK is present):
#       rustup target add aarch64-apple-watchos aarch64-apple-watchos-sim
#   - The pildora workspace must be built at least once:
#       cargo build -p pildora-crypto-ffi
#
# Usage:
#   cd <repo-root>
#   ./ios/ffi-spike/build-xcframework.sh
#
# Output:
#   ios/ffi-spike/generated/           — Swift bindings + C header + modulemap
#   ios/ffi-spike/PildoraCryptoFFI.xcframework/  — Universal XCFramework
#
# watchOS support (issue #42):
#   The XCFramework includes watchOS device (aarch64-apple-watchos) and watchOS
#   simulator (aarch64-apple-watchos-sim) slices when the watchOS SDK is
#   installed. Both build on *stable* Rust. Apple Watch Series 4–8 use the
#   arm64_32-apple-watchos target, which is Tier 3 and requires a nightly
#   toolchain with `-Zbuild-std`; it is intentionally NOT built here. See
#   ios/watchos-ffi-spike/README.md for the full validation and the arm64_32
#   follow-up decision.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPIKE_DIR="$REPO_ROOT/ios/ffi-spike"
GENERATED_DIR="$SPIKE_DIR/generated"
XCFRAMEWORK_DIR="$SPIKE_DIR/PildoraCryptoFFI.xcframework"
LIB_A="libpildora_crypto_ffi.a"

# ── Rust targets ─────────────────────────────────────────────────────────────
# iOS slices are always built. watchOS slices are added when the watchOS SDK is
# available (detected below).
IOS_TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim)
WATCHOS_TARGETS=(aarch64-apple-watchos aarch64-apple-watchos-sim)

have_watchos_sdk() {
    xcodebuild -showsdks 2>/dev/null | grep -qiE 'watchos'
}

ensure_target() {
    local target="$1"
    if ! rustup target list --installed 2>/dev/null | grep -qx "$target"; then
        echo "==> Installing Rust target $target..."
        rustup target add "$target"
    fi
}

# Collect the targets we will actually build.
BUILD_TARGETS=("${IOS_TARGETS[@]}")
if have_watchos_sdk; then
    echo "==> watchOS SDK detected — including watchOS slices."
    BUILD_TARGETS+=("${WATCHOS_TARGETS[@]}")
else
    echo "==> watchOS SDK not found — building iOS slices only."
    echo "    (Install Xcode's watchOS SDK to include watchOS in the XCFramework.)"
fi

# ── Build the host dylib (needed for uniffi-bindgen) ─────────────────────────
echo "==> Building pildora-crypto-ffi for macOS (host)..."
cargo build -p pildora-crypto-ffi --release

# ── Cross-compile each Apple target ──────────────────────────────────────────
for target in "${BUILD_TARGETS[@]}"; do
    ensure_target "$target"
    echo "==> Building pildora-crypto-ffi for $target (release)..."
    cargo build -p pildora-crypto-ffi --target "$target" --release
done

# ── Generate Swift bindings ──────────────────────────────────────────────────
echo "==> Generating Swift bindings..."
mkdir -p "$GENERATED_DIR"
cargo run -p pildora-crypto-ffi --features bindgen --bin uniffi-bindgen -- \
    generate \
    --library "$REPO_ROOT/target/release/libpildora_crypto_ffi.dylib" \
    --language swift \
    --out-dir "$GENERATED_DIR"

# ── Package XCFramework ──────────────────────────────────────────────────────
echo "==> Packaging XCFramework..."
rm -rf "$XCFRAMEWORK_DIR"

# Stage a per-target directory containing the static lib + a Headers/ dir with
# the C header and modulemap, then append the -library/-headers args for it.
TMP_DIRS=()
XCFRAMEWORK_ARGS=()
stage_slice() {
    local target="$1"
    local slice_lib="$REPO_ROOT/target/$target/release/$LIB_A"
    if [ ! -f "$slice_lib" ]; then
        echo "error: expected static lib not found: $slice_lib" >&2
        exit 1
    fi
    local dir
    dir="$(mktemp -d)"
    TMP_DIRS+=("$dir")
    cp "$slice_lib" "$dir/"
    mkdir -p "$dir/Headers"
    cp "$GENERATED_DIR/pildora_crypto_ffiFFI.h" "$dir/Headers/"
    cp "$GENERATED_DIR/pildora_crypto_ffiFFI.modulemap" "$dir/Headers/module.modulemap"
    XCFRAMEWORK_ARGS+=(-library "$dir/$LIB_A" -headers "$dir/Headers")
}

for target in "${BUILD_TARGETS[@]}"; do
    stage_slice "$target"
done

xcodebuild -create-xcframework \
    "${XCFRAMEWORK_ARGS[@]}" \
    -output "$XCFRAMEWORK_DIR"

# Clean up temp dirs
for dir in "${TMP_DIRS[@]}"; do
    rm -rf "$dir"
done

echo "==> Done!"
echo "    Bindings:     $GENERATED_DIR/"
echo "    XCFramework:  $XCFRAMEWORK_DIR/"
echo "    Slices:       ${BUILD_TARGETS[*]}"
echo ""
echo "Next steps:"
echo "  iOS    : open ios/ffi-spike/PildoraCryptoSpike/Package.swift and run the spike"
echo "  watchOS: ./ios/watchos-ffi-spike/run-watchos-tests.sh"
