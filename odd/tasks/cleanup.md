# Cleanup (prune)

Objective: show what Docker uses on the Colima disk and free reclaimable space, exactly as Cleanup.dc.html.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test` (full suite; `--filter` breaks with the CLT).

## Specs

- S1 — Disk card: "Colima VM disk · <profile>", Docker data used of the profile's disk size, a segmented bar (images, build cache, volumes, containers, free) with legend, and the note "Colima disks can only grow — freeing space inside the VM is the only way to reclaim it."
- S2 — Reclaimable cards with a checkbox, title, description, count and size: Dangling & unused images; Stopped containers (names); Unused volumes ("Deletes data permanently"); Build cache. Defaults: everything but volumes selected.
- S3 — Footer: "Selected: <size> to free", "Review items…" (lists the items of each card), "Clean up selected" (asks for confirmation, prunes each selected category, shows how much was freed, rescans).
- S4 — Header "Cleanup" with "Last scanned …" and Rescan; the sidebar's Cleanup row shows the total reclaimable once scanned.
- Sources: `GET /system/df` (prefers the engine's `*Usage.Reclaimable` when present), prunes via `POST /images/prune` (dangling=false), `/containers/prune`, `/volumes/prune` (all=true), `/build/prune?all=1`.

## Tasks

- T1 — S1–S3 · inline · core disk usage + prune + tests — pending
- T2 — S1–S4 · inline · view model + view + sidebar total + tests — pending

## Log

- L1 (2026-11-01, user, verbatim): "Sí, limpieza"
- L2: Real `/system/df` (API 1.54) returns ImageUsage/ContainerUsage/VolumeUsage/BuildCacheUsage with TotalSize and Reclaimable next to the per-item arrays; took ~1 s. The VM root fs (`colima ssh -- df /`) isn't the Docker data disk, so usage is Docker's own total over the configured disk size.
