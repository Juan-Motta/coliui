#!/usr/bin/env bash
# Builds build/ColiUI-<version>.dmg: the installer window with the app, an Applications shortcut to drag it
# onto, and the volume icon. Needs dmgbuild (pip install dmgbuild==1.6.7).
# Usage: scripts/make-dmg.sh <version>            e.g. scripts/make-dmg.sh 0.2.0
# Signing and notarization run only when their variables are set:
#   SIGN_IDENTITY       "Developer ID Application: Name (TEAMID)"
#   NOTARY_KEY_PATH     App Store Connect API key (.p8)
#   NOTARY_KEY_ID       its key ID
#   NOTARY_ISSUER_ID    its issuer ID
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/make-dmg.sh <version>}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must look like 1.2.3, got '$VERSION'" >&2
    exit 1
fi
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
DMG="build/ColiUI-$VERSION.dmg"
DMGBUILD="${DMGBUILD:-dmgbuild}"
if ! command -v "$DMGBUILD" >/dev/null; then
    echo "dmgbuild is missing: pip install dmgbuild==1.6.7 (or set DMGBUILD to its path)" >&2
    exit 1
fi

VERSION="$VERSION" SIGN_IDENTITY="$SIGN_IDENTITY" scripts/bundle.sh

# dmgbuild writes the window layout (background, icon positions, volume icon) without driving Finder,
# so it also works on CI runners. Layout: scripts/dmg-settings.py; background: make-dmg-background.swift.
rm -f "$DMG"
"$DMGBUILD" -s scripts/dmg-settings.py -D app=build/ColiUI.app "ColiUI $VERSION" "$DMG"

if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    : "${NOTARY_KEY_ID:?NOTARY_KEY_ID is required with NOTARY_KEY_PATH}"
    : "${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID is required with NOTARY_KEY_PATH}"
    AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
    RESULT="$(xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait --output-format json)"
    echo "$RESULT"
    if [[ "$(plutil -extract status raw - <<<"$RESULT")" != "Accepted" ]]; then
        # Print Apple's reasons before failing.
        xcrun notarytool log "$(plutil -extract id raw - <<<"$RESULT")" "${AUTH[@]}" || true
        echo "Notarization was not accepted" >&2
        exit 1
    fi
    # Stapling the ticket lets Gatekeeper accept the app offline too.
    xcrun stapler staple "$DMG"
fi

echo "Built $DMG"
