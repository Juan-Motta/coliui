# Updates — check for and install new versions

Objective: ColiUI finds new releases and installs them through Sparkle, with ColiUI's own UI (Updates.dc.html).
Branch: feat/updates. Delivery: ask-on-risk. Test runner: `swift test` (scratchpad build.sh retries the TestingMacros flake).

## Specs

- S1 — "me gustaria agregar de una vez la opcion para verificar si existe una version nueva y actualizar". Sparkle 2.10.0 checks the appcast, downloads, verifies (EdDSA + Developer ID) and installs; no Sparkle window ever shows.
- S2 — Settings › About gets an Updates group (Updates.dc.html): "Check for updates automatically" switch (once a day); status "ColiUI is up to date" / "Checking…" / "Version X is available" + New tag; "Last checked …"; "Check for Updates" button that becomes "View update" when one is found; hint "Checks once a day. Updates are signed and verified before they install."
- S3 — Update modal (same modal host, click outside closes it): icon, "ColiUI X is available", "You have Y · N MB download", release notes grouped as in the GitHub release. Steps: Available (Skip this version · Later · Install update), Downloading (progress, "You can close this; the download keeps going.", Cancel), Ready ("Downloaded and verified. ColiUI relaunches to finish; your containers keep running.", Later · Relaunch now).
- S4 — Menu bar popover: "Update available · ColiUI X" banner with View while an update waits (View opens the main window with the modal), and a "Check for Updates…" action. The app menu also gets "Check for Updates…".
- S5 — Releases publish a signed `appcast.xml` next to the DMG; the feed is `releases/latest/download/appcast.xml`. The EdDSA private key is a repository secret; the public key is in Info.plist.
- S6 — Builds without the Sparkle keys (`swift run`, ad-hoc bundles) keep working; updates are just unavailable there.

Assumption: "Later" on a downloaded update lets Sparkle install it when ColiUI quits (Sparkle's dismiss behaviour).

## Tasks

- T1 (S3) ReleaseNotes parser in ColiUICore — inline — pending
- T2 (S1–S4, S6) UpdatesViewModel + Sparkle user driver + About group, modal, menu bar — inline — pending
- T3 (S1, S5, S6) bundle.sh embeds and signs Sparkle.framework; Info.plist feed and key — inline — pending
- T4 (S5) release workflow signs and publishes appcast.xml — inline — pending

Risk: item 2 (update signature verification and signing key), item 5 (new dependency, release workflow).

## Log

- L1 (2026-11-03) "y me gustaria agregar de una vez la opcion para verificar si existe una version nueva y actualizar" — then chose Sparkle with ColiUI's own UI ("ok"), and approved Updates.dc.html ("Se ve bien").
