#!/bin/sh
# Builds release, the owner's release tool (Foundation and CryptoKit only). Not shipped: ./release runs it. The JSON
# value, the clock, the child-process runner, the signers and the HTTPS client come from desktop/cli. JEB_OUT names the
# output (default release, here; gitignored).
set -e
cd "$(dirname "$0")"
OUT="${JEB_OUT:-release}"
CLI=../../desktop/cli
swiftc -O ./*.swift "$CLI/Json.swift" "$CLI/Env.swift" "$CLI/Home.swift" "$CLI/State.swift" "$CLI/Signers.swift" "$CLI/Tags.swift" \
  "$CLI/Fetch.swift" -o "$OUT.tmp"
mv -f "$OUT.tmp" "$OUT"
