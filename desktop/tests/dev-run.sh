#!/bin/sh
# dev-run.sh: tests dev/run (the repo-only dev entry point) against stubs. HOME, the dev home, the store folder
# and every binary are throwaway: a fake launchctl fails the test if anything calls it, the "installed jebctl"
# logs its argv, the "dev app" is a shell stub that records its environment and sleeps, and the "claude" prints
# what it was given. Nothing here touches ~/.jeb, ~/Library, ~/.claude or a real Jeb.
#
#   sh desktop/tests/dev-run.sh
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RUN=$ROOT/dev/run
T=$(mktemp -d "${TMPDIR:-/tmp}/jeb-dev-run.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P)
FAILS=0
cleanup() {
  [ -f "$H/dev.pid" ] && kill -KILL "$(cat "$H/dev.pid")" 2>/dev/null
  rm -rf "$T"
}
trap cleanup EXIT INT TERM

for v in $(env | sed -n 's/^\(JEB_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
HOME=$T/home; export HOME
H=$T/dev-home
REAL="$HOME/Library/Application Support/Jeb"
mkdir -p "$HOME" "$T/bin" "$T/store"
export JEB_DEV_HOME=$H JEB_DEV_STORE_DIR=$T/store JEB_DEV_JEBCTL=$T/jebctl JEB_DEV_BIN=$T/devbin JEB_DEV_CLAUDE=$T/claude JEB_DEV_APP_NAME=sleep
PATH=$T/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH

printf '#!/bin/sh\ntouch "%s/launchctl-called"\nexit 1\n' "$T" > "$T/bin/launchctl"
cat > "$T/jebctl" <<STUB
#!/bin/sh
# status reports what the seed files say; every other call is logged with whether JEB_HOME was set
if [ "\$1" = status ]; then
  if [ -e "$HOME/seed-running" ]; then echo "running: 1"; else echo "running: 0"; fi
  exit 0
fi
echo "\$* JEB_HOME=\${JEB_HOME-unset}" >> "$T/jebctl.log"
STUB
cat > "$T/devbin" <<STUB
#!/bin/sh
env > "$T/launch.env"
echo \$\$ > "\$JEB_PID_FILE"
exec sleep 300
STUB
cat > "$T/claude" <<'STUB'
#!/bin/sh
for a in "$@"; do echo "ARG:$a"; done
echo "JEB_HOME=$JEB_HOME"
echo "JEB_DROP_NOW=${JEB_DROP_NOW-absent}"
STUB
chmod +x "$T/bin/launchctl" "$T/jebctl" "$T/devbin" "$T/claude"

ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; FAILS=$((FAILS + 1)); }
# eq NAME WANT GOT
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '      want: %s\n      got:  %s\n' "$2" "$3"; fi; }
reset() { rm -rf "$H" "$T/jebctl.log" "$T/launch.env" "$T/store"/* "$HOME/seed-running" "$REAL"; }
log() { cat "$T/jebctl.log" 2>/dev/null; }

REPO_JSON=$ROOT/mod/.claude-plugin/plugin.json
REPO_HASH=$(shasum -a 256 "$REPO_JSON" | cut -c1-64)
STORE=$T/store/jeb-dev_inline-574da5d906c7.json

# ---- --dry-run: a literal plan, and nothing happens ----
reset
got=$(sh "$RUN" start --dry-run --no-build 2>&1); rc=$?
want="dev/run start: dry run, nothing is changed
  dev home   $H
  store      $STORE
  installed  record its state in $H/restore, then
             $T/jebctl pause-updates (unless already paused)
             $T/jebctl quit (if running)
  sync       copy mod/ to $H/plugin
  build      skipped (--no-build)
  launch     $T/devbin (detached; stderr appended to $H/run.log)
    env      JEB_HOME=$H
             JEB_STORE_PATH=$STORE
             JEB_MOD=$ROOT/mod
             JEB_PID_FILE=$H/dev.pid
             JEB_LAUNCHAGENTS=$H/no-agents
             JEB_NO_LAUNCHCTL=1
             JEB_DEFAULTS_SUITE=com.jeb.desktop.dev
    unset    JEB_START JEB_HANDOFF_FROM"
eq "dry-run: exit 0" 0 "$rc"
eq "dry-run: the plan" "$want" "$got"
[ ! -e "$H" ] && [ ! -e "$T/jebctl.log" ] && [ ! -e "$T/launch.env" ] && ok "dry-run: nothing created or called" || bad "dry-run: nothing created or called"

# ---- refusals ----
reset
JEB_DEV_HOME=$REAL sh "$RUN" start --no-build >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && [ ! -e "$T/launch.env" ] && [ ! -e "$T/jebctl.log" ] && ok "refuses the real Jeb home" || bad "refuses the real Jeb home (rc $rc)"
JEB_DEV_HOME=$HOME/.claude/jeb-desktop sh "$RUN" start --no-build >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && [ ! -e "$T/launch.env" ] && ok "refuses the legacy Jeb home" || bad "refuses the legacy Jeb home (rc $rc)"
JEB_DEV_HOME=$REAL sh "$RUN" stop --purge >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && ok "refuses stop --purge on the real Jeb home" || bad "refuses stop --purge on the real Jeb home"

# ---- start: installed app running, updates on ----
reset
touch "$HOME/seed-running"
JEB_HOME=bogus JEB_START=launchd JEB_HANDOFF_FROM=1234 JEB_HOLIDAY=none sh "$RUN" start --no-build >"$T/start.out" 2>&1; rc=$?
eq "start: exit 0" 0 "$rc"
eq "start: pause-updates, then quit, JEB_HOME unset" "pause-updates JEB_HOME=unset
quit JEB_HOME=unset" "$(log)"
eq "start: restore" "paused_before=0
running_before=1" "$(cat "$H/restore")"
want="JEB_DEFAULTS_SUITE=com.jeb.desktop.dev
JEB_HOLIDAY=none
JEB_HOME=$H
JEB_LAUNCHAGENTS=$H/no-agents
JEB_MOD=$ROOT/mod
JEB_NO_LAUNCHCTL=1
JEB_PID_FILE=$H/dev.pid
JEB_STORE_PATH=$STORE"
eq "start: launch env (JEB_START and JEB_HANDOFF_FROM unset)" "$want" "$(grep '^JEB_' "$T/launch.env" | grep -v '^JEB_DEV_' | sort)"
PID=$(cat "$H/dev.pid" 2>/dev/null)
kill -0 "$PID" 2>/dev/null && ok "start: dev app running under the pid in dev.pid" || bad "start: dev app running under the pid in dev.pid"
[ ! -e "$T/launchctl-called" ] && ok "start: launchctl never called" || bad "start: launchctl never called"

# staged plugin
P=$H/plugin
eq "sync: staged name" '"name": "jeb-dev",' "$(grep '"name"' "$P/.claude-plugin/plugin.json" | sed 's/^ *//')"
sed 's/"name": "jeb-dev"/"name": "jeb"/' "$P/.claude-plugin/plugin.json" > "$T/restored.json"
eq "sync: other fields unchanged" "$REPO_HASH" "$(shasum -a 256 "$T/restored.json" | cut -c1-64)"
for f in hooks/register.tsx hooks/flags.ts hooks/pixel-art.ts types/index.d.ts; do
  [ -f "$P/$f" ] && ok "sync: $f staged" || bad "sync: $f staged"
done
nrepo=$(grep -c "atom({ plugin: 'jeb'," "$ROOT/mod/hooks/register.tsx")
[ "$nrepo" -gt 0 ] && ok "sync: repo atoms are owned by jeb ($nrepo)" || bad "sync: repo atoms are owned by jeb"
eq "sync: staged atoms owned by jeb-dev" "$nrepo" "$(grep -c "atom({ plugin: 'jeb-dev'," "$P/hooks/register.tsx")"
eq "sync: no staged atom left owned by jeb" "0" "$(cat "$P"/hooks/*.ts "$P"/hooks/*.tsx | grep -c "atom({ plugin: 'jeb',")"
[ ! -e "$P/art/out" ] && ok "sync: art previews left out" || bad "sync: art previews left out"
eq "sync: repo plugin.json untouched" "$REPO_HASH" "$(shasum -a 256 "$REPO_JSON" | cut -c1-64)"

# status, and a second start refuses while the first lives
sh "$RUN" status > "$T/status.out" 2>&1
grep -q "dev app: running, pid $PID" "$T/status.out" && ok "status: running pid" || bad "status: running pid"
grep -q "installed Jeb is paused/quit by dev/run; run dev/run stop" "$T/status.out" && ok "status: restore warning" || bad "status: restore warning"
: > "$T/jebctl.log"
sh "$RUN" start --no-build >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && [ -z "$(log)" ] && ok "refuses a second start with a live dev.pid" || bad "refuses a second start with a live dev.pid (rc $rc)"

# claude
sh "$RUN" claude --resume abc "two words" > "$T/claude.out" 2>&1
want="ARG:--plugin-dir
ARG:$P
ARG:--settings
ARG:{\"enabledPlugins\":{\"jeb@jeb\":false,\"jeb@inline\":false}}
ARG:--resume
ARG:abc
ARG:two words
JEB_HOME=$H
JEB_DROP_NOW=absent"
eq "claude: argv and JEB_HOME, extra args passed through" "$want" "$(cat "$T/claude.out")"
JEB_DROP_NOW=9 sh "$RUN" claude > "$T/claude.out" 2>&1
eq "claude: an inherited JEB_DROP_NOW is dropped" "JEB_DROP_NOW=absent" "$(grep '^JEB_DROP_NOW=' "$T/claude.out")"
sh "$RUN" claude --surprise x > "$T/claude.out" 2>&1
eq "claude --surprise: JEB_DROP_NOW=1 and no --surprise in argv" "ARG:x
JEB_DROP_NOW=1" "$(grep -v -e '^ARG:--plugin-dir' -e "^ARG:$P" -e '^ARG:--settings' -e '^ARG:{' -e '^JEB_HOME=' "$T/claude.out")"
rm -rf "$P"
sh "$RUN" claude >/dev/null 2>&1
[ -f "$P/.claude-plugin/plugin.json" ] && ok "claude: syncs when plugin/ is missing" || bad "claude: syncs when plugin/ is missing"

# stop
sh "$RUN" stop > "$T/stop.out" 2>&1; rc=$?
eq "stop: exit 0" 0 "$rc"
kill -0 "$PID" 2>/dev/null && bad "stop: dev app terminated" || ok "stop: dev app terminated"
[ ! -e "$H/dev.pid" ] && [ ! -e "$H/restore" ] && ok "stop: dev.pid and restore removed" || bad "stop: dev.pid and restore removed"
eq "stop: start, then resume-updates (the log was emptied after start)" "start JEB_HOME=unset
resume-updates JEB_HOME=unset" "$(log)"
sh "$RUN" stop >/dev/null 2>&1; rc=$?
eq "stop: idempotent" 0 "$rc"
eq "stop: second run calls nothing more" 2 "$(log | wc -l | tr -d ' ')"

# ---- updates already paused, installed app not running: neither is touched ----
reset
mkdir -p "$REAL"; touch "$REAL/updates-paused"
sh "$RUN" start --no-build >/dev/null 2>&1
eq "pre-paused: no pause-updates, no quit" "" "$(log)"
eq "pre-paused: restore" "paused_before=1
running_before=0" "$(cat "$H/restore")"
sh "$RUN" stop >/dev/null 2>&1
eq "pre-paused: stop calls neither resume-updates nor start" "" "$(log)"
[ -e "$REAL/updates-paused" ] && ok "pre-paused: the pause file is still there" || bad "pre-paused: the pause file is still there"

# ---- pre-paused and running: quit and start, but no resume ----
reset
mkdir -p "$REAL"; touch "$REAL/updates-paused" "$HOME/seed-running"
sh "$RUN" start --no-build >/dev/null 2>&1
sh "$RUN" stop >/dev/null 2>&1
eq "pre-paused, running: quit then start, never resume-updates" "quit JEB_HOME=unset
start JEB_HOME=unset" "$(log)"

# ---- --alongside: the installed Jeb is never touched ----
reset
touch "$HOME/seed-running"
sh "$RUN" start --alongside --no-build >/dev/null 2>&1; rc=$?
eq "alongside: exit 0" 0 "$rc"
[ ! -e "$T/jebctl.log" ] && [ ! -e "$H/restore" ] && ok "alongside: no jebctl calls, no restore" || bad "alongside: no jebctl calls, no restore"
[ -s "$T/launch.env" ] && ok "alongside: dev app launched" || bad "alongside: dev app launched"
sh "$RUN" stop >/dev/null 2>&1
[ ! -e "$T/jebctl.log" ] && ok "alongside: stop calls nothing" || bad "alongside: stop calls nothing"

# ---- the one command: start, a dev session, then stop when it ends ----
reset
JEB_DEV_NO_BUILD=1 sh "$RUN" --resume abc > "$T/up.out" 2>&1
rc=$?
eq "up: exit 0" 0 "$rc"
[ -s "$T/launch.env" ] && ok "up: dev app launched" || bad "up: dev app launched"
grep -qx "ARG:$P" "$T/up.out" && grep -qx "ARG:--resume" "$T/up.out" && grep -qx "ARG:abc" "$T/up.out" && grep -qx "JEB_HOME=$H" "$T/up.out" && ok "up: dev session opened with the args" || bad "up: dev session opened with the args"
eq "up: installed Jeb paused, then restored when the session ends" "$(printf 'pause-updates JEB_HOME=unset\nresume-updates JEB_HOME=unset')" "$(log)"
[ ! -e "$H/dev.pid" ] && [ ! -e "$H/restore" ] && ok "up: dev app stopped, restore cleared" || bad "up: dev app stopped, restore cleared"

reset
JEB_DEV_NO_BUILD=1 sh "$RUN" --surprise --resume abc > "$T/up.out" 2>&1
grep -qx "JEB_DROP_NOW=1" "$T/up.out" && grep -qx "ARG:--resume" "$T/up.out" && grep -qx "ARG:abc" "$T/up.out" && ! grep -q -e "--surprise" "$T/up.out" && ok "up --surprise: JEB_DROP_NOW=1, args passed, --surprise stripped" || bad "up --surprise: JEB_DROP_NOW=1, args passed, --surprise stripped"
reset
JEB_DEV_NO_BUILD=1 sh "$RUN" --resume abc --surprise > "$T/up.out" 2>&1
grep -qx "JEB_DROP_NOW=1" "$T/up.out" && grep -qx "ARG:abc" "$T/up.out" && ! grep -q -e "--surprise" "$T/up.out" && ok "up: --surprise last works too" || bad "up: --surprise last works too"
reset
JEB_DEV_NO_BUILD=1 sh "$RUN" --resume abc > "$T/up.out" 2>&1
grep -qx "JEB_DROP_NOW=absent" "$T/up.out" && ok "up: no JEB_DROP_NOW without --surprise" || bad "up: no JEB_DROP_NOW without --surprise"

# ---- a first argument that is not a subcommand runs up and goes to claude (no usage, no exit 2) ----
reset
JEB_DEV_NO_BUILD=1 sh "$RUN" hello there > "$T/up.out" 2>&1; rc=$?
eq "non-subcommand first arg: exit 0, not usage" 0 "$rc"
grep -qx "ARG:hello" "$T/up.out" && grep -qx "ARG:there" "$T/up.out" && ok "non-subcommand first arg: runs up and passes the args to claude" || bad "non-subcommand first arg: runs up and passes the args to claude"
! grep -q "^usage:" "$T/up.out" && ok "non-subcommand first arg: no usage printed" || bad "non-subcommand first arg: no usage printed"
eq "non-subcommand first arg: the installed Jeb paused, then restored" "$(printf 'pause-updates JEB_HOME=unset\nresume-updates JEB_HOME=unset')" "$(log)"

# ---- stop: a live dev.pid that is not the dev app is left alone, but dev.pid and restore are cleaned up ----
reset
mkdir -p "$H"
printf 'paused_before=1\nrunning_before=0\n' > "$H/restore"
tail -f /dev/null &
OTHER=$!
echo "$OTHER" > "$H/dev.pid"
sh "$RUN" stop > "$T/stop.out" 2>&1; rc=$?
eq "stop, not the dev app: exit 0" 0 "$rc"
grep -q "pid $OTHER in dev.pid is not the dev app; left alone" "$T/stop.out" && ok "stop, not the dev app: says it is left alone" || bad "stop, not the dev app: says it is left alone"
kill -0 "$OTHER" 2>/dev/null && ok "stop, not the dev app: the process is not killed" || bad "stop, not the dev app: the process is not killed"
[ ! -e "$H/dev.pid" ] && [ ! -e "$H/restore" ] && ok "stop, not the dev app: dev.pid removed and restore consumed" || bad "stop, not the dev app: dev.pid removed and restore consumed"
grep -q "installed Jeb restored" "$T/stop.out" && ok "stop, not the dev app: restores" || bad "stop, not the dev app: restores"
kill -KILL "$OTHER" 2>/dev/null
wait "$OTHER" 2>/dev/null

# ---- stop --purge ----
reset
sh "$RUN" start --alongside --no-build >/dev/null 2>&1
echo '{}' > "$STORE"
sh "$RUN" stop --purge >/dev/null 2>&1
[ ! -e "$H" ] && [ ! -e "$STORE" ] && ok "stop --purge: dev home and store removed" || bad "stop --purge: dev home and store removed"

[ ! -e "$T/launchctl-called" ] && ok "launchctl was never called" || bad "launchctl was never called"
if [ $FAILS -eq 0 ]; then echo "dev-run: all passed"; else echo "dev-run: $FAILS failed"; exit 1; fi
