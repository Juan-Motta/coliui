# Inspect

Objective: the container detail Inspect tab, exactly as Inspect.dc.html.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test` (full suite).

## Specs

- S1 — Toolbar: "Filter keys and values" field, Tree / Raw segments, "Expand all", "Collapse all", "Copy JSON".
- S2 — Tree: the `docker inspect` JSON in its original key order inside a card; branches have a disclosure triangle and show `{ n keys }` / `[ n items ]` when collapsed; values are colored by type (string green, number blue, boolean orange, null gray), keys purple. The root, State, Config, NetworkSettings and its Ports open by default.
- S3 — Filtering keeps rows whose key or value matches, plus their parents (opened) and a matching branch's children.
- S4 — Raw: the same JSON pretty-printed, wrapped in `[ ]` like `docker inspect`, on the dark log panel; "Copy JSON" copies it.
- S5 — Footer "Same JSON as docker inspect · secrets in Env are masked · click a value to copy it": secret-looking `Config.Env` values (names with PASS, SECRET, TOKEN, KEY, CREDENTIAL, AUTH, PRIVATE) show as `••••••` in the tree, Raw and copies; clicking a value copies it.
- S6 — The tab uses the full width (no info cards), and reloads each time it opens.

## Tasks

- T1 — S2–S5 · inline · core: ordered JSON parser + printer, Env masking, `ContainerInspector` over `/containers/{id}/json` + tests — done (live: real inspect parsed in key order and round-trips)
- T2 — S1–S6 · inline · view model + tab + tests — done (239 tests). Visual check pending.

## Log

- L1 (2026-11-02, user, verbatim): "Diseñar Inspect" — designed first on the canvas, approved: "Se ve bien".
