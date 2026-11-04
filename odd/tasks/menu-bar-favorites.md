# Menu bar — Compose groups, Restart and favorites

Objective: the popover lists containers grouped like the main window, with Restart, and follows the user's favorites (MenuBar.dc.html, Favorites.dc.html).
Branch: fix/menu-bar-usage (after the PR #1 fixes, 718b97d). Delivery: ask-on-risk. Test runner: `swift test`.

## Specs

- S1 — "no sera posible el poder agruparlas por compose o invividuales como en la ventana principal para que se vea un poco mas ordenado": popover containers grouped by Compose project (folder icon, name, running / total badge), standalone ones under "Standalone"; groups collapse.
- S2 — "podriamos agregar un boton de reset? a los containers": Restart next to Stop on each running container; Compose groups get Restart all and Stop all (Start all when none runs).
- S3 — "una opcion para marcar containers favoritos o algo asi de tal manera que si ese container o grupo de containers esta corriendo se muestre si no que se muestren los primeros 8": a star on containers and Compose projects in the main window (and "Add to Favorites" in the container menu). Some favorite running → the popover lists only the running favorites under "★ FAVORITES"; otherwise "CONTAINERS", the first N A to Z. A starred project counts all its containers. Favorites are kept per engine and Colima profile.
- S4 — "agregar una opcion en settings para controlar cuantos contenedores se quieren mostrar en el popover": Settings › General › Menu bar › Containers to show: 4, 8, 12, All (default 8). Favorites always show in full.

## Tasks

- T1 (S3, S4) Favorites, the popover list rule and the limit setting, with tests — inline — done
- T2 (S1, S2) Popover groups with Restart and group actions — inline — done
- T3 (S3, S4) Stars in the main window, container menu item, Settings option — inline — done

Risk: none expected (new local preferences; no stored data changes shape).

## Log

- L1 (2026-11-04) The four requests above, verbatim; MenuBar.dc.html (groups, Restart) and Favorites.dc.html (favorites, Settings limit) approved: "Se ve bien".
- L2 (2026-11-04) Built; 7 new tests (list rule, favorites, limit, persistence per scope). Main window checked: stars by the project name and in each row's leading gutter. Popover still to be checked by the user.
