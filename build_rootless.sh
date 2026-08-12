#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ROOTLESS_THEOS="${THEOS_ROOTLESS:-/Users/uni9k/theos}"
export THEOS="$ROOTLESS_THEOS"
export PATH="$THEOS/bin:$PATH"

if [[ ! -d "$THEOS" ]]; then
    echo "ERROR: Rootless Theos not found: $THEOS" >&2
    echo "Set THEOS_ROOTLESS to override the path." >&2
    exit 1
fi

cd "$ROOT"

echo "Using Rootless Theos: $THEOS"
echo "Project: $ROOT"
echo "==> Cleaning..."
make clean THEOS_PACKAGE_SCHEME=rootless

echo "==> Building Rootless package..."
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

echo
echo "==> Done. Rootless packages:"
find "$ROOT/packages/rootless" -type f -name '*.deb' -print 2>/dev/null || \
find "$ROOT/packages" -type f -name '*.deb' -print 2>/dev/null || true
