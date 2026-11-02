# Volumes

Objective: list, create and remove Docker volumes, exactly as Volumes.dc.html.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test` (full suite).

## Specs

- S1 — Header "Volumes" with "N volumes · SIZE", Refresh and Sort capsule, Search, tinted "New volume" button.
- S2 — Create bar: "Name" field, "Driver: local", Cancel and Create; errors show in the bar.
- S3 — Filters "All (n)", "In use (n)", "Unused (n)" and the orange warning "Removing a volume deletes its data permanently".
- S4 — Table NAME / DRIVER / CREATED / SIZE / USED BY / ACTIONS; Compose project chip under the name; anonymous volumes in monospace; USED BY green dot + container names or gray "Unused".
- S5 — Actions: copy the name; Remove (confirmation) is disabled while a container uses the volume.

## Tasks

- T1 — S1–S5 · inline · core: volume list with sizes, create, remove, container volume mounts + tests
- T2 — S1–S5 · inline · view model + screen + tests

## Log

- L1 (2026-11-01, user, verbatim): "Volumes" — designed first on the canvas, approved: "Se ve bien".
