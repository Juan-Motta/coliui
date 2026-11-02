# Run container

Objective: start a new container from a form, exactly as RunContainer.dc.html.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test` (full suite).

## Specs

- S1 — "Run container" (⌘N) opens a sheet "Run a new container": Image, Name (optional), Ports (host → container, tcp/udp), Volumes (host path or volume → container path, folder picker), Environment (KEY = value, "+ Add variable · Import .env file…"), Restart (no / unless-stopped / always / on-failure), "Remove when stopped (--rm)", "Pull latest image".
- S2 — "Equivalent command" shows the matching `docker run` live, masking values of variables whose name contains PASSWORD, SECRET, TOKEN or KEY; Copy copies the unmasked command.
- S3 — Run = optional pull (`POST /images/create`), create (`POST /containers/create?name=`), start. If create says the image is missing, pull and retry once. Pull errors reported inside the 200 stream are surfaced.
- S4 — Validation before sending: image required; ports 1–65535 and container port required on filled rows; container paths absolute; variable names non-empty; name matches `[a-zA-Z0-9][a-zA-Z0-9_.-]*`; `--rm` can't be combined with a restart policy.
- S5 — On success the sheet closes, the list refreshes and a toast says "Started <name>"; on failure the error shows in the sheet and the form stays.

## Tasks

- T1 — S2, S3 · inline · core RunRequest + runner + tests — done (36c7df4)
- T2 — S1, S4, S5 · inline · view model + sheet + tests — done (102 tests green; live run of hello-world --rm created, started and self-removed). Visual check pending.

## Log

- L1 (2026-11-01, user, verbatim): "Run container"
