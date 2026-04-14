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
codesign --force --deep --sign - --entitlements MetalShade.entitlements "$APP"

echo "Resetting Screen Recording permission (ensures fresh TCC prompt on next launch)..."
tccutil reset ScreenCapture com.metalshade.app 2>/dev/null || true

echo ""
echo "Done → $APP"
echo ""
echo "При первом запуске macOS ПОПРОСИТ разрешение на Запись экрана — нажми OK."
echo "Если разрешение не появилось: Системные настройки → Конфиденциальность → Запись экрана"
echo "  → найди MetalShade, включи переключатель."
echo ""
echo "Запустить: open $APP"
