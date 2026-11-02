# Colima profiles

Objective: list Colima profiles, edit their resources, create and delete them, exactly as Profiles.dc.html.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test` (full suite).

## Specs

- S1 — Header "Colima profiles" with "N profiles · M running" and a tinted "New profile" button.
- S2 — Profile list: status dot, name, "4 CPU · 8 GiB · 100 GiB · vz · docker", Running/Stopped, a "docker context" pill on the profile ColiUI uses; clicking selects it.
- S3 — Editor "Edit “<name>”": CPUs stepper, Memory slider (1–32 GiB), Disk slider (current size up to 500 GiB, "Disk can grow but never shrink"), VM type vz/qemu and Runtime (only when creating), Mount type (virtiofs/sshfs/9p), Rosetta switch (vz only). Buttons Delete… (confirmation, `colima delete <name> --force`), Revert, Apply & restart (`colima stop` if running, then `colima start <name> --cpus --memory --disk --mount-type --vz-rosetta=`; confirmation when running).
- S4 — New profile: name field (letters, digits, "-"), defaults 2 CPU · 2 GiB · 100 GiB · vz · virtiofs · docker, "Create & start" runs `colima start <name> … --vm-type --runtime`.
- S5 — Long commands show progress ("Applying…", "Creating…", "Deleting…") and keep the editor disabled; errors show the last line of colima's stderr.
- Source of current settings: `colima list --json` plus `~/.colima/<name>/colima.yaml` (mountType, rosetta, vmType, runtime).

## Tasks

- T1 — S3–S5 · inline · core settings + commands + tests — done (8bb555f; live read of the real colima.yaml)
- T2 — S1–S5 · inline · view model + screen + tests — done (119 tests; RED caught a reload clearing the apply error). Visually accepted (L3); no real apply/create/delete run (they restart or remove VMs).

## Log

- L1 (2026-11-01, user, verbatim): "Perfiles de Colima"
- L2: colima 0.10.3 flags: -c/--cpus, -m/--memory (GiB float), -d/--disk (GiB), -t/--vm-type (qemu, vz, krunkit), --mount-type (sshfs, 9p, virtiofs), --vz-rosetta, -r/--runtime (docker, incus, containerd); `colima delete --force`. Config at ~/.colima/<profile>/colima.yaml with top-level `cpu`, `memory`, `disk`, `vmType`, `rosetta`, `mountType`, `runtime`.
- L3 (2026-11-01, user, verbatim): "Se ve bien"
