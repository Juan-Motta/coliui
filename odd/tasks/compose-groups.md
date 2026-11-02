# Compose groups

Objective: group containers by Docker Compose project, exactly as Compose.dc.html.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test`.

## Specs

- S1 — The "Compose groups" toggle shows one card per Compose project (label `com.docker.compose.project`) with the config file path, an "x / y running" badge (green all, orange partial, grey none), a collapse chevron, and Stop all (or Start all when none run), Restart, and Edit compose file (opens the file in the default editor; the in-app editor is not built).
- S2 — Rows show the service name (`com.docker.compose.service`), image, status, first published port as a link with an arrow, a copy-exec button with a "Copied …" toast, and a "…" menu with the container actions.
- S3 — Containers without a project go in a last "Standalone containers" card ("not part of a Compose project").
- S4 — Search filters rows in both views; groups with no matching rows are hidden.

## Tasks

- T1 — S1–S3 · inline · core labels + view model groups/actions + tests — done (fd17733)
- T2 — S1–S4 · inline · Compose groups view — done (529200f; 73 tests green). Visual check pending.

## Log

- L1 (2026-11-01, user, verbatim): "ademas estoy corriendo varios contenedores mediante un compose.yml es posible agruparlos?"
- L2: Real labels include `com.docker.compose.project`, `.service`, `.project.config_files`, `.project.working_dir`.
- L3 (user): "me gustaria alg tipo de feedback para los links de los puertos para saber que puedo clickearlos cuando hago hover" → PortLink underlines + link cursor.
- L4 (user): "ademas me gustaria que comose groups fuera la vista por defecto y lista por si se quiere cambiar" → default viewMode .compose; toggle order kept as designed.
