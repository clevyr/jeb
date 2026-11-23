#!/bin/sh
# run.sh: build and run the unit tests for the sprite encoding (art/src/*.swift except main.swift, the jebart
# command, plus art/tests/*.swift). The only file it writes besides the runner is one .ts under TMPDIR, removed again.
set -eu
cd "$(dirname "$0")/../.."
REPO=$PWD
BIN=${JEBART_TESTS_BIN:-$REPO/art/jebart-tests}        # gitignored

SRC=""
for f in "$REPO"/art/src/*.swift; do
    [ "$(basename "$f")" = main.swift ] || SRC="$SRC $f"
done
# shellcheck disable=SC2086
swiftc -warnings-as-errors -I "$REPO"/art/CZlib -o "$BIN" $SRC "$REPO"/art/tests/*.swift
JEB_REPO=$REPO "$BIN"
