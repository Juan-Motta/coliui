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
- T3 — S1 · inline · stale results: profiles, Files, resource refreshes
- T4 — S1 · inline · digest references
- T5 — S1 · inline · Files start on container start; shortcuts behind Settings
- T6 — S1 · inline · one secret rule; cancellable colima commands
- T7 — S2 · inline · performance items
- T8 — S3 · inline · cleanup items

## Log

- L1 (2026-11-02, user, verbatim): "ok ahora quiero que hagas una revision del proyecto en busca de problemas de optimizacion, posibles errores, malas practicas, y busca codigo simple y limpio" → review delivered; user: "Todo por partes".
