# Review fixes

Objective: fix the findings of the 2026-11-02 project review, in parts: bugs, then performance, then cleanup.
Branch: `fix/review-findings` · Delivery: work-unit commits, no push · Runner: `swift test` (full suite) + `COLIUI_LIVE=1` read-only checks.

## Specs

- S1 — Bugs: no fd is shut down after it was closed; closing a detail or disconnecting mid-connect leaves no stream or shell behind; late async results never overwrite newer state (profiles, Files, resource lists); digest image references (`name@sha256:…`) run and pull; Files starts when the container starts while the tab is open; shortcuts behind Settings don't fire; one secret rule everywhere; `colima` commands can be cancelled.
- S2 — Performance: stats sample only while shown; per-row "used by" lookups use one index per render; the log filter caches its regex and filtered lines; no unused observation in Stats; hover doesn't redraw every row; long lists are lazy; stream decoders don't re-copy their buffers.
- S3 — Cleanup: one socket stream helper, one segmented control, shared clipboard, card and message helpers, shared toast, dead code removed. Behavior and looks unchanged.

## Tasks

- T1 — S1 · inline · stream fd lifecycle (logs, events, pull) — done (StreamingSocket; 288 tests, 12 live). RED not observable: the reuse race is timing-dependent; the invariant is pinned by StreamingSocketTests.
- T2 — S1 · inline · detail start after stop; terminal connect after disconnect — done (RED observed for both, then GREEN; 290 tests)
- T3 — S1 · inline · stale results: profiles, Files, resource refreshes — done (LatestRequest; RED observed for profiles, Files ×2, containers; Images/Volumes/Networks share the containers pattern; 294 tests)
- T4 — S1 · inline · digest references — done (RED observed, then GREEN)
- T5 — S1 · inline · Files start on container start; shortcuts behind Settings — done (view-only; no unit test: SwiftUI focus, disabled and task identity; built and suite green)
- T6 — S1 · inline · one secret rule; cancellable colima commands — done (RED observed for both; 297 tests; live colima list ok)
- T6b — S1 · inline · core edge cases: `~other` binds, ASCII-only IDs, chunk-size overflow (crashed the test process: RED), lone surrogate escape, huge folders via `find -exec stat {} +` — done (303 tests; live files ok on 11 containers)
- T6c — S1 · inline · app minor bugs: list search ignored the Compose service, AlertRules never forgot removed containers, Files download could start twice and failed silently (RED observed for these three), terminal resizes now sent in order, "Last scanned" refreshes every 30 s, VoiceOver names for the sort and "More actions" menus — done (306 tests)
- T7 — S2 · inline · performance items — done: stats only while the list shows them (eb33c13); usage index for Images/Volumes/Networks (460d0b9); incremental log filter + cached regex (07a1173); lazy lists, per-row hover, one stats filter per chart (9b517e8); decoders without per-line copies, release 0.27 s → 0.14 s for 20 MB (e1dc7a0); parallel colima status (ffc9295); lists computed once per render (b34557b); archive/exec read in place. Skipped: the two regexes per log line (minor)
- T8 — S3 · inline · cleanup items — done: Clipboard, cardSurface (21→1), MessageCard, Toast, DockerName, one decode helper in the core, one segmented control for the 3 field toolbars, dead placeholder code removed, deprecated Text + Text. Kept apart on purpose: Settings tabs / Theme / Profiles segments (different sizes and icons) and TerminalPillStyle (dims when disabled; PillButtonStyle doesn't).

## Log

- L1 (2026-11-02, user, verbatim): "ok ahora quiero que hagas una revision del proyecto en busca de problemas de optimizacion, posibles errores, malas practicas, y busca codigo simple y limpio" → review delivered; user: "Todo por partes".
- L2 (2026-11-02): the new socket tests sometimes killed the test process with SIGPIPE: their server replied to clients that had already left, and accepted Unix sockets neither inherit SO_NOSIGPIPE nor take it after the peer closed. The test servers now ignore SIGPIPE (the app sets SO_NOSIGPIPE before connecting, so it is not affected). Also found: the build-retry loop could run tests on a stale binary after a real compile error hidden by the TestingMacros flake; builds are now checked before testing.
- L3 (2026-11-02): one live files run hit a 30 s socket timeout ("Resource temporarily unavailable") on one request; two reruns passed with identical results and the script answers in 0.13 s by hand. Treated as a transient Colima stall (the transport's timeout did its job).
- L4 (2026-11-02): live runs hit a one-off 30 s socket stall about once every five runs (disk usage, files, logs); reruns always pass and the requests answer in < 1 s by hand. Observation for the user, not a code defect found.
- L5 (2026-11-02): independent verifier: S1–S3 met except 3 blockers caused by this branch — B1 regex cache keyed on the trimmed text, B2 Files stuck on "Loading…" after a failed move during the first load, B3 MessageCard added centring/padding to Inspect and Environment. One correction batch fixed all three (RED observed for B1 and B2 via the verifier probes, now regression tests; B3 restored by an opt-in `wraps`). 310 tests, 3/3 clean runs. Advisories left: SIGTERM-only colima termination, cancelled commands surface as exit 15.
