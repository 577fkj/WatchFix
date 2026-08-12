#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ROOTHIDE_THEOS="${THEOS_ROOTHIDE:-/Users/uni9k/theos-roothide}"
export THEOS="$ROOTHIDE_THEOS"
export PATH="$THEOS/bin:$PATH"

if [[ ! -d "$THEOS" ]]; then
    echo "ERROR: RootHide Theos not found: $THEOS" >&2
    echo "Set THEOS_ROOTHIDE to override the path." >&2
    exit 1
fi

cd "$ROOT"

echo "Using RootHide Theos: $THEOS"
echo "Project: $ROOT"
echo "==> Cleaning..."
make clean THEOS_PACKAGE_SCHEME=roothide

echo "==> Building RootHide package..."
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide

echo
echo "==> Done. RootHide packages:"
find "$ROOT/packages/roothide" -type f -name '*.deb' -print 2>/dev/null || \
find "$ROOT/packages" -type f -name '*.deb' -print 2>/dev/null || true
