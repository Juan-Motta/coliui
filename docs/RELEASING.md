# Releasing ColiUI

Push a version tag and GitHub does the rest:

```bash
git tag v0.2.0
git push origin v0.2.0
```

`.github/workflows/release.yml` then runs the tests, builds the app, signs and notarizes the DMG, signs the update feed (`appcast.xml`) and publishes the GitHub Release with the DMG, the feed and the release notes.

## What each script does

| Script | Purpose |
| --- | --- |
| `scripts/bundle.sh` | Builds `build/ColiUI.app` (release), embeds Sparkle and signs it: Developer ID with `SIGN_IDENTITY`, ad-hoc otherwise. |
| `scripts/make-dmg.sh 0.2.0` | Builds `build/ColiUI-0.2.0.dmg` with the drag-to-Applications window; signs and notarizes it when the signing variables are set. Needs [dmgbuild](https://pypi.org/project/dmgbuild/) (`pip install dmgbuild==1.6.7`, or point `DMGBUILD` at it). |
| `scripts/dmg-settings.py` | The installer window layout for dmgbuild. |
| `swift scripts/make-dmg-background.swift` | Regenerates `Resources/dmg-background.tiff`. |
| `swift scripts/make-icon.swift` | Regenerates `Resources/AppIcon.icns`. |
| `scripts/release-notes.sh v0.2.0` | Prints the notes: commits since the previous published release, grouped into Features, Fixes, Performance, Refactoring and Other changes. |
| `scripts/make-appcast.sh` | Writes and signs `build/appcast.xml` from the built app and DMG. |

## Repository secrets

Settings → Secrets and variables → Actions:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Your *Developer ID Application* certificate and private key exported from Keychain Access as `.p12`, then `base64 -i cert.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | The password you set on that `.p12` export |
| `APP_STORE_CONNECT_API_KEY_P8` | The full text of an App Store Connect API key file (`AuthKey_XXXX.p8`; Users and Access → Integrations → Team Keys, role *Developer*) |
| `APP_STORE_CONNECT_KEY_ID` | That key's ID |
| `APP_STORE_CONNECT_ISSUER_ID` | The issuer ID shown above the keys list |
| `SPARKLE_PRIVATE_KEY` | The EdDSA private key that signs `appcast.xml` (see below) |

The names and formats match the Loqui repository, so the same values work in both.

## Updates

ColiUI updates itself with [Sparkle](https://sparkle-project.org): Settings › About › Updates, "Check for Updates…" in the menus, and a daily check. Each release publishes `appcast.xml` next to the DMG; the app reads `releases/latest/download/appcast.xml` and installs an update only when its EdDSA signature matches `Resources/sparkle-public-key` and its Developer ID matches the installed app.

One-time key setup (the private key stays in your keychain and the repository secret):

```bash
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys            # creates the key in your keychain, prints the public key
.build/artifacts/sparkle/Sparkle/bin/generate_keys -p > Resources/sparkle-public-key
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key
gh secret set SPARKLE_PRIVATE_KEY -R Juan-Motta/coliui < sparkle-private-key && rm sparkle-private-key
```

Builds without `Resources/sparkle-public-key` (or `SPARKLE_PUBLIC_KEY`) run with updates off; `SPARKLE_FEED_URL` points a test build at another feed.
