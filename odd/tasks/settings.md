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
- T3 — S6 · inline · container selection + shortcuts + tests — done (188 tests). Visually accepted (L5).

## Log

- L1 (2026-11-01, user, verbatim): "Settings"
- L2 (2026-11-01, user): shortcuts that need a selected container → "Agregar selección (Recommended)".
- L3 (2026-11-01, user, verbatim): "quiero ue settings sea mas como un modal en lugar de otra ventana" — Settings is now a sheet on the main window with a Done button (Esc); ⌘, and the sidebar row open it.
- L4 (2026-11-01, user, verbatim): "si presiono fuera del modal se debe cerrar" — replaced the sheet with an overlay modal over a dimmed backdrop; clicking the backdrop, Done or Esc closes it.
- L5 (2026-11-02, user, verbatim): "Se ve bien"
- L14 (2026-11-02, user, verbatim): "cuando abro la ventana no se ve icono en el dock ... si yo abro la ventana deberia verse el icono en el dock, si la cierro solo deberia quedar el icono de arriba a menos de que la cierra explicitamente con quit" — the Dock icon now follows the main window (regular while open, accessory when closed); Settings › Show icon in Dock keeps it when closed.
- L15 (2026-11-02, user, verbatim): "pero si le doy a la x se cierra no queda en segundo plano, me gustaria que la forma de cerrarla total sea por el quit de la barra superior" — closing the only Window scene terminated the app (new pid after reopening); AppDelegate now returns false from applicationShouldTerminateAfterLastWindowClosed. No unit test: calling NSApplication.shared from tests made a timing test flaky; verified by the user instead.
- L16 (2026-11-02, user, verbatim): "Se sigue cerrando" / "afecta que este usando vorssaint" — confirmed with a quit trace: ColiUI answered false to applicationShouldTerminateAfterLastWindowClosed, then received an external Quit Apple Event (_handleAEQuit). Vorssaint has "Quit apps when their last window closes" for Dock apps; ColiUI is a Dock app while its window is open, so Vorssaint quits it. Not an app bug.
