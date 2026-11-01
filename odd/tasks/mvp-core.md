# ColiUI MVP core

Objective: native, lightweight macOS UI for Colima to manage Docker containers visually.
Branch: `feat/mvp-core` · Delivery: work-unit commits, PR strategy pending (no push/PR yet) · Runner: `swift test` (Swift Testing, SwiftPM only — no Xcode installed).

## Specs

- S1 — SwiftPM project targeting macOS 26 that builds with `swift build` and packages a `ColiUI.app` via a script. Designs: https://claude.ai/artifact/3MwzFhm1Mg27A5BSHcpZoR (Liquid Glass).
- S2 — Hexagonal layout: `ColiUICore` (Domain, Ports, Adapters, no third-party deps) and `ColiUI` (SwiftUI app).
- S3 — Docker Engine client over the Colima Unix socket: list containers (all), start, stop, restart, remove.
- S4 — Colima adapter through the CLI: read status/resources (`colima list --json`), start, stop, restart a profile.
- S5 — Main window: `NavigationSplitView` with the shared sidebar (Colima card, DOCKER and SYSTEM sections), containers list with All / Running / Stopped filter, search, and per-row start/stop/restart/remove (remove asks for confirmation).
- S6 — `MenuBarExtra` with the chosen llama-in-console template glyph, Colima status, per-container start/stop and "Open ColiUI".
- S7 — Unit tests for domain mapping, HTTP response parsing, Colima JSON parsing, socket path resolution and the containers view model.
- Assumption: refresh by polling every 3 s while running (Docker events stream is a later task). Kubernetes is out of scope (user: "menos por ahora kubernetes").

## Tasks

- T1 — S1, S2 · inline · package skeleton, .gitignore, bundle script — pending
- T2 — S2, S3, S7 · inline · domain + ports + Docker socket adapter + tests — pending
- T3 — S4, S7 · inline · Colima CLI adapter + tests — pending
- T4 — S5, S6, S7 · inline · SwiftUI app: sidebar, containers, menu bar, view model tests — pending

Route evidence: units depend on each other (app needs core ports), so no parallel writers; all inline.

## Log

- L1 (2026-11-01, user, verbatim): "este es un proyecto personal el cual quiero que sea una ui para colima (docker), me gustaria que fuera nativo para macos entonces como podria generarlo, lo que quiero es poder gestionarlos contenedores de una forma mas visual y no solo por line de comandos y a la vez que sea liviano"
- L2 (2026-11-01, user): "Armar proyecto" — after approving the Liquid Glass designs, Graphite app icon and menu bar glyph.
- L3: Environment — Swift 6.4 CLT only (no Xcode, no XcodeGen); probe confirmed `swift build` compiles SwiftUI `.glassEffect()` and `swift test` runs Swift Testing. Docker Engine 29.5.2 / API 1.54 at `~/.colima/default/docker.sock`; `colima list --json` prints one JSON object per line.
