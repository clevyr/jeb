#!/bin/sh
# run.sh: build and run the unit tests for the runtime core (desktop/cli/*.swift except main.swift, the shipped
# launcher, which build.sh compiles on its own), then diff the jebhome and updater-status probes against the goldens
# capture-goldens.sh froze from the Python. Nothing here touches ~/.jeb, ~/Library or the LaunchAgents: HOME, TMPDIR
# and every JEB_* path point into a throwaway folder (under $JEBCTL_TESTS_TMP when set, else TMPDIR).
set -eu
cd "$(dirname "$0")/../../.."
REPO=$PWD
CLI=$REPO/desktop/cli
BIN=${JEBCTL_TESTS_BIN:-$CLI/jebctl-tests}        # gitignored
ARCH=$(uname -m)

SRC=""
for f in "$CLI"/*.swift; do
    [ "$(basename "$f")" = main.swift ] || SRC="$SRC $f"
done
# shellcheck disable=SC2086
swiftc -warnings-as-errors -target "$ARCH-apple-macos12" -o "$BIN" $SRC "$CLI"/tests/*.swift

W=$(mktemp -d "${JEBCTL_TESTS_TMP:-${TMPDIR:-/tmp}}/jebctl-tests.XXXXXX")
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
H=$W/home
mkdir -p "$H"

# the goldens' pinned world: 2026-05-28 02:46:40 Chicago, pid 4242, no launchctl
export HOME=$H TMPDIR=$W TZ=America/Chicago LC_ALL=C JEB_TEST_NOW=1780000000 JEB_TEST_PID=4242 JEB_NO_LAUNCHCTL=1 JEB_REPO=$REPO
export JEB_HOME="$H/Library/Application Support/Jeb" JEB_LAUNCHAGENTS=$H/Library/LaunchAgents JEB_APP_DIR=$H/Applications
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
rc=0
"$BIN" || rc=1

# ---- the probes, in a sandbox laid out like capture-goldens.sh's bundle_sb("probe") ----
SB=$W/sb
mkdir -p "$SB/home/.local/bin" "$SB/home/.jeb/versions/v1.4.0" "$SB/home/Library/Application Support/Jeb" "$SB/rel"
printf '#!/bin/sh\n' > "$SB/home/.local/bin/claude"; chmod 755 "$SB/home/.local/bin/claude"
printf '{"schema": 1, "repo": "clevyr/jeb", "tag": "v1.4.0", "version": "1.4.0", "commit": "%s", "arch": "%s"}' "$(printf '%040d' 0)" "$ARCH" > "$SB/home/.jeb/versions/v1.4.0/bundle.json"
ln -s "$SB/home/.jeb/versions/v1.4.0" "$SB/home/.jeb/current"
printf 'v1.6.0' > "$SB/rel/latest"
printf '%s' '<feed><entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.6.0"/></entry><entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.5.0"/></entry><entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.4.0"/></entry><entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.6.0"/></entry><entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.2"/></entry></feed>' > "$SB/rel.atom"

probe() {  # name args...: run the probe and diff its ## rc / ## stdout / ## stderr capture against the golden
    name=$1; shift
    out=$W/$name.out; err=$W/$name.err; got=$W/$name.txt
    prc=0
    env HOME="$SB/home" JEB_HOME="$SB/home/Library/Application Support/Jeb" JEB_RELEASE_BASE="file://$SB/rel" JEB_TOOLS_DIR="$SB/home/.jeb/bin" \
        "$BIN" --probe "$name" "$@" > "$out" 2> "$err" || prc=$?
    {
        printf '## rc\n%s\n\n' "$prc"
        for s in stdout stderr; do
            f=$out; [ "$s" = stdout ] || f=$err
            printf '## %s\n' "$s"
            if [ -s "$f" ]; then sed -e "s|$SB|\$SB|g" -e "s|$ARCH|\$ARCH|g" "$f"; else printf '(empty)\n'; fi
            printf '\n'
        done
    } > "$got"
    if diff -u "$REPO/desktop/tests/golden/runtime/probes/$name.txt" "$got"; then
        echo "probe $name: matches the golden"
    else
        echo "probe $name: DIFFERS from the golden"; rc=1
    fi
}
probe jebhome --sb "$SB" --stub "$BIN"
probe updater-status
exit $rc
