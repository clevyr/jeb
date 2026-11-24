#!/bin/sh
# Builds creative/jeb-creative-tests (gitignored) from creative/src/*.swift except main.swift, desktop/cli/Json.swift and tests/*.swift, then
# runs it. Options go to the binary: --list, --only NAME..., --skip-slow, -j N (workers, default min(6, CPUs)), --real (H01, N12 and H30 on the real `claude plugin test`, minutes each, alone after the rest; without it the stand-in is used and N12, H30 are skipped with one line). Every folder the tests write is under a mktemp folder the tests
# remove themselves; mod/, ~/.claude, ~/Library/Caches/jeb-creative and the real HOME are only read (the pinned TypeScript, `claude`, node).
# No model is ever called. Run `jeb-creative-build --dry-run` once first so the pinned TypeScript is installed.
set -eu
cd "$(dirname "$0")/../.."
cd "$(pwd -P)"
SRC=""
for f in "$PWD"/creative/src/*.swift; do
    [ "$(basename "$f")" = main.swift ] || SRC="$SRC $f"
done
# shellcheck disable=SC2086
swiftc -warnings-as-errors -o creative/jeb-creative-tests $SRC "$PWD/desktop/cli/Json.swift" "$PWD"/creative/tests/*.swift
exec creative/jeb-creative-tests "$@"
