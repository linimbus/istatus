#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p .build
swiftc -O "$ROOT/Tools/make-icon.swift" -o "$ROOT/.build/make-icon"
"$ROOT/.build/make-icon" "$ROOT/.build/icon-1024.png"

ICONSET="$ROOT/.build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16 16 .build/icon-1024.png --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 .build/icon-1024.png --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 .build/icon-1024.png --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 .build/icon-1024.png --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 .build/icon-1024.png --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 .build/icon-1024.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 .build/icon-1024.png --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 .build/icon-1024.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 .build/icon-1024.png --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 .build/icon-1024.png --out "$ICONSET/icon_512x512@2x.png" >/dev/null

mkdir -p "$ROOT/Resources"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "Wrote Resources/AppIcon.icns"
