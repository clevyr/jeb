#!/bin/sh
# Builds jebgates, the desktop's gates (parity, day, fake) as one native tool (Foundation and CryptoKit only). Not
# shipped. The ordered JSON value comes from desktop/cli/Json.swift. JEB_OUT names the output (default jebgates).
set -e
cd "$(dirname "$0")"
OUT="${JEB_OUT:-jebgates}"
swiftc -O main.swift Support.swift Parity.swift Day.swift Fake.swift ../cli/Json.swift ../cli/Gates.swift -o "$OUT.tmp"
mv -f "$OUT.tmp" "$OUT"
