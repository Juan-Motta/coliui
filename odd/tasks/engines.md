# Engines — work with Docker Desktop, OrbStack and Rancher Desktop too

Objective: ColiUI runs against any local Docker engine; Colima keeps the VM controls and Profiles (Engines.dc.html).
Branch: feat/engines. Delivery: ask-on-risk. Test runner: `swift test` (scratchpad build.sh retries the TestingMacros flake).

## Specs

- S1 — "que tanto esfuerzo lleva que dicha ui sea compatible con docker en lugar de colima" → agreed as: works with any Docker engine, and with Colima you also get the VM controls and profiles.
- S2 — Settings › General › Docker engine: Engine picker "Automatic (<detected>)", Colima, Docker Desktop, OrbStack, Rancher Desktop, Custom socket…; the Docker socket in use with "Detected automatically…" hint (editable for Custom socket); Colima profile only for Colima. "Automatic picks the first engine that answers: Colima, then Docker Desktop, OrbStack and Rancher Desktop. Changes apply on the next launch." A `unix://` DOCKER_HOST still wins in Automatic.
- S3 — Sidebar card: Colima as today. Other engines: kicker with the engine name, title = engine name, "Engine <version> · <n> CPU · <m> GiB", one "Open <App>" button; Profiles hidden. No engine answering: "DOCKER", "No engine running", "Start Colima, Docker Desktop or OrbStack", Start Colima when Colima is installed.
- S4 — Menu bar popover: subtitle "Profile: default" for Colima, the engine name otherwise; tiles CPU / Memory / Disk ("<n> cores", "<m> GiB", "<used> used"); "Open <App>" instead of Restart VM / Stop VM.
- S5 — Cleanup: "<Engine> disk" title and "used by images, cache, volumes and containers" without a total; note "<Engine> sets its disk size in its own settings, so ColiUI shows what Docker uses, not the free space."
- S6 — Colima-only behaviour stays off with other engines: "Start Colima when ColiUI opens", the Colima VM notification, `colima list` polling.
- S7 — Existing users keep working: a custom socket saved before this change becomes Engine = Custom socket.

Assumption: Docker Desktop reports OperatingSystem "Docker Desktop" and OrbStack "OrbStack" in `/info`; used only to name an engine reached through DOCKER_HOST or a custom socket. Not verified against a real install (none on this Mac).

## Tasks

- T1 (S1, S2, S7) Engine kinds, socket candidates, detection and `/info` in ColiUICore; Engine setting with migration — inline — done
- T2 (S3–S6) Sidebar card, menu bar, Cleanup and Settings follow the engine — inline — done

Risk: item 3 (the Docker socket setting others already use changes shape; migration keeps saved values).

## Log

- L1 (2026-11-03) "una cosa final que tan complejo seria hacer que funcione en linux?" → dropped. "ok descartada esa, otra idea que tanto esfuerzo lleva que dicha ui sea compatible con docker en lugar de colima" → "hace sentido lo que digo?" → "ok que habria que hacer" → "si" (design first) → Engines.dc.html approved ("Se ve bien").
- L2 (2026-11-03) Verified in the app: Colima unchanged (card, Restart/Stop, Profiles); OrbStack simulated with a temporary `~/.orbstack/run/docker.sock` link to Colima's socket → "ORBSTACK · Running", "Engine 29.5.2 · 4 CPU · 3.8 GiB", Profiles hidden, no Open button (OrbStack not installed); Docker Desktop with no socket → "No engine running". Found and fixed: the unreachable message said "Is Colima running?" and offered Start Colima for every engine. Deviation: the design's "ColiUI checks again every few seconds" became "Start one, then reopen ColiUI", because the socket is chosen at launch. Link and setting removed afterwards.
- L3 (2026-11-03) Independent verifier: blocker B1 — a saved custom socket pointing at a Colima profile (and a DOCKER_HOST to a non-default Colima profile) was treated as an unknown engine, losing Colima's controls until /info answered; fixed by naming sockets under ~/.colima as Colima and fetching /info before the Colima check, with tests. Also: menu bar icon follows the engine, empty custom socket falls back to detection, doc comment moved.
