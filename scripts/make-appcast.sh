#!/usr/bin/env bash
# Writes build/appcast.xml for one release: the feed Sparkle reads to find, download and verify the update.
# Usage: scripts/make-appcast.sh <dmg> <download-url> <notes.md>
# The EdDSA private key comes from SPARKLE_KEY_FILE; versions come from build/ColiUI.app's Info.plist.
set -euo pipefail

cd "$(dirname "$0")/.."
DMG="${1:?usage: scripts/make-appcast.sh <dmg> <download-url> <notes.md>}"
URL="${2:?usage: scripts/make-appcast.sh <dmg> <download-url> <notes.md>}"
NOTES="${3:?usage: scripts/make-appcast.sh <dmg> <download-url> <notes.md>}"
: "${SPARKLE_KEY_FILE:?SPARKLE_KEY_FILE must point at the EdDSA private key}"
SIGN_UPDATE="$(find .build/artifacts -path "*Sparkle/bin/sign_update" -maxdepth 5 -type f | head -1)"
[[ -n "$SIGN_UPDATE" ]] || { echo "sign_update not found under .build/artifacts (run swift build first)" >&2; exit 1; }

PLIST=build/ColiUI.app/Contents/Info.plist
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")"
MINIMUM="$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$PLIST")"
# Prints: sparkle:edSignature="…" length="…"
SIGNATURE="$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_KEY_FILE" "$DMG")"
[[ "$SIGNATURE" == sparkle:edSignature=* ]] || { echo "sign_update failed" >&2; exit 1; }
# The notes stay Markdown (ColiUI renders them); only a literal "]]>" would end the CDATA block.
DESCRIPTION="$(sed 's/]]>/]]]]><![CDATA[>/g' "$NOTES")"
PUB_DATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"

cat > build/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ColiUI</title>
    <item>
      <title>ColiUI ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MINIMUM}</sparkle:minimumSystemVersion>
      <description sparkle:descriptionFormat="plain-text"><![CDATA[${DESCRIPTION}]]></description>
      <enclosure url="${URL}" type="application/octet-stream" ${SIGNATURE} />
    </item>
  </channel>
</rss>
XML
xmllint --noout build/appcast.xml
echo "Wrote build/appcast.xml (${VERSION}, build ${BUILD_NUMBER})"
