#!/usr/bin/env bash
# Catches project-specific mistakes the compiler on GitHub (Xcode) doesn't: see CONTRIBUTING.md.
set -euo pipefail

cd "$(dirname "$0")/.."
failed=0

# `@State` is a macro whose plugin ships only with Xcode; with the Command Line Tools it doesn't build.
if matches="$(grep -rnE '^[[:space:]]*@State[[:space:](]' Sources)"; then
    echo "Don't use @State (it doesn't build with the Command Line Tools); keep UI state in an @Observable model:" >&2
    echo "$matches" >&2
    failed=1
fi

# A doubled backslash before "(" prints the expression's text instead of its value.
if matches="$(grep -rn '\\\\(' Sources)"; then
    echo "Escaped string interpolation (\\\\( prints literally); use \\( instead:" >&2
    echo "$matches" >&2
    failed=1
fi

exit "$failed"
