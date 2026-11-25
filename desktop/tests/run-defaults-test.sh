#!/bin/sh
# Compiles desktop/src/Defaults.swift with defaults-test.swift (plain swiftc, no XCTest) in a temp dir and runs it.
set -e
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/jeb-defaults.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
cp "$here/defaults-test.swift" "$tmp/main.swift"     # top-level code must be main.swift when more than one file compiles
swiftc -warnings-as-errors "$here/../src/Defaults.swift" "$tmp/main.swift" -o "$tmp/defaults-test"
"$tmp/defaults-test"
