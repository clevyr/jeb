#!/bin/sh
# Builds JebDesktop (Core Animation; no SpriteKit, no JavaScript, so no JIT
# entitlement). The art is read from the mod's pixel-art.ts as text at run time, so
# nothing is exported or executed here. A running instance sees the new binary and
# hands over to it. JEB_OUT names another output (e.g. JebDesktop.dev, for checks that
# must not hand the live desktop over to a build under review). JEB_UNIVERSAL=1 builds arm64 and
# x86_64 (macOS 12) and joins them with lipo; the release ships that binary.
set -e
cd "$(dirname "$0")"
OUT="${JEB_OUT:-JebDesktop}"
FILES="main.swift Store.swift Farm.swift Live.swift Story.swift FarmScene.swift Valley.swift Strip.swift Homestead.swift Camp.swift Area.swift Road.swift Cast.swift Broadcast.swift Holiday.swift Art.swift PixelArt.swift StatusMenu.swift UpdateStatus.swift AgentHeal.swift JebLines.swift BannerArt.swift Banner.swift UpdateNotifier.swift IconExport.swift EmojiExport.swift Heartbeat.swift Probe.swift Bench.swift Defaults.swift"
FW="-framework AppKit -framework QuartzCore -framework Metal"
if [ -n "$JEB_UNIVERSAL" ]; then
  for a in arm64 x86_64; do
    swiftc -O $FILES -target "$a-apple-macos12" -o "$OUT.$a.tmp" $FW
  done
  lipo -create "$OUT.arm64.tmp" "$OUT.x86_64.tmp" -output "$OUT.tmp"
  rm -f "$OUT.arm64.tmp" "$OUT.x86_64.tmp"
else
  swiftc -O $FILES -o "$OUT.tmp" $FW
fi
mv -f "$OUT.tmp" "$OUT" # one rename, so a watcher never sees half a binary
