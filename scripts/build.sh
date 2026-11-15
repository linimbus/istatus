#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP_NAME="iStatus"
BUNDLE="$ROOT/dist/$APP_NAME.app"

swift build -c "$CONFIG"
BIN="$ROOT/.build/$CONFIG/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
    echo "Build product not found: $BIN" >&2
    exit 1
fi

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
    "$ROOT/scripts/make-icon.sh"
fi

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# SMAppService requires a valid signature. Ad-hoc signing is sufficient for local use;
# distribution builds should use a Developer ID identity.
codesign --force --deep --sign - "$BUNDLE" >/dev/null

echo "Built $BUNDLE"
