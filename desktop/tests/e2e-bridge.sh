#!/bin/sh
# End-to-end check of the bridge: an installed v1.6.x (the old Python `follow`) updates itself to a schema 2 bundle whose own Swift
# `apply` runs the gates, with the real JebDesktop and the dev jebctl.
#   sh desktop/tests/e2e-bridge.sh                 BRIDGE_TAG=v1.6.0 (the default) is the installed release
# The installed release is `git archive` of $BRIDGE_TAG; the new one is built by dev/release (bundle --from-tree) with a
# throwaway ed25519 key that is also the pinned signer, into a file:// release tree (JEB_RELEASE_BASE). Everything lives in a
# fresh mktemp -d: HOME, JEB_HOME, JEB_APP_DIR, JEB_LAUNCHAGENTS, JEB_BIN_DIR, JEB_TOOLS_DIR, JEB_STORE_DIR, JEB_NO_LAUNCHCTL=1;
# the real ~/.jeb, ~/Library, ~/.claude and ~/.ssh are never read or written, and no network is used. The old follow's rollback
# leg is not exercised here: the rollback floor moves to v1.6.0 at the cutover and Q4 covers it (apply's own rollback is in
# apply-e2e.sh). Exit 0 when every assertion passes, 1 otherwise.
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
BRIDGE_TAG=${BRIDGE_TAG:-v1.6.0}
NEW_TAG=v9.9.9
T=$(mktemp -d "${TMPDIR:-/tmp}/jeb-e2e-bridge.XXXXXX")
trap 'rm -rf "$T"' EXIT INT TERM
FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { if [ "$2" = ok ]; then pass "$1"; else fail "$1: $3"; fi }
die() { echo "FAIL $1"; exit 1; }

git -C "$REPO" rev-parse -q --verify "refs/tags/$BRIDGE_TAG" >/dev/null || die "no tag $BRIDGE_TAG in $REPO"
ARCH=$(uname -m)

echo "building JebDesktop, the dev jebctl and the release tool in $T"
mkdir -p "$T/build" "$T/stage"
JEB_OUT="$T/build/JebDesktop" sh "$REPO/desktop/src/build.sh" >"$T/build.log" 2>&1 || { cat "$T/build.log"; die "build JebDesktop"; }
JEB_PROBES=1 JEB_OUT="$T/build/jebctl" sh "$REPO/desktop/cli/build.sh" >>"$T/build.log" 2>&1 || { cat "$T/build.log"; die "build jebctl"; }
JEB_OUT="$T/build/release" sh "$REPO/dev/release/build.sh" >>"$T/build.log" 2>&1 || { cat "$T/build.log"; die "build the release tool"; }
cp "$T/build/JebDesktop" "$T/build/jebctl" "$REPO/desktop/src/tools/detect" "$REPO/desktop/src/tools/png2raw" "$T/stage/"
/usr/bin/codesign -s - -f "$T/stage/jebctl" >>"$T/build.log" 2>&1 || die "codesign the staged jebctl"

# the world: HOME and every path override inside $T
H="$T/home"
JH="$H/Library/Application Support/Jeb"
mkdir -p "$H/.jeb/versions" "$H/.jeb/bin" "$H/.local/bin" "$H/Applications" "$H/Library/LaunchAgents" "$T/rel" "$T/fakebin" "$JH"
for n in claude gh launchctl; do
    printf '#!/bin/sh\nexit 0\n' >"$T/fakebin/$n"; chmod 755 "$T/fakebin/$n"
done
ln -s "$T/fakebin/claude" "$H/.local/bin/claude"
world() {
    env PATH="$T/fakebin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$H" TMPDIR="$T" JEB_HOME="$JH" JEB_APP_DIR="$H/Applications" \
        JEB_LAUNCHAGENTS="$H/Library/LaunchAgents" JEB_BIN_DIR="$H/.local/bin" JEB_TOOLS_DIR="$H/.jeb/bin" JEB_STORE_DIR="$H/store" \
        JEB_SETTINGS="$H/.claude/settings.json" JEB_BACKUPS="$H/.claude/backups" CLAUDE_CONFIG_DIR="$H/.claude" \
        JEB_RELEASE_BASE="file://$T/rel" JEB_NO_LAUNCHCTL=1 JEB_TEST_START_SECS=5 JEB_APPLY_WATCH_SECS=2 "$@"
}

# the signer: a throwaway key, pinned, and the one the new bundle lists
ssh-keygen -q -t ed25519 -N '' -C bridge-e2e -f "$T/key" || die "ssh-keygen"
printf 'bridge-e2e namespaces="jeb-release" %s\n' "$(cut -d' ' -f1,2 "$T/key.pub")" >"$T/signers"
cp "$T/signers" "$JH/release-signers"; chmod 600 "$JH/release-signers"
printf "release\n" >"$JH/install-mode"      # follow only runs in release mode

