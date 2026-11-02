# ColiUI

A native, lightweight macOS app for managing [Colima](https://github.com/abiosoft/colima) and its Docker containers — a window with a sidebar plus a menu bar extra.

## Requirements

- macOS 26 or later
- Colima (`brew install colima`) with the Docker runtime
- Swift 6.2+ (the Command Line Tools are enough; Xcode is optional)

## Build and run

```bash
swift run ColiUI          # run from source
swift test                # run the test suite
scripts/bundle.sh         # build build/ColiUI.app (release, ad-hoc signed)
open build/ColiUI.app
swift scripts/make-icon.swift   # regenerate Resources/AppIcon.icns from the Paper design
```

## What works today

- Colima status for the `default` profile, with start, stop and restart.
- Containers list with All / Running / Stopped filter, search, start, stop, restart and remove (with confirmation).
- Context menu: open a published port in the browser, copy the container ID or a `docker exec` command.
- Container detail (click a name): live logs with filter, regex, follow, timestamps, time range, export and clear; overview, ports and mounts.
- Menu bar extra with the VM status and quick start/stop per container.

The list updates live from Docker events; CPU and memory refresh every 3 seconds (Colima every 15). Images, volumes, networks, settings and the other detail tabs are designed but not built yet.

```bash
COLIUI_LIVE=1 swift test   # also runs the tests that talk to your real Colima socket
```

`swift test --filter …` fails with the Command Line Tools (the Testing macro plugin isn't loaded); run the whole suite instead.

## Architecture

```
Sources/
  ColiUICore/            no third-party dependencies
    Domain/              Container, ColimaInstance
    Ports/               ContainerRepository, ColimaRuntime
    Adapters/Docker/     HTTP/1.1 over the Colima Unix socket → Docker Engine API
    Adapters/Colima/     `colima` CLI (list --json, start, stop, restart)
  ColiUI/                SwiftUI app: composition root, view models, views
```

The Docker socket is `~/.colima/<profile>/docker.sock`, or a `unix://` `DOCKER_HOST` when set.

> On the macOS 27 SDK, SwiftUI's `@State` is a macro whose plugin ships only with Xcode. To keep the project buildable with the Command Line Tools, UI state lives in `@Observable` models instead of `@State`.
