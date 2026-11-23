#!/bin/sh
# Builds jebart, the art tool (Foundation, CryptoKit, ImageIO and the system zlib via CZlib), from art/src/*.swift. JEB_OUT names the output
# (default jebart, gitignored). It runs on the owner's Mac only, so it is built for this Mac's architecture.
set -e
cd "$(dirname "$0")"
OUT="${JEB_OUT:-jebart}"
swiftc -O -warnings-as-errors -I CZlib src/*.swift -o "$OUT.tmp"
mv -f "$OUT.tmp" "$OUT"
