# Environment

Objective: the container detail Environment tab, exactly as Environment.dc.html.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test` (full suite).

## Specs

- S1 — Toolbar: "Filter variables" field (name or value), "All (n)" / "Container (n)" / "Image (n)" segments, "Show secrets" / "Hide secrets" toggle, "Copy as .env".
- S2 — Table NAME / VALUE / SOURCE / COPY in Docker's order. SOURCE is "Image" when the image defines the same `NAME=value`, else "Container" (set or overridden by the container).
- S3 — Secrets use the Inspect rule (names with PASS, SECRET, TOKEN, KEY, CREDENTIAL, AUTH, PRIVATE, or a URL with a password): shown as `••••••` with a per-row eye to reveal; "Show secrets" reveals all. Leaving the tab hides them again.
- S4 — COPY copies that variable's real value (an explicit action); "Copy as .env" copies the visible rows as `NAME=value` lines, secrets masked unless revealed.
- S5 — Footer: lock icon, "N secrets masked" (or "Secrets visible until you leave this tab") · "read-only: changing a variable means recreating the container". Full width, reloads each time the tab opens.

## Tasks

- T1 — S2–S3 · inline · core: variables with source and secret flag from container + image inspect + tests — done (live: 58 vars, 6 from the image, 12 secret)
- T2 — S1–S5 · inline · view model + tab + tests — done (253 tests). Visually accepted (L4).

## Log

- L1 (2026-11-02, user, verbatim): "Diseñar Environment" — designed first on the canvas, approved: "Se ve bien".
- L2 (2026-11-02): decision — per-row COPY copies the real value; "Copy as .env" follows what is shown (not in the design text; chosen so masking still protects bulk copies).
- L3 (2026-11-02, user): a one-off "can't connect to Docker" in this tab did not reproduce (500 parallel connections fine, no Colima errors, no fd leak). User: "Sí, agrégala" — the connection error now carries the system reason (strerror) for diagnosis.
- L4 (2026-11-02, user, verbatim): "se ve bien"
