#!/usr/bin/env bash
# Builds ColiUI in release mode and wraps the binary in build/ColiUI.app.
# VERSION and BUILD_NUMBER set the bundle version (default 0.1.0 and the commit count).
# SIGN_IDENTITY signs with a Developer ID and the hardened runtime; without it the app is ad-hoc signed.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="build/ColiUI.app"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ColiUI"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ColiUI"
# Regenerate with: swift scripts/make-icon.swift
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ColiUI</string>
    <key>CFBundleDisplayName</key><string>ColiUI</string>
    <key>CFBundleIdentifier</key><string>dev.coliui.ColiUI</string>
    <key>CFBundleExecutable</key><string>ColiUI</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>ColiUI asks Terminal to run docker exec in your container.</string>
</dict>
</plist>
PLIST

if [[ -n "$SIGN_IDENTITY" ]]; then
    # Notarization needs the hardened runtime and a secure timestamp.
    codesign --force --options runtime --timestamp --entitlements Resources/ColiUI.entitlements \
        --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP" >/dev/null
fi
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"
