#!/usr/bin/env bash
# cargo-build-phase.sh — Xcode "Run Script" build phase that cross-compiles
# pildora-crypto-ffi for the active SDK/architecture and stages the resulting
# static library where the linker can find it.
#
# This replaces the manual `ios/ffi-spike/build-xcframework.sh` step for the
# production app: developers just press Cmd+B and Xcode compiles the Rust code
# as part of the normal build.
#
# It is driven entirely by the environment variables Xcode exports to a Run
# Script phase:
#   PLATFORM_NAME       iphoneos | iphonesimulator | macosx | watchos | ...
#   ARCHS               space-separated active arches, e.g. "arm64" or "arm64 x86_64"
#   CONFIGURATION       Debug | Release
#   BUILT_PRODUCTS_DIR  where the linker looks for libraries (-L)
#   SRCROOT             the directory containing the .xcodeproj (ios/app)
#
# It can also be run standalone for testing by exporting those variables.
#
# The UniFFI Swift bindings are NOT generated here — they are produced once by
# `generate-bindings.sh` and committed under `Pildora/Generated/`. Regenerate
# them only when the Rust FFI surface changes.

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

CRATE="pildora-crypto-ffi"
LIB_NAME="libpildora_crypto_ffi.a"

# ── Locate cargo ─────────────────────────────────────────────────────────────
# Xcode runs build phases with a minimal PATH that usually does not include
# ~/.cargo/bin, so resolve cargo explicitly.
if [ -n "${CARGO:-}" ] && command -v "$CARGO" >/dev/null 2>&1; then
    : # caller provided an explicit cargo
elif command -v cargo >/dev/null 2>&1; then
    CARGO="$(command -v cargo)"
elif [ -x "$HOME/.cargo/bin/cargo" ]; then
    CARGO="$HOME/.cargo/bin/cargo"
    export PATH="$HOME/.cargo/bin:$PATH"
elif [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
    CARGO="$(command -v cargo)"
else
    echo "error: cargo not found. Install Rust from https://rustup.rs and ensure ~/.cargo/bin is available." >&2
    exit 1
fi

# ── Resolve the repository root ──────────────────────────────────────────────
# SRCROOT points at ios/app/ when invoked by Xcode. Fall back to git when run
# standalone.
if [ -n "${SRCROOT:-}" ] && [ -d "$SRCROOT/../.." ]; then
    REPO_ROOT="$(cd "$SRCROOT/../.." && pwd)"
else
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi

# ── Map Xcode SDK + arch to a Rust target triple ─────────────────────────────
rust_target_for() {
    local platform="$1" arch="$2"
    case "$platform" in
        iphoneos)
            case "$arch" in
                arm64|arm64e) echo "aarch64-apple-ios" ;;
                *) echo "error: unsupported iphoneos arch '$arch'" >&2; return 1 ;;
            esac
            ;;
        iphonesimulator)
            case "$arch" in
                arm64) echo "aarch64-apple-ios-sim" ;;
                x86_64) echo "x86_64-apple-ios" ;;
                *) echo "error: unsupported iphonesimulator arch '$arch'" >&2; return 1 ;;
            esac
            ;;
        macosx)
            case "$arch" in
                arm64) echo "aarch64-apple-darwin" ;;
                x86_64) echo "x86_64-apple-darwin" ;;
                *) echo "error: unsupported macosx arch '$arch'" >&2; return 1 ;;
            esac
            ;;
        watchos)
            case "$arch" in
                arm64_32) echo "arm64_32-apple-watchos" ;;
                arm64) echo "aarch64-apple-watchos" ;;
                *) echo "error: unsupported watchos arch '$arch'" >&2; return 1 ;;
            esac
            ;;
        watchsimulator)
            case "$arch" in
                arm64) echo "aarch64-apple-watchos-sim" ;;
                x86_64) echo "x86_64-apple-watchos-sim" ;;
                *) echo "error: unsupported watchsimulator arch '$arch'" >&2; return 1 ;;
            esac
            ;;
        *)
            echo "error: unsupported PLATFORM_NAME '$platform'" >&2
            return 1
            ;;
    esac
}

# ── Inputs with sensible standalone defaults ─────────────────────────────────
PLATFORM_NAME="${PLATFORM_NAME:-iphonesimulator}"
ARCHS="${ARCHS:-arm64}"
CONFIGURATION="${CONFIGURATION:-Debug}"

# Allow `ONLY_ACTIVE_ARCH`-style single-arch builds to be respected naturally:
# ARCHS already reflects what Xcode wants to produce.

# Map Debug/Release to a cargo profile. Release builds are optimized; Debug
# stays unoptimized for fast incremental developer builds.
CARGO_PROFILE_FLAG=""
PROFILE_DIR="debug"
if [ "$CONFIGURATION" = "Release" ]; then
    CARGO_PROFILE_FLAG="--release"
    PROFILE_DIR="release"
fi

echo "==> Building $CRATE for $PLATFORM_NAME [$ARCHS] ($CONFIGURATION)"

# ── Build each architecture ──────────────────────────────────────────────────
SLICES=()
for arch in $ARCHS; do
    target="$(rust_target_for "$PLATFORM_NAME" "$arch")"
    echo "    cargo build --target $target $CARGO_PROFILE_FLAG"
    # `cargo` provides fine-grained incremental compilation: this is a no-op
    # when no Rust sources changed.
    ( cd "$REPO_ROOT" && "$CARGO" build -p "$CRATE" --target "$target" $CARGO_PROFILE_FLAG )
    SLICES+=("$REPO_ROOT/target/$target/$PROFILE_DIR/$LIB_NAME")
done

# ── Combine slices (if multi-arch) and stage for the linker ──────────────────
mkdir -p "${BUILT_PRODUCTS_DIR:?BUILT_PRODUCTS_DIR must be set}"
OUTPUT="$BUILT_PRODUCTS_DIR/$LIB_NAME"

if [ "${#SLICES[@]}" -eq 1 ]; then
    cp -f "${SLICES[0]}" "$OUTPUT"
else
    echo "==> lipo-combining ${#SLICES[@]} arch slices"
    lipo -create "${SLICES[@]}" -output "$OUTPUT"
fi

echo "==> Staged $LIB_NAME -> $OUTPUT"