# the installed release: the tag's tree, a schema 1 bundle.json and the python/bin/python3 its follow checks for
V="$H/.jeb/versions/$BRIDGE_TAG"
mkdir -p "$V/python/bin"
git -C "$REPO" archive "$BRIDGE_TAG" | tar -x -C "$V" || die "git archive $BRIDGE_TAG"
ln -s /usr/bin/python3 "$V/python/bin/python3"
printf '{"schema": 1, "repo": "clevyr/jeb", "tag": "%s", "version": "%s", "commit": "%s", "arch": "%s"}\n' \
    "$BRIDGE_TAG" "${BRIDGE_TAG#v}" "$(git -C "$REPO" rev-parse "$BRIDGE_TAG^{commit}")" "$ARCH" >"$V/bundle.json"
ln -s "versions/$BRIDGE_TAG" "$H/.jeb/current"
printf '#!/bin/sh\necho old standalone\n' >"$H/.jeb/bin/jebctl"; chmod 755 "$H/.jeb/bin/jebctl"
printf '{"failed": [], "checked": null, "last": null, "layout": "bundle", "installed": [{"tag": "%s", "stamp": null, "at": 1}], "bridge_reset": 1, "signers_from": "%s"}\n' \
    "$BRIDGE_TAG" "$BRIDGE_TAG" >"$JH/release-state.json"

# the new release (the tool finds this clone through JEB_RELEASE_CLONE): a real schema 2 bundle from this working tree, signed by the pinned key
JEB_RELEASE_CLONE="$REPO" "$T/build/release" bundle --tag "$NEW_TAG" --out "$T/rel/download/$NEW_TAG" --from-tree --app "$T/stage" --key "$T/key" --signers "$T/signers" \
    >"$T/bundle.log" 2>&1 || { cat "$T/bundle.log"; die "release bundle"; }
printf '%s' "$NEW_TAG" >"$T/rel/latest"

js() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2], "") if not isinstance(d.get(sys.argv[2]), dict) else d[sys.argv[2]].get(sys.argv[3], ""))' "$@" 2>/dev/null; }

echo "running the old Python follow ($BRIDGE_TAG)"
world /usr/bin/python3 -I "$H/.jeb/current/desktop/jebctl" follow --no-agents >"$T/follow1.out" 2>&1; rc1=$?
tail -12 "$T/follow1.out" | sed 's/^/    | /'
[ "$rc1" = 0 ] && r=ok || r="exit $rc1"
check "follow exits 0" "$r" "$r"

cur=$(readlink "$H/.jeb/current")
[ "$cur" = "versions/$NEW_TAG" ] && r=ok || r="current is $cur"
check "current moves to $NEW_TAG" "$r" "$r"

LOG="$JH/update.log"
if grep -q "smoke" "$LOG" 2>/dev/null && grep -q "start" "$LOG" 2>/dev/null; then r=ok; else r="update.log lacks the smoke and start gates"; fi
check "update.log has the smoke and start gates" "$r" "$r"
grep -E "smoke|start" "$LOG" 2>/dev/null | head -6 | sed 's/^/    | /'

APP="$H/Applications/JebDesktop.app"
if /usr/bin/codesign --verify "$APP" >/dev/null 2>&1; then r=ok; else r="codesign --verify fails on $APP"; fi
check "the app in JEB_APP_DIR is signed" "$r" "$r"

res=$(js "$JH/release-state.json" last result)
[ "$res" = ok ] && r=ok || r="last.result is '$res'"
check "release-state last.result is ok" "$r" "$r"

if cmp -s "$H/.jeb/bin/jebctl" "$H/.jeb/current/desktop/bin/jebctl" && [ "$(sed -n 1p "$H/.jeb/bin/jebctl")" != "#!/bin/sh" ]; then r=ok; else r="~/.jeb/bin/jebctl was not refreshed from the new bundle"; fi
check "~/.jeb/bin/jebctl is refreshed" "$r" "$r"

# a second follow, by the new bundle's own jebctl (it has no Python launcher): nothing newer, and it removes the old folder
world "$H/.jeb/current/desktop/bin/jebctl" follow --no-agents >"$T/follow2.out" 2>&1
tail -3 "$T/follow2.out" | sed 's/^/    | /'
grep -q "$NEW_TAG is current" "$T/follow2.out" && r=ok || r="no '$NEW_TAG is current' line"
check "a second follow prints the up-to-date line" "$r" "$r"

# doctor from the new bundle. --no-agents installs no LaunchAgents, no ~/.local/bin link and starts no app, so the checks for
# those three are the only FIX lines left out; the plugin store (the fake claude registers nothing) is the other
world "$H/.jeb/current/desktop/bin/jebctl" doctor >"$T/doctor.out" 2>&1
fix=$(grep "^FIX" "$T/doctor.out" | grep -vE "plugin|jebctl command:|LaunchAgent plist|exactly one JebDesktop running" || true)
[ -z "$fix" ] && r=ok || r="doctor has FIX lines:
$fix"
check "doctor has no FIX lines except the plugin store (and the agents, link and running app a --no-agents sandbox lacks)" "$r" "$r"

[ "$FAILS" = 0 ] && { echo "PASS e2e-bridge ($BRIDGE_TAG -> $NEW_TAG)"; exit 0; }
echo "FAIL e2e-bridge: $FAILS check(s) failed"; exit 1
