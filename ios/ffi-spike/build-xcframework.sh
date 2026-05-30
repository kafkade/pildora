#!/usr/bin/env bash
# build-xcframework.sh — Build pildora-crypto-ffi for Apple targets and
# generate Swift bindings + XCFramework.
#
# Prerequisites:
#   - macOS with Xcode command-line tools
#   - Rust toolchain with Apple targets:
#       rustup target add aarch64-apple-ios aarch64-apple-ios-sim
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

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPIKE_DIR="$REPO_ROOT/ios/ffi-spike"
GENERATED_DIR="$SPIKE_DIR/generated"
XCFRAMEWORK_DIR="$SPIKE_DIR/PildoraCryptoFFI.xcframework"

echo "==> Building pildora-crypto-ffi for macOS (host)..."
cargo build -p pildora-crypto-ffi --release

echo "==> Building pildora-crypto-ffi for aarch64-apple-ios (device)..."
cargo build -p pildora-crypto-ffi --target aarch64-apple-ios --release

echo "==> Building pildora-crypto-ffi for aarch64-apple-ios-sim (simulator)..."
cargo build -p pildora-crypto-ffi --target aarch64-apple-ios-sim --release

echo "==> Generating Swift bindings..."
mkdir -p "$GENERATED_DIR"
cargo run -p pildora-crypto-ffi --features bindgen --bin uniffi-bindgen -- \
    generate \
    --library "$REPO_ROOT/target/release/libpildora_crypto_ffi.dylib" \
    --language swift \
    --out-dir "$GENERATED_DIR"

echo "==> Packaging XCFramework..."
rm -rf "$XCFRAMEWORK_DIR"

# Create temporary directories with headers for xcodebuild
DEVICE_DIR=$(mktemp -d)
SIM_DIR=$(mktemp -d)

cp "$REPO_ROOT/target/aarch64-apple-ios/release/libpildora_crypto_ffi.a" "$DEVICE_DIR/"
mkdir -p "$DEVICE_DIR/Headers"
cp "$GENERATED_DIR/pildora_crypto_ffiFFI.h" "$DEVICE_DIR/Headers/"
cp "$GENERATED_DIR/pildora_crypto_ffiFFI.modulemap" "$DEVICE_DIR/Headers/module.modulemap"

cp "$REPO_ROOT/target/aarch64-apple-ios-sim/release/libpildora_crypto_ffi.a" "$SIM_DIR/"
mkdir -p "$SIM_DIR/Headers"
cp "$GENERATED_DIR/pildora_crypto_ffiFFI.h" "$SIM_DIR/Headers/"
cp "$GENERATED_DIR/pildora_crypto_ffiFFI.modulemap" "$SIM_DIR/Headers/module.modulemap"

xcodebuild -create-xcframework \
    -library "$DEVICE_DIR/libpildora_crypto_ffi.a" \
        -headers "$DEVICE_DIR/Headers" \
    -library "$SIM_DIR/libpildora_crypto_ffi.a" \
        -headers "$SIM_DIR/Headers" \
    -output "$XCFRAMEWORK_DIR"

# Clean up temp dirs
rm -rf "$DEVICE_DIR" "$SIM_DIR"

echo "==> Done!"
echo "    Bindings:     $GENERATED_DIR/"
echo "    XCFramework:  $XCFRAMEWORK_DIR/"
echo ""
echo "Next steps:"
echo "  1. Open ios/ffi-spike/PildoraCryptoSpike/Package.swift in Xcode"
echo "  2. Run the spike app to validate encrypt/decrypt roundtrip"
