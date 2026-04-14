#!/usr/bin/env bash
set -euo pipefail

APP="MetalShade.app"

echo "Building..."
swift build -c release --arch arm64 --arch x86_64 2>&1

echo "Creating app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp ".build/apple/Products/Release/MetalShade" "$APP/Contents/MacOS/MetalShade" 2>/dev/null \
  || cp ".build/release/MetalShade" "$APP/Contents/MacOS/MetalShade"

cp "Sources/MetalShade/Info.plist" "$APP/Contents/Info.plist"

echo "Signing..."
# NOTE: --options runtime (Hardened Runtime) with ad-hoc signing (-) causes macOS
# to revoke the Screen Recording TCC permission on every rebuild.
# Omitting it lets the permission persist across rebuilds for the same bundle ID.
codesign --force --deep --sign - --entitlements MetalShade.entitlements "$APP"

echo ""
echo "Done → $APP"
echo ""
echo "FIRST RUN: macOS will ask for Screen Recording permission."
echo "If it shows 'No access' — go to:"
echo "  System Settings → Privacy & Security → Screen Recording"
echo "  Toggle MetalShade OFF then ON, then click 'Retry' in the error dialog."
echo ""
echo "To launch: open $APP"
