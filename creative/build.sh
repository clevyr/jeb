#!/bin/sh
# Builds jeb-creative-build, the creative builder (Foundation, CryptoKit), from src/*.swift. The ordered JSON value comes from
# desktop/cli/Json.swift. Not shipped: it runs on the owner's Mac only, so it is built for this Mac's architecture.
# JEB_OUT names the output (default jeb-creative-build, gitignored).
set -e
cd "$(dirname "$0")"
OUT="${JEB_OUT:-jeb-creative-build}"
swiftc -O -warnings-as-errors src/*.swift ../desktop/cli/Json.swift -o "$OUT.tmp"
mv -f "$OUT.tmp" "$OUT"
