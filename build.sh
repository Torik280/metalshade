#!/usr/bin/env bash
set -euo pipefail

APP="MetalShade.app"

echo "Building..."
swift build -c release --arch arm64 --arch x86_64 2>&1

echo "Creating app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp ".build/apple/Products/Release/MetalShade" "$APP/Contents/MacOS/MetalShade" 2>/dev/null \
  || cp ".build/release/MetalShade" "$APP/Contents/MacOS/MetalShade"

cp "Sources/MetalShade/Info.plist" "$APP/Contents/Info.plist"

echo "Signing..."
codesign --force --deep --sign - --entitlements MetalShade.entitlements --options runtime "$APP"

echo "Done → open $APP"
