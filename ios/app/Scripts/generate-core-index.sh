#!/usr/bin/env bash
# generate-core-index.sh — Xcode pre-build phase that generates the bundled
# **core** drug index (`core-index.db`) from the checked-in `core-seed.json`.
#
# The core index is a small, offline, schema-identical subset of the full drug
# corpus. Shipping it as a generated `.db` (rather than a committed binary) keeps
# the repo clean and deterministic: the seed JSON is the source of truth.
#
# It runs the `pildora-core-index-tool` executable from the PildoraDrugIndex
# SwiftPM package via `swift run`. If the tool cannot be built (e.g. offline
# without a resolved package cache) the app still works: it falls back to
# building the core index from the bundled `core-seed.json` at first launch.
#
# Xcode-exported variables used:
#   SRCROOT             directory containing the .xcodeproj (ios/app)
#
# Output:
#   $SRCROOT/Pildora/Resources/core-index.db   (git-ignored; bundled as a resource)

set -euo pipefail

SEED="$SRCROOT/Pildora/Resources/core-seed.json"
OUT="$SRCROOT/Pildora/Resources/core-index.db"
PACKAGE_DIR="$SRCROOT/../drug-index/PildoraDrugIndex"

if [ ! -f "$SEED" ]; then
    echo "warning: core-seed.json not found at $SEED; skipping core index generation" >&2
    exit 0
fi

# Only regenerate when the seed is newer than the output (keeps incremental
# builds fast). Xcode's own input/output file tracking also gates this phase.
if [ -f "$OUT" ] && [ "$OUT" -nt "$SEED" ]; then
    echo "core-index.db is up to date" >&2
    exit 0
fi

# Locate swift (Xcode build phases run with a minimal PATH).
if command -v swift >/dev/null 2>&1; then
    SWIFT="$(command -v swift)"
elif [ -x "/usr/bin/swift" ]; then
    SWIFT="/usr/bin/swift"
else
    echo "warning: swift not found; the app will build core-index.db at first launch" >&2
    exit 0
fi

echo "Generating bundled core drug index → $OUT" >&2
if "$SWIFT" run --package-path "$PACKAGE_DIR" pildora-core-index-tool "$SEED" "$OUT" >&2; then
    echo "Bundled core drug index generated." >&2
else
    echo "warning: core index generation failed; the app will build it at first launch" >&2
    rm -f "$OUT"
fi

exit 0
