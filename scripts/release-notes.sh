#!/usr/bin/env bash
# Prints Markdown release notes for <tag>: its conventional commits since the previous tag, grouped by type.
# Usage: scripts/release-notes.sh v0.2.0
set -euo pipefail

TAG="${1:?usage: scripts/release-notes.sh <tag>}"
PREVIOUS="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
RANGE="${PREVIOUS:+$PREVIOUS..}$TAG"
SUBJECTS="$(git log --no-merges --format=%s "$RANGE")"

section() {
    local title="$1" pattern="$2" lines
    # "feat(app): add X" -> "- **app:** add X"; a "!" before the colon still matches the type.
    lines="$(grep -E "^($pattern)(\([^)]*\))?!?: " <<<"$SUBJECTS" \
        | sed -E 's/^[a-z]+\(([^)]*)\)!?: /- **\1:** /; s/^[a-z]+!?: /- /' || true)"
    if [[ -n "$lines" ]]; then
        printf '## %s\n\n%s\n\n' "$title" "$lines"
    fi
}

section "Features" "feat"
section "Fixes" "fix"
section "Performance" "perf"
section "Refactoring" "refactor"

if [[ -n "$PREVIOUS" ]]; then
    REPO_URL="$(gh repo view --json url -q .url 2>/dev/null || true)"
    if [[ -n "$REPO_URL" ]]; then
        printf '**Full changelog:** %s/compare/%s...%s\n' "$REPO_URL" "$PREVIOUS" "$TAG"
    fi
fi
