#!/bin/sh
# Builds JebDesktop (Core Animation; no SpriteKit, no JavaScript, so no JIT
# entitlement). The art is read from the mod's pixel-art.ts as text at run time, so
# nothing is exported or executed here. A running instance sees the new binary and
# hands over to it. JEB_OUT names another output (e.g. JebDesktop.dev, for checks that
# must not hand the live desktop over to a build under review).
set -e
cd "$(dirname "$0")"
swiftc -O main.swift Store.swift Farm.swift Live.swift Story.swift FarmScene.swift Valley.swift Strip.swift Homestead.swift Camp.swift Area.swift Road.swift Cast.swift \
  Art.swift PixelArt.swift StatusMenu.swift Heartbeat.swift Probe.swift Bench.swift -o "${JEB_OUT:-JebDesktop}.tmp" \
  -framework AppKit -framework QuartzCore -framework Metal
mv -f "${JEB_OUT:-JebDesktop}.tmp" "${JEB_OUT:-JebDesktop}" # one rename, so a watcher never sees half a binary
