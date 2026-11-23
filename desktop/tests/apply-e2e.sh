#!/bin/sh
# End-to-end check of `jebctl apply` (desktop/cli/Apply.swift) against the real JebDesktop and the dev jebctl.
#   sh desktop/tests/apply-e2e.sh
# Everything lives in a fresh mktemp -d: HOME, JEB_HOME, JEB_APP_DIR, JEB_LAUNCHAGENTS, JEB_BIN_DIR, JEB_TOOLS_DIR,
# JEB_NO_LAUNCHCTL=1. Nothing under the real ~/.jeb, ~/Library or ~/.claude is read or written, and the gates' app
# instances get their own scratch HOME and JEB_HOME (Gates.swift gateEnv), so none can reach a running Jeb.
# The bundle carries the full smoke manifest (desktop/src/fixtures/smoke.json, every parity fixture), as a release
# bundle does, so the smoke gate runs exactly as it will on a user's Mac. Test hooks used:
# JEB_TEST_START_SECS (short start gate), JEB_TEST_FAIL_GATE, JEB_TEST_NO_BEAT, JEB_APPLY_WATCH_SECS.
# Exit 0 when every case passes, 1 otherwise.
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/jeb-apply-e2e.XXXXXX")
trap 'rm -rf "$T"' EXIT
FAILS=0

echo "building JebDesktop and the dev jebctl in $T"
JEB_OUT="$T/build/JebDesktop" sh -c 'mkdir -p "$(dirname "$JEB_OUT")" && sh "$0/desktop/src/build.sh"' "$REPO" >"$T/build.log" 2>&1 || { cat "$T/build.log"; echo "FAIL build JebDesktop"; exit 1; }
JEB_OUT="$T/build/jebctl" sh "$REPO/desktop/cli/next/build.sh" >>"$T/build.log" 2>&1 || { cat "$T/build.log"; echo "FAIL build jebctl"; exit 1; }

