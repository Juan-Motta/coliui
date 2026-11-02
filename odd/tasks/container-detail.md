# Container detail with live logs

Objective: open a container from the list and see its live logs and overview, exactly as Detail.dc.html.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test`.

## Specs

- S1 — Clicking a container's name opens its detail; the back button returns to the list. Header per design: back capsule, name + "shortID · image", status pill, capsule with Stop/Start, Restart, Open shell, separate capsule with Remove (confirmation; returns to the list after removal).
- S2 — Tabs capsule: Logs, Stats, Terminal, Inspect, Environment. Logs is built; the others show "Designed, not built yet." (Open shell selects Terminal).
- S3 — Live logs from the Docker Engine (`/containers/{id}/logs?follow=1&stdout=1&stderr=1&timestamps=1`), decoding the multiplexed stream (8-byte frame headers) and TTY raw streams, across chunked transfer encoding. Each line shows time (HH:mm:ss), a level when the message carries one (INFO/WARN/ERROR/DEBUG), and the message, colored as designed.
- S4 — Logs toolbar: filter field, `.*` regex toggle, Follow (auto-scroll), Timestamps (show/hide time), Since (15 min / 1 hour / All, restarts the stream), Export (save as .log), Clear. Keeps the last 5,000 lines.
- S5 — Aside: OVERVIEW (Image, Created relative, Restart policy, Network, IP), PORTS (links), MOUNTS (source → destination) from `/containers/{id}/json`.
- Assumption: an invalid regex shows no lines and marks the toggle red rather than crashing.

## Tasks

- T1 — S3, S5 · inline · core: details + log stream decoding + tests — done (37a41ac; RED: missing types, GREEN: 43 core tests)
- T2 — S1–S5 · inline · app: detail view model + view + navigation + tests — done (app commit; RED: missing view model, GREEN: 19 app tests; live test read 22 real lines). Visually accepted.

Route evidence: T2 depends on T1's ports, no parallel writers.

## Log

- L1 (2026-11-01, user, verbatim): "Detalle con logs"
- L2: Docker returns `application/vnd.docker.multiplexed-stream` for non-TTY containers (frame header `01 00 00 00` + big-endian size) with RFC3339Nano timestamps prefixed to each line; inspect provides Created, State.StartedAt, Config.Tty, HostConfig.RestartPolicy.Name, NetworkSettings.Networks.*.IPAddress, Mounts.
- L3: `swift test --filter` fails with the CLT (TestingMacros plugin not loaded); the full suite works. Live integration test gated by `COLIUI_LIVE=1`. Log lines wrap instead of scrolling horizontally (readability over the mockup's nowrap).
- L4 (user): "ok se ve bien" — detail with live logs, ports and row navigation visually accepted.
