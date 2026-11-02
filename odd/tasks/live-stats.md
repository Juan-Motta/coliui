# Live stats

Objective: the container detail Stats tab exactly as LiveStats.dc.html.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test` (full suite).

## Specs

- S1 — Range segments "1 min" / "5 min" / "15 min" (default 5 min), status "Sampling every 2 s · paused when the window is hidden", "Pause" pill (becomes "Resume").
- S2 — Four cards in a 2-column grid: CPU ("3.1%", "of 4 cores"), Memory ("214 MiB", "limit 1 GiB"), Network I/O ("42 KB/s · 18 KB/s", "rx / tx", Received / Sent legend), Block I/O ("1.2 MB/s · 0.3 MB/s", "read / write", Read / Write legend).
- S3 — Each card: 24 pt value, 120 pt chart with three gridlines, blue line with 10% area; dual cards add an orange second line.
- S4 — Samples every 2 s while the tab is open and the window is visible; history kept for 15 minutes; rates come from consecutive samples.

## Tasks

- T1 — S2, S4 · inline · core: extended stats (CPU count, memory limit, network and block I/O totals, sample time) + tests — done
- T2 — S1–S4 · inline · stats history model + Stats tab + tests — done (198 tests; live read of a running container). Visual check pending.

## Log

- L1 (2026-11-02, user, verbatim): "Live stats"
- L2 (2026-11-02, user, verbatim): "una cosa que se deberia mejorar es que no veo datos en el eje y y eje x entonces veo la linea pero no se a que equivale ni cuando sucedio" — charts moved to Swift Charts: values on the leading axis, clock time on the bottom axis, and a hover rule shared by all four charts with the exact time and values. Departs from the artboard, which has no axes.
- L3 (2026-11-02, user, verbatim): "la altura de las grafias se podria ajustar al tamano de la ventana para no dejar espacios en blanco?" — the two chart rows now share the available height (min 90 pt per chart); the newest X-axis label no longer truncates.
