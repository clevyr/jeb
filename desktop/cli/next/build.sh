#!/bin/sh
# Builds the dev jebctl: the Swift runtime port (desktop/cli/*.swift except main.swift, the shipped launcher, which
# ../build.sh compiles on its own) with this folder's dispatch and probes. Not shipped; desktop/tests/check.sh --impl swift
# runs it against the goldens until the cutover. JEB_OUT names the output (default jebctl, here; gitignored).
set -e
cd "$(dirname "$0")"
OUT="${JEB_OUT:-jebctl}"
FILES=""
for f in ../*.swift; do
  [ "$(basename "$f")" = main.swift ] || FILES="$FILES $f"
done
# shellcheck disable=SC2086
swiftc -O $FILES ./*.swift -o "$OUT.tmp"
mv -f "$OUT.tmp" "$OUT"
