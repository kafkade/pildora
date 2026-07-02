#!/usr/bin/env bash
# run-watchos-tests.sh — Build the watchOS FFI slices and run the FFI
# validation XCTest bundle on the watchOS simulator (issue #42).
#
# Steps:
#   1. Build ../ffi-spike/PildoraCryptoFFI.xcframework (with watchOS slices)
#      and generate the UniFFI Swift bindings.
#   2. Stage the generated bindings into the test target.
#   3. Pick (and boot) an available watchOS simulator.
#   4. Run `xcodebuild test` against that simulator.
#
# Usage:
#   cd <repo-root>
#   ./ios/watchos-ffi-spike/run-watchos-tests.sh
#
# Requires: macOS with Xcode + the watchOS SDK and a watchOS simulator runtime.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPIKE_DIR="$REPO_ROOT/ios/watchos-ffi-spike"
PKG_DIR="$SPIKE_DIR/PildoraCryptoWatchSpike"
GENERATED_DIR="$REPO_ROOT/ios/ffi-spike/generated"
TEST_SRC_DIR="$PKG_DIR/Tests/PildoraCryptoWatchTests"
KIT_SRC_DIR="$PKG_DIR/Sources/PildoraCryptoWatchKit"
BINDINGS_DEST="$KIT_SRC_DIR/pildora_crypto_ffi.swift"

# ── 1. Build the XCFramework (adds watchOS slices) + generate bindings ────────
echo "==> Building XCFramework + bindings (via ffi-spike/build-xcframework.sh)..."
"$REPO_ROOT/ios/ffi-spike/build-xcframework.sh"

# Fail fast if the watchOS slices are missing (e.g. no watchOS SDK installed).
XCFRAMEWORK="$REPO_ROOT/ios/ffi-spike/PildoraCryptoFFI.xcframework"
if [ ! -d "$XCFRAMEWORK/watchos-arm64-simulator" ]; then
    echo "error: XCFramework has no watchos-arm64-simulator slice." >&2
    echo "       Install Xcode's watchOS SDK and re-run." >&2
    exit 1
fi

# ── 2. Stage the generated Swift bindings into the library target ─────────────
echo "==> Staging UniFFI bindings into the PildoraCryptoWatchKit target..."
cp "$GENERATED_DIR/pildora_crypto_ffi.swift" "$BINDINGS_DEST"

# ── 3. Pick an available watchOS simulator ───────────────────────────────────
echo "==> Locating an available watchOS simulator..."
# Parse the JSON device list with python (BSD awk lacks 3-arg match()). Pick the
# first available device whose runtime identifier mentions watchOS.
WATCH_UDID="$(
    xcrun simctl list devices available --json 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get("devices", {}).items():
    if "watchOS" not in runtime and "watchos" not in runtime:
        continue
    for d in devices:
        if d.get("isAvailable", False):
            print(d["udid"])
            sys.exit(0)
'
)"

if [ -z "${WATCH_UDID:-}" ]; then
    echo "error: no available watchOS simulator found. Create one in Xcode:" >&2
    echo "       Xcode > Settings > Platforms, or Devices & Simulators." >&2
    exit 1
fi
echo "    Using watchOS simulator UDID: $WATCH_UDID"

# Boot it (ignore 'already booted').
xcrun simctl boot "$WATCH_UDID" 2>/dev/null || true

# ── 4. Run the tests ─────────────────────────────────────────────────────────
echo "==> Running xcodebuild test on watchOS simulator..."
cd "$PKG_DIR"

# Clear stale artifacts (xcodebuild refuses to overwrite an existing bundle).
rm -rf "$SPIKE_DIR/TestResults.xcresult" "$SPIKE_DIR/xcodebuild-test.log"

# Resolve the test scheme. SwiftPM auto-generates "<Package>-Package" which
# builds the library + test targets (the plain package-name scheme has no
# buildable platform).
SCHEME="PildoraCryptoWatchSpike-Package"
if ! xcodebuild -list 2>/dev/null | grep -q "$SCHEME"; then
    SCHEME="$(xcodebuild -list 2>/dev/null | awk '/Schemes:/{f=1; next} f && NF {gsub(/^ +/,""); print; exit}')"
fi
echo "    Scheme: $SCHEME"

xcodebuild test \
    -scheme "$SCHEME" \
    -destination "platform=watchOS Simulator,id=$WATCH_UDID" \
    -resultBundlePath "$SPIKE_DIR/TestResults.xcresult" \
    | tee "$SPIKE_DIR/xcodebuild-test.log" \
    | grep -E "Test Suite|Test Case|passed|failed|error:|ℹ️|Argon2id" || true

echo ""
echo "==> Done. Full log: $SPIKE_DIR/xcodebuild-test.log"
echo "    Result bundle:  $SPIKE_DIR/TestResults.xcresult"
