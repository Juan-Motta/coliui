# Create modals and About

Objective: Run container closes on an outside click; Pull image, New volume, New network and New profile become modals (PullImageModal / NewVolumeModal / NewNetworkModal / NewProfileModal.dc.html); Settings gets an About tab (Settings.dc.html).
Branch: `main` (commits, no push) · Runner: `swift test` (full suite).

## Specs

- S1 — Run container, Pull image, New volume, New network and New profile open as modals over the whole window (sidebar included), styled like RunContainer.dc.html; a click outside closes them; the screen behind takes no clicks or shortcuts.
- S2 — Pull image: closing the modal (outside click) leaves a running pull going; Cancel stops it.
- S3 — New profile: its own settings; the editor keeps the selected profile; refreshing the list doesn't close the modal.
- S4 — Settings › About: icon, "ColiUI", "Version x (build)", tagline; "This Mac": Colima version · profile (vm type), Docker Engine version · API, macOS version · chip, Docker socket; Copy diagnostics (→ "Copied"), GitHub repository, Report an issue.

## Tasks

- T1 — S4 · inline · core: `colima version` and `/version` + tests — done
- T2 — S1–S4 · inline · modal host, four modals, About tab + tests — done (318 tests). Visually accepted (L2).

## Log

- L1 (2026-11-02, user, verbatim): "quiero ajustar que con run container si se clickea fuera del modal se cierre, pull image debe abrir un modal , new volume igual modal, new network igual, new profile igual y en settings incluir una parte de about" — designed first on the canvas, approved: "Se ve bien".
- L2 (2026-11-02, user, verbatim): "Se ve bien"
