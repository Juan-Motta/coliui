#!/usr/bin/env bash
# Builds ColiUI in release mode and wraps the binary in build/ColiUI.app.
# VERSION and BUILD_NUMBER set the bundle version (default 0.1.0 and the commit count).
# SIGN_IDENTITY signs with a Developer ID and the hardened runtime; without it the app is ad-hoc signed.
# Updates: Sparkle reads SPARKLE_FEED_URL (default: the latest GitHub release's appcast.xml) and the public key
# in Resources/sparkle-public-key (or SPARKLE_PUBLIC_KEY). Without a key the app runs with updates off.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="build/ColiUI.app"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/Juan-Motta/coliui/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-$( { tr -d '[:space:]' < Resources/sparkle-public-key; } 2>/dev/null || true)}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ColiUI"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/ColiUI"
# Sparkle is a binary package: copy its framework from the resolved artifact (build output layouts differ
# between toolchains). The app looks for it in Contents/Frameworks.
SPARKLE_SOURCE="$(find .build/artifacts -path "*Sparkle.xcframework/macos-*/Sparkle.framework" -maxdepth 6 -type d | head -1)"
[[ -n "$SPARKLE_SOURCE" ]] || { echo "Sparkle.framework not found under .build/artifacts" >&2; exit 1; }
ditto "$SPARKLE_SOURCE" "$APP/Contents/Frameworks/Sparkle.framework"
# ColiUI isn't sandboxed, so Sparkle's XPC services are unused (Sparkle's docs allow removing them).
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/ColiUI"
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
    <key>SUFeedURL</key><string>${SPARKLE_FEED_URL}</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
${SPARKLE_PUBLIC_KEY:+    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>}
    <key>NSAppleEventsUsageDescription</key><string>ColiUI asks Terminal to run docker exec in your container.</string>
</dict>
</plist>
PLIST

# Inside out: Sparkle's helpers, the framework, then the app (Sparkle's documented order).
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -n "$SIGN_IDENTITY" ]]; then
    # Notarization needs the hardened runtime and a secure timestamp.
    SIGN=(codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY")
    "${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
    "${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
    "${SIGN[@]}" "$SPARKLE"
    "${SIGN[@]}" --entitlements Resources/ColiUI.entitlements "$APP"
else
    for item in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE" "$APP"; do
        codesign --force --sign - "$item" 2>&1 | grep -v "replacing existing signature" >&2 || true
        codesign --verify "$item"
    done
fi
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"
