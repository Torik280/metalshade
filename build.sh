#!/usr/bin/env bash
# MetalShade — one-command build script
# Produces MetalShade.app in the project root, signed with ad-hoc signature.
# Usage: ./build.sh
set -euo pipefail

APP="MetalShade.app"
BINARY_NAME="MetalShade"
ENTITLEMENTS="MetalShade.entitlements"

echo "━━━  MetalShade Build  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Build ──────────────────────────────────────────────
echo "→ Compiling (Release)…"
swift build -c release --arch arm64 --arch x86_64 2>&1

# ── 2. App bundle structure ───────────────────────────────
echo "→ Creating app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Universal binary (arm64 + x86_64)
cp ".build/apple/Products/Release/$BINARY_NAME" "$APP/Contents/MacOS/$BINARY_NAME" 2>/dev/null \
  || cp ".build/release/$BINARY_NAME" "$APP/Contents/MacOS/$BINARY_NAME"

# Info.plist
cp "Sources/MetalShade/Info.plist" "$APP/Contents/Info.plist"

# ── 3. Sign (ad-hoc) ──────────────────────────────────────
echo "→ Signing (ad-hoc)…"
codesign --force --deep --sign - \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    "$APP"

# ── 4. Done ───────────────────────────────────────────────
echo ""
echo "✓  Built: $APP"
echo ""
echo "Run with:"
echo "   open $APP"
echo ""
echo "First launch: macOS will ask for Screen Recording permission."
echo "  → System Settings → Privacy & Security → Screen Recording → toggle MetalShade ON"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
