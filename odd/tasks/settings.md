# Settings

Objective: the Settings window (General, Notifications, Shortcuts) exactly as Settings.dc.html, with every option working.
Branch: `feat/mvp-core` · Delivery: work-unit commits, no push · Runner: `swift test` (full suite).

## Specs

- S1 — Window 680 pt wide, #F5F5F7, centred glass tab capsule "General" / "Notifications" / "Shortcuts" with icons.
- S2 — General › Startup: "Launch ColiUI at login" (login item), "Start Colima when ColiUI opens" (starts the profile if it exists and is stopped), "Show icon in Dock" (off = menu bar only). Defaults as designed: on, on, off.
- S3 — General › Colima: "Default profile" picker, "Docker socket" field with "Detected automatically from the active profile" (empty = detected), "Refresh stats every" 2 seconds / 5 seconds / Off. Profile and socket apply the next time ColiUI opens.
- S4 — General › Appearance: "Theme" System / Light / Dark.
- S5 — Notifications: "Container exited with an error" (non-zero exit), "Restart loop detected" (more than 3 restarts within 5 minutes), "Colima VM stopped or failed to start", "VM disk almost full" (usage passes 80%, opens Cleanup), "Image pull finished" (pulls longer than 10 seconds); defaults on, on, on, on, off; footer "Delivered through macOS Notification Center — allow ColiUI in System Settings › Notifications."
- S6 — Shortcuts: Refresh ⌘R, Search ⌘F, Run container ⌘N, Start / stop selected Space, View logs ⌘L, Open shell ⌘⇧T, Open port in browser ⌘O, Remove selected ⌘⌫, Settings ⌘,. The user chose "Agregar selección": Containers gets row selection (click, ↑/↓) so the selection shortcuts work; ⌘⇧T is listed but disabled until Terminal exists.

## Tasks

- T1 — S1–S4, S6 list · inline · settings model, General tab, window shell, stats interval, start-on-open, Dock, theme, login item + tests — done (172 tests)
- T2 — S5 · inline · notification rules (pure) + Notification Center delivery + tests — done (182 tests; RED not observed for the rules, written together with the code)
- T3 — S6 · inline · container selection + shortcuts + tests — done (188 tests). Visual check pending.

## Log

- L1 (2026-11-01, user, verbatim): "Settings"
- L2 (2026-11-01, user): shortcuts that need a selected container → "Agregar selección (Recommended)".
- L3 (2026-11-01, user, verbatim): "quiero ue settings sea mas como un modal en lugar de otra ventana" — Settings is now a sheet on the main window with a Done button (Esc); ⌘, and the sidebar row open it.
