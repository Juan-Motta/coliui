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
- T2 — S1–S3, S5 · inline · SwiftTerm dependency (app target only), terminal model + tab + tests — done (217 tests). Visual check accepted (L4).

- T3 — S4 · inline · typing lag: move blocking socket and process work off the cooperative pool + regression test — done (219 tests, 9 live)

## Log

- L1 (2026-11-02, user, verbatim): "Terminal"
- L2 (2026-11-02, user): emulator choice → "Usar SwiftTerm (Recommended)" (first external dependency, app target only).
- L3 (2026-11-02): independent verifier found a blocker — DockerShellSession.send held the lock across a write that can block forever, so Disconnect froze the app when a program stops reading stdin. RED observed (suite hung, then a 3 s regression test failed); fixed by writing without the lock and draining the write queue before the reader closes the fd. Security quoting and the dependency pin passed review.
- L4 (2026-11-02, user, verbatim): "se ve bien solo hay un problema y es que los comandos o al escribir existe un delay"
- L5 (2026-11-02, user, verbatim): "generalmente responde rapido pero hay ocaciones en que tarda un leve tiempo en notarse en que aparece lo que se escribe, no es consistente pero sucede a menudo para que sea molesto y notable"
- L6 (2026-11-02): measured in the running app — shell output arrived in bursts up to ~540 ms late, released whenever a Docker request finished; the socket (~1.5 ms echo, also under 13 parallel stats calls) and SwiftTerm drawing (~1.3 ms) were fast. Cause: every adapter ran blocking socket reads and process waits in `Task.detached`, so stats rounds (~1 s per container) filled the user-initiated cooperative pool and the terminal's stream delivery waited for a free thread. Fix: `BlockingIO` runs that work on GCD threads; RED observed (pool test waited ~2 s), then GREEN.
- L7 (2026-11-02, user, verbatim): "Ya va fluido" — independent verifier passed ebf6913 (no blockers; advisory: stream readers arm `onTermination` only after connect, pre-existing).
