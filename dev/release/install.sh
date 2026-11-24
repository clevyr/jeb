#!/bin/sh
# Jeb's one-line installer, uploaded with every release:
#   curl -fsSL https://github.com/clevyr/jeb/releases/latest/download/install.sh | sh
# It puts the release's jebctl at ~/.jeb/bin/jebctl (the copy that always works, even off PATH) and runs
# `jebctl install`, which fetches the newest signed release, verifies it against the pinned signers and installs it
# (or updates and repairs an existing install). Arguments are passed on: `... | sh -s -- --no-agents`.
# $JEB_RELEASE_BASE overrides the release location and $JEB_TOOLS_DIR the folder (tests).
# Everything is inside main, called on the last line, so a partly downloaded script runs nothing and the shell has
# read the whole script before jebctl starts (when piped, jebctl shares the shell's stdin).
set -eu

main() {
    if [ "$(uname -s)" != Darwin ]; then
        echo "Jeb runs on macOS only." >&2
        exit 1
    fi
    base="${JEB_RELEASE_BASE:-https://github.com/clevyr/jeb/releases}"
    bin="${JEB_TOOLS_DIR:-$HOME/.jeb/bin}"
    url="$base/latest/download/jebctl-macos"
    mkdir -p "$bin"
    # a new file renamed over the old one: overwriting a signed binary in place can get it killed
    trap 'rm -f "$bin/jebctl.new"' EXIT
    if ! curl -fsSL "$url" -o "$bin/jebctl.new"; then
        echo "Could not download jebctl from $url; check the network." >&2
        exit 1
    fi
    chmod +x "$bin/jebctl.new"
    mv -f "$bin/jebctl.new" "$bin/jebctl"
    rc=0
    "$bin/jebctl" install "$@" || rc=$?
    exit "$rc"
}

main "$@"