# the bundle template: schema 2, the full smoke manifest and its fixtures, the art the gates read
B="$T/template/v9.9.9"
mkdir -p "$B/desktop/bin" "$B/app" "$B/desktop/src/fixtures" "$B/mod/hooks"
printf '{"schema":2,"repo":"x/y","tag":"v9.9.9","version":"9.9.9","commit":"abcdef0123456789","arch":"%s"}\n' "$(uname -m)" >"$B/bundle.json"
cp "$T/build/jebctl" "$B/desktop/bin/jebctl"
cp "$T/build/JebDesktop" "$B/app/JebDesktop"
cp "$REPO/desktop/src/tools/detect" "$REPO/desktop/src/tools/png2raw" "$B/app/"
cp "$REPO/mod/hooks/pixel-art.ts" "$B/mod/hooks/"
cp "$REPO/desktop/src/fixtures/smoke.json" "$REPO"/desktop/src/fixtures/*.store.json "$B/desktop/src/fixtures/"

# a fresh world: previous version, current link, installed app, standalone jebctl, empty state
world() {
    W="$T/w"; rm -rf "$W"
    mkdir -p "$W/home/.jeb/versions/v9.0.0/desktop/bin" "$W/home/.jeb/bin" "$W/jeb" "$W/apps/JebDesktop.app/Contents/MacOS" "$W/agents" "$W/bin"
    cp -R "$B" "$W/home/.jeb/versions/v9.9.9"
    ln -s versions/v9.0.0 "$W/home/.jeb/current"
    echo old >"$W/home/.jeb/versions/v9.0.0/marker"
    printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleVersion</key><string>prev-stamp</string></dict></plist>\n' >"$W/apps/JebDesktop.app/Contents/Info.plist"
    echo previous-binary >"$W/apps/JebDesktop.app/Contents/MacOS/JebDesktop"
    printf '#!/bin/sh\necho old standalone\n' >"$W/home/.jeb/bin/jebctl"; chmod 755 "$W/home/.jeb/bin/jebctl"
    rm -rf "$T/before"; cp -R "$W/apps" "$T/before"
}
# jebctl apply <args>: the sandboxed environment, stdout and stderr to $T/out
japply() {
    HOME="$W/home" JEB_HOME="$W/jeb" JEB_APP_DIR="$W/apps" JEB_LAUNCHAGENTS="$W/agents" JEB_BIN_DIR="$W/bin" \
    JEB_TOOLS_DIR="$W/home/.jeb/bin" JEB_STORE_DIR="$W/home/store" JEB_NO_LAUNCHCTL=1 JEB_TEST_START_SECS=3 \
    "$T/build/jebctl" apply "$@" >"$T/out" 2>&1
}
cur() { readlink "$W/home/.jeb/current"; }
status() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2],""))' "$W/jeb/update-status.json" "$1" 2>/dev/null; }
mode() { stat -f %Lp "$W/jeb/update-status.json" 2>/dev/null; }
app_same() { diff -r "$T/before/JebDesktop.app" "$W/apps/JebDesktop.app" >/dev/null 2>&1; }
verdict() {
    if [ "$2" = ok ]; then echo "PASS $1"; else echo "FAIL $1: $3"; sed 's/^/    | /' "$T/out" | tail -15; FAILS=$((FAILS + 1)); fi
}

# a: gates only touches nothing
world; V="$W/home/.jeb/versions/v9.9.9"
japply "$V" --not-final --lock-held --no-watch --gates-only; rc=$?
res=ok; why=""
[ $rc -eq 0 ] || { res=bad; why="exit $rc"; }
app_same || { res=bad; why="$why app changed"; }
[ "$(cur)" = versions/v9.0.0 ] || { res=bad; why="$why current moved to $(cur)"; }
[ "$(status source)" = release ] && [ "$(status phase)" != done ] || { res=bad; why="$why status source=$(status source) phase=$(status phase)"; }
[ "$(mode)" = 600 ] || { res=bad; why="$why status mode $(mode)"; }
grep -q 'gate smoke' "$W/jeb/update.log" && grep -q 'gate start' "$W/jeb/update.log" || { res=bad; why="$why gates not logged"; }
verdict "a gates-only: exit 0, app and current untouched" $res "$why"

# b: swap, no watch
world; V="$W/home/.jeb/versions/v9.9.9"
japply "$V" --not-final --lock-held --no-watch; rc=$?
res=ok; why=""
[ $rc -eq 0 ] || { res=bad; why="exit $rc"; }
[ "$(cur)" = versions/v9.9.9 ] || { res=bad; why="$why current is $(cur)"; }
app_same && { res=bad; why="$why app not replaced"; }
[ -x "$W/apps/JebDesktop.app/Contents/MacOS/JebDesktop" ] || { res=bad; why="$why no new binary"; }
codesign --verify "$W/apps/JebDesktop.app" >/dev/null 2>&1 || { res=bad; why="$why codesign verify failed"; }
cmp -s "$W/home/.jeb/bin/jebctl" "$V/desktop/bin/jebctl" || { res=bad; why="$why standalone jebctl not refreshed"; }
[ "$(status phase)" != done ] || { res=bad; why="$why phase done under --not-final"; }
[ -d "$V" ] || { res=bad; why="$why version folder gone"; }
verdict "b swap: exit 0, current at v9.9.9, app replaced, jebctl refreshed" $res "$why"

# c: a failing smoke gate
world; V="$W/home/.jeb/versions/v9.9.9"
(JEB_TEST_FAIL_GATE=smoke; export JEB_TEST_FAIL_GATE; japply "$V" --not-final --lock-held --no-watch); rc=$?
res=ok; why=""
[ $rc -eq 2 ] || { res=bad; why="exit $rc"; }
app_same || { res=bad; why="$why app changed"; }
[ "$(cur)" = versions/v9.0.0 ] || { res=bad; why="$why current is $(cur)"; }
cmp -s "$W/home/.jeb/bin/jebctl" "$V/desktop/bin/jebctl" && { res=bad; why="$why jebctl refreshed on a rejection"; }
verdict "c smoke rejected: exit 2, app byte-identical, current unchanged" $res "$why"

# d: watch on, no heartbeat ever: rolled back
world; V="$W/home/.jeb/versions/v9.9.9"
(JEB_TEST_NO_BEAT=1; export JEB_TEST_NO_BEAT; japply "$V" --not-final --lock-held --watch-secs 4); rc=$?
res=ok; why=""
[ $rc -eq 3 ] || { res=bad; why="exit $rc"; }
app_same || { res=bad; why="$why app not restored"; }
[ "$(cur)" = versions/v9.0.0 ] || { res=bad; why="$why current is $(cur)"; }
[ "$(status phase)" != done ] || { res=bad; why="$why phase done"; }
[ -d "$V" ] || { res=bad; why="$why version folder gone"; }
verdict "d no heartbeat: exit 3, current and app restored" $res "$why"

# e: the install form writes the final line itself
world; V="$W/home/.jeb/versions/v9.9.9"
japply "$V" --lock-held --no-watch; rc=$?
res=ok; why=""
[ $rc -eq 0 ] || { res=bad; why="exit $rc"; }
[ "$(cur)" = versions/v9.9.9 ] || { res=bad; why="$why current is $(cur)"; }
[ "$(status phase)" = done ] || { res=bad; why="$why phase is '$(status phase)', not done"; }
[ "$(mode)" = 600 ] || { res=bad; why="$why status mode $(mode)"; }
verdict "e install form: exit 0 and a final status line" $res "$why"

[ $FAILS -eq 0 ] && echo "apply-e2e: all cases passed" || echo "apply-e2e: $FAILS case(s) failed"
[ $FAILS -eq 0 ]
