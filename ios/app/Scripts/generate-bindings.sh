#!/usr/bin/env bash
# generate-bindings.sh — Generate the UniFFI Swift bindings for
# pildora-crypto-ffi and stage them under ios/app/Pildora/Generated/.
#
# Run this ONCE to bootstrap, and again whenever the Rust FFI surface
# (crypto-uniffi/src/) changes. The output is committed so that a fresh
# checkout builds with Cmd+B without any manual pre-step — the per-build Run
# Script phase (cargo-build-phase.sh) only cross-compiles the static library.
#
# Output files:
#   Pildora/Generated/pildora_crypto_ffi.swift   UniFFI Swift bindings
#   Pildora/Generated/pildora_crypto_ffiFFI.h     C FFI header
#   Pildora/Generated/module.modulemap            module map (renamed)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GENERATED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Pildora/Generated"

CARGO="${CARGO:-cargo}"

echo "==> Building pildora-crypto-ffi for the host (needed by uniffi-bindgen)..."
( cd "$REPO_ROOT" && "$CARGO" build -p pildora-crypto-ffi )

# uniffi-bindgen loads the freshly built dylib to read the FFI metadata.
DYLIB="$REPO_ROOT/target/debug/libpildora_crypto_ffi.dylib"
if [ ! -f "$DYLIB" ]; then
    echo "error: expected $DYLIB to exist after the build" >&2
    exit 1
fi

echo "==> Generating Swift bindings into $GENERATED_DIR"
mkdir -p "$GENERATED_DIR"
( cd "$REPO_ROOT" && "$CARGO" run -p pildora-crypto-ffi --features bindgen --bin uniffi-bindgen -- \
    generate \
    --library "$DYLIB" \
    --language swift \
    --out-dir "$GENERATED_DIR" )

# UniFFI emits "<name>FFI.modulemap"; Clang expects a file literally named
# "module.modulemap" on the include path so `import pildora_crypto_ffiFFI`
# resolves.
if [ -f "$GENERATED_DIR/pildora_crypto_ffiFFI.modulemap" ]; then
    mv -f "$GENERATED_DIR/pildora_crypto_ffiFFI.modulemap" "$GENERATED_DIR/module.modulemap"
fi

echo "==> Done. Generated files:"
ls -1 "$GENERATED_DIR"
echo ""
echo "These files are committed; rerun this script only when the Rust FFI"
echo "surface (crypto-uniffi/src/) changes."
