# Images

Objective: list, pull, run from and remove Docker images, exactly as Images.dc.html.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test` (full suite).

## Specs

- S1 — Header "Images" with "N images · SIZE" (unique images, decimal size), Refresh and Sort capsule, Search, tinted "Pull image" button.
- S2 — Pull bar (opened by "Pull image"): "Image" field, progress bar with "Downloading 62%" style text, Cancel (stops a running pull or closes the bar) and Pull; pull errors show in the bar.
- S3 — Filters "All (n)", "In use (n)", "Unused (n)", "Dangling (n)" and the note "Images in use can't be removed while a container uses them".
- S4 — Table REPOSITORY / TAG / IMAGE ID / CREATED / SIZE / USED BY / ACTIONS; one row per tag; IMAGE ID "sha256:4be1c0"; CREATED "12 min ago"; USED BY green dot + container names, gray "Unused", orange "Dangling"; dangling rows show `<none>` in gray.
- S5 — Actions: Run opens the Run container sheet with the image filled in; Remove (confirmation) is disabled while a container uses the image; tagged rows remove `repo:tag`, dangling rows remove by ID.

## Tasks

- T1 — S1–S5 · inline · core: image list, remove, streamed pull progress, container image ID + tests — done (bbe2125; live list + hello-world re-pull)
- T2 — S1–S5 · inline · view model + screen + tests — done (136 tests). Visual check pending; no real remove run.

## Log

- L1 (2026-11-01, user, verbatim): "Images" — no design existed; the user chose "Diseñar primero", then approved Images.dc.html: "Se ve bien".
