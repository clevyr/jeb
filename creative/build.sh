#!/bin/sh
# Builds jeb-creative-build, the creative builder (Foundation, CryptoKit), from src/*.swift. The ordered JSON value comes from
# desktop/cli/Json.swift. Not shipped: it runs on the owner's Mac only, so it is built for this Mac's architecture.
# JEB_OUT names the output (default jeb-creative-build, gitignored). While the Python script still sits at that path, build to
# JEB_OUT=jeb-creative-build-next.
set -e
cd "$(dirname "$0")"
OUT="${JEB_OUT:-jeb-creative-build}"
if [ -f "$OUT" ] && [ "$(head -c 2 "$OUT")" = "#!" ]; then
    echo "build: $PWD/$OUT is a script; build to JEB_OUT=jeb-creative-build-next or remove the Python first" >&2
    exit 1
fi
swiftc -O -warnings-as-errors src/*.swift ../desktop/cli/Json.swift -o "$OUT.tmp"
mv -f "$OUT.tmp" "$OUT"
