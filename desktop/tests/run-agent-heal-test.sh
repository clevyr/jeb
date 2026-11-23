#!/bin/sh
# Compiles desktop/src/AgentHeal.swift with agent-heal-test.swift (plain swiftc, no XCTest) in a temp dir and runs it.
set -e
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/jeb-agent-heal.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
cp "$here/agent-heal-test.swift" "$tmp/main.swift"     # top-level code must be main.swift when more than one file compiles
swiftc -warnings-as-errors "$here/../src/AgentHeal.swift" "$tmp/main.swift" -o "$tmp/agent-heal-test"
"$tmp/agent-heal-test"
