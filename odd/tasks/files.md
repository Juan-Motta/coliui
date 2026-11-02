# Files

Objective: the container detail Files tab, exactly as Files.dc.html: browse folders, preview text files, download.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test` (full suite).

## Specs

- S1 — Tabs: Logs, Stats, Terminal, Files, Inspect, Environment. Files uses the full width and starts in the container's working directory (`/` when it has none).
- S2 — Toolbar: Back, Enclosing folder, Refresh in a glass capsule; the path as clickable segments (`/ app src`); "Filter this folder"; "Hidden files" toggle (names starting with `.`).
- S3 — Table NAME (folder / file / symlink icon, `→ target` for links) / SIZE / MODIFIED / MODE; click selects, double-click opens a folder; footer "N items · M hidden". Folders first, then files, by name.
- S4 — Preview panel: name; Kind, Size, Modified, Mode, Owner; "Download…" (file) / "Download folder…" (a `.tar`), "Copy path", "Shell here" (Terminal tab, `cd` into the folder). Text files up to 256 KB show their contents; larger ones say "Too large to preview (over 256 KB). Download it instead."; binary files say so; with nothing selected the panel describes the folder ("Select a file to preview it.").
- S5 — Footer "Read-only · double-click a folder to open it · lists with docker exec, downloads through the archive API · previews show the first 256 KB of text files". Containers without `sh`/`stat` (distroless) or a stopped container show a clear message instead of the listing.

## Tasks

- T1 — S1, S3–S5 · inline · core: listing via `docker exec sh -c 'stat …'`, archive reads (tar), working directory + tests — done (live: 11 containers — GNU stat, BusyBox, 3 distroless reported as no shell)
- T2 — S1–S5 · inline · view model + tab + tests — done (284 tests). Visual check pending.

## Log

- L1 (2026-11-02, user, verbatim): "finalmente me gustaria tener una opcion para ver los files del contenedor y explorar por las carpetas del mismo" — designed first on the canvas, approved: "Se ve bien".
- L2 (2026-11-02): assumption — folders are listed before files (the mockup mixes dot files first); listing needs `sh` and `stat` in the container.
- L3 (2026-11-02, user, verbatim): "hay una esquina u cuadro blanco abajo a la derecha" — the scroll-bar corner of the two-axis preview drew in light mode; dark panels now use dark scrollers (also Inspect Raw).
