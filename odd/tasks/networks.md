# Networks

Objective: list, create and remove Docker networks, exactly as Networks.dc.html.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test` (full suite).

## Specs

- S1 — Header "Networks" with "N networks · M in use", Refresh and Sort capsule, Search, tinted "New network" button.
- S2 — Create bar: "Name" field, "Driver" picker (bridge, macvlan), "Internal (no internet)" checkbox, Cancel and Create; errors show in the bar.
- S3 — Filters "All (n)", "In use (n)", "Unused (n)" and the note "bridge, host and none are built in and can't be removed".
- S4 — Table NAME / DRIVER / SUBNET / GATEWAY / CONTAINERS / ACTIONS; chip under the name with the Compose project or "Built-in"; CONTAINERS green dot + names or gray "No containers"; "—" when there is no subnet.
- S5 — Actions: copy the name; Remove (confirmation) is disabled for built-in networks and while containers are connected.

## Tasks

- T1 — S1–S5 · inline · core: network list, create, remove, container networks + tests — done (6776272; live read-only list)
- T2 — S1–S5 · inline · view model + screen + tests — done (163 tests). Visually accepted (L2); no real create/remove run.

## Log

- L1 (2026-11-01, user, verbatim): "Networks" — designed first on the canvas, approved: "Se ve bien".
- L2 (2026-11-01, user, verbatim): "Se ve bien"
