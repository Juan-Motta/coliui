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

- T1 — S1, S2 · inline · package skeleton, .gitignore, bundle script — done (00e4910 skeleton; bundle script in the app commit)
- T2 — S2, S3, S7 · inline · domain + ports + Docker socket adapter + tests — done (00e4910; RED: missing types, GREEN: 14 tests)
- T3 — S4, S7 · inline · Colima CLI adapter + tests — done (f8c0beb; RED: missing types, GREEN: 20 tests; smoke against live Colima OK)
- T4 — S5, S6, S7 · inline · SwiftUI app: sidebar, containers, menu bar, view model tests — done (app commit; RED: no app target, GREEN: 29 tests; bundle 1.1 MB, launches; visual check pending — screen capture not permitted from the terminal)

Route evidence: units depend on each other (app needs core ports), so no parallel writers; all inline.

## Log

- L1 (2026-11-01, user, verbatim): "este es un proyecto personal el cual quiero que sea una ui para colima (docker), me gustaria que fuera nativo para macos entonces como podria generarlo, lo que quiero es poder gestionarlos contenedores de una forma mas visual y no solo por line de comandos y a la vez que sea liviano"
- L2 (2026-11-01, user): "Armar proyecto" — after approving the Liquid Glass designs, Graphite app icon and menu bar glyph.
- L3: Environment — Swift 6.4 CLT only (no Xcode, no XcodeGen); probe confirmed `swift build` compiles SwiftUI `.glassEffect()` and `swift test` runs Swift Testing. Docker Engine 29.5.2 / API 1.54 at `~/.colima/default/docker.sock`; `colima list --json` prints one JSON object per line.
- L4: On the macOS 27 SDK `@State` is a macro whose plugin (SwiftUIMacros) ships only with Xcode, so the build failed with the CLT. Decision: no `@State`; UI state (sidebar section, table selection, pending removal) lives in the `@Observable` models; the app model is a static shared instance. `@Observable`, `@Bindable` and `@Environment` work.
- L5: Smoke — real `UnixSocketTransport` listed containers and `ColimaCLIRuntime` read `default running 4 CPU · 4 GiB · 100 GiB`. Release bundle 1.1 MB, ~146 MB RSS at launch.
- L6 (2026-11-01, user, verbatim): "hay detalles, si doy click a containers no carga, los botones de cada cintainer nose ven bien, el diseno de la lista no es como el establecido en los disenos" / "es decir la imagen no se ve como el diseno" (with a screenshot of the Main.dc.html design).
- L7: Fixes — sidebar row had `.badge` after `.tag`, so the List couldn't select Containers; list rebuilt as the designed card (uppercase NAME/IMAGE/STATUS/PORTS/CPU/MEMORY/ACTIONS headers, separators, tinted status, 28 pt icon buttons), filter moved above the list, toolbar gets List/Compose toggle, Refresh + Sort group, search and Run container (disabled: not built). Added container stats (CPU/memory, docker CLI formulas) and sidebar totals (images/volumes/networks/profiles), uppercase sections and a Settings link. 36 tests green. Visual check pending.
- Next: user visual check of the running app; then Docker events stream, logs view, app icon (.icns from the Graphite design), remaining designed screens.
