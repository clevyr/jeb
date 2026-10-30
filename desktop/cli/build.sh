#!/bin/sh
# Builds jebctl, the native command teammates run (Foundation and CryptoKit only). Every command is forwarded to the
# installed Jeb's Python jebctl except `install` and `--version`, which a standalone copy answers itself. JEB_OUT names
# the output (default jebctl), JEB_VERSION the version it reports (default dev). JEB_UNIVERSAL=1 builds arm64 and
# x86_64 (macOS 12) and joins them with lipo; the release ships that binary.
set -e
cd "$(dirname "$0")"
OUT="${JEB_OUT:-jebctl}"
VER="${JEB_VERSION:-dev}"
case "$VER" in *[!A-Za-z0-9._+-]*) echo "build: JEB_VERSION has odd characters" >&2; exit 1 ;; esac
GEN=$(mktemp -d)
trap 'rm -rf "$GEN"' EXIT
printf 'let jebctlVersion = "%s"\n' "$VER" > "$GEN/Version.swift"
FILES="main.swift $GEN/Version.swift"
if [ -n "$JEB_UNIVERSAL" ]; then
  for a in arm64 x86_64; do
    swiftc -O $FILES -target "$a-apple-macos12" -o "$OUT.$a.tmp"
  done
  lipo -create "$OUT.arm64.tmp" "$OUT.x86_64.tmp" -output "$OUT.tmp"
  rm -f "$OUT.arm64.tmp" "$OUT.x86_64.tmp"
  codesign --force --sign - "$OUT.tmp" # lipo drops the linker's ad-hoc signature
else
  swiftc -O $FILES -o "$OUT.tmp"
fi
mv -f "$OUT.tmp" "$OUT"
