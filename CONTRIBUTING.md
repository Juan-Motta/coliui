# Contributing to ColiUI

Thanks for helping. Pull requests are welcome; these rules keep them easy to review and merge.

## Before you open a pull request

1. Build and test locally:

   ```bash
   swift build --build-tests
   swift test --skip-build
   scripts/check-conventions.sh
   ```

   With only the Command Line Tools, `swift build` can stop once on "TestingMacros" — run it again.
2. Check the change in the app: `scripts/bundle.sh && open build/ColiUI.app`.
3. Open the pull request against `main`. CI runs the same checks and must pass.

## Rules

| Rule | Why |
| --- | --- |
| **No `@State`.** Keep UI state in an `@Observable` model (a view model or `AppModel`). | `@State` is a macro whose plugin ships only with Xcode, so the app stops building with the Command Line Tools. CI builds with Xcode and wouldn't catch it; `scripts/check-conventions.sh` does. |
| **[Conventional Commits](https://www.conventionalcommits.org):** `feat(app): …`, `fix(core): …`, `refactor`, `perf`, `docs`, `test`, `ci`. | Release notes group commits by type. Anything else lands under "Other changes". |
| **Interface changes start in the design canvas.** Describe the change in the pull request; the maintainer updates the canvas (a copy lives in [`design/`](design/README.md)). | The app follows the canvas exactly, so a change that isn't there drifts from it. |
| **Use the design system:** `Palette`, `.ui()` / `.mono()` fonts and the shared button styles in `Sources/ColiUI/Shared/DesignSystem.swift`. | Fixed colours like `.red` or `.black.opacity(…)` don't follow light and dark mode or the design. |
| **Add tests for logic** (parsers, view models, rules) under `Tests/`. | Views aren't tested; the logic behind them is. |
| **Blocking I/O never runs on Swift's concurrency pool:** use `BlockingIO`. | A blocked cooperative thread stalls the whole UI (it once made the terminal lag). |

## Layout

`ColiUICore` holds the domain, ports and adapters (Docker Engine API, the `colima` CLI) with no third-party dependencies; `ColiUI` is the SwiftUI app. See the README's "How it works".

## Security

Report vulnerabilities privately; see [SECURITY.md](SECURITY.md).
