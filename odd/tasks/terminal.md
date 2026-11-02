# Terminal

Objective: the container detail Terminal tab exactly as Terminal.dc.html — an interactive `docker exec -it` shell.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test` (full suite).

## Specs

- S1 — Toolbar: "Shell" picker (/bin/sh, /bin/bash, /bin/zsh), "User" field (root), status "Connected" (green dot), then "Open in Terminal.app", "New session", "Disconnect" (red).
- S2 — Dark panel #1C1C1E, 14 pt radius, 16 pt padding, 13 pt monospaced text, xterm emulation (colors, cursor, full-screen programs), resizes with the window.
- S3 — Footer "Runs docker exec -it through the Engine API · ⌘K clears · ⌘+/⌘− font size".
- S4 — The session runs over the Colima socket: create exec (Tty, stdin), hijack `POST /exec/{id}/start` with `Upgrade: tcp`, resize on window changes; "Disconnect" closes it, "New session" starts another.
- S5 — ⌘⇧T (Settings › Shortcuts "Open shell") opens the Terminal tab for the selected container and stops being disabled.

## Tasks

- T1 — S4 · inline · core: exec create/start/resize over the socket + tests — done (live: /bin/sh echo in a running container)
- T2 — S1–S3, S5 · inline · SwiftTerm dependency (app target only), terminal model + tab + tests

## Log

- L1 (2026-11-02, user, verbatim): "Terminal"
- L2 (2026-11-02, user): emulator choice → "Usar SwiftTerm (Recommended)" (first external dependency, app target only).
