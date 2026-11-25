#!/bin/sh
# End-to-end check that a real install, built from this working tree, migrates every historical Jeb install shape.
#   sh desktop/tests/old-installs-e2e.sh [--keep] [--only "A D"] [--no-standalone]
#
# Builds once (the app, the gate helpers, jebctl) and packs two bundles signed by a throwaway key (v0.0.1 is the one
# installed, v0.0.0 plays the "already installed" v1.9 for scenario D). Each scenario then gets a fresh HOME under one
# mktemp -d box, seeded with the historical shape taken from the real old tags (git archive / git show), and runs
#   <home>/.jeb/versions/v0.0.1/desktop/bin/jebctl install --no-agents --plain
# in the dev/run install-sandbox environment. Scenarios:
#   A clone at ~/jeb, wired            B clone at ~/.jeb/repo, wired      C = A with updates paused and ~/jeb.old(-2) taken
#   D half-migrated (v1.9 + dangling link + old pin)                     E v1.6 schema 1 bundle, legacy_clone = ~/jeb
#   F ~/jeb is not Jeb                 G unwired Jeb clone at ~/jeb       H = A with local changes in the clone
# The standalone jebctl (the curled one) is also run for D (live branch) and E (schema 1, fresh path) against a file://
# release tree; it is built from a copy of desktop/cli whose signerLines hold the throwaway key (the repo is untouched).
#
# Safety: every path is inside the box (asserted before each run), env -i with PATH = system dirs + a stub dir,
# JEB_NO_LAUNCHCTL=1, --no-agents, a stub claude, file:// release base, no network. The only thing run from the repo is
# ./release bundle --from-tree into the box (it may rebuild dev/release/release, as dev/run does). Exit 0 when all pass.
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
KEEP=0; ONLY=""; STANDALONE=1
while [ $# -gt 0 ]; do
    case "$1" in
        --keep) KEEP=1; shift;;
        --only) ONLY=$2; shift 2;;
        --no-standalone) STANDALONE=0; shift;;
        *) echo "usage: old-installs-e2e.sh [--keep] [--only \"A D\"] [--no-standalone]" >&2; exit 2;;
    esac
done
case "$(uname -m)" in arm64) ARCH=arm64;; x86_64) ARCH=x86_64;; *) echo "unsupported arch" >&2; exit 2;; esac

box=$(mktemp -d "${TMPDIR:-/tmp}/jeb-old-installs.XXXXXX") || exit 2
box=$(cd "$box" && pwd -P)
trap '[ "$KEEP" = 1 ] || rm -rf "$box"' EXIT
trap 'exit 130' INT TERM HUP
NEW=v0.0.1; PREV=v0.0.0
stage=$box/stage; rel=$box/rel; log=$box/build.log
mkdir -p "$stage" "$rel/download" "$box/stub" "$box/tmp" "$box/homes"
: > "$log"
FAILS=0; SUMMARY=""; SCEN_FAILS=0; SCEN_PASS=0; SCEN=""
die() { echo "ABORT: $*" >&2; KEEP=1; echo "box kept: $box" >&2; exit 2; }
say() { printf '%s\n' "$*"; }

# ---------------- reporting ----------------
pass() { SCEN_PASS=$((SCEN_PASS + 1)); say "  PASS  $1"; }
fail() { SCEN_FAILS=$((SCEN_FAILS + 1)); FAILS=$((FAILS + 1)); say "  FAIL  $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/          | /'; return 0; }
chk() { # chk <label> <evidence-on-fail> <command...>
    l=$1; ev=$2; shift 2
    if "$@" >/dev/null 2>&1; then pass "$l"; else fail "$l" "$ev"; fi
}
begin() { SCEN=$1; SCEN_FAILS=0; SCEN_PASS=0; say ""; say "=== $1: $2"; }
finish() { SUMMARY="$SUMMARY
$SCEN  pass=$SCEN_PASS fail=$SCEN_FAILS"; }
want() { [ -z "$ONLY" ] || case " $ONLY " in *" $1 "*) return 0;; *) return 1;; esac; }

# ---------------- build ----------------
step() { l=$1; shift; printf '%s ... ' "$l"; if "$@" >>"$log" 2>&1; then echo ok; else echo failed; tail -n 25 "$log"; die "build step failed: $l"; fi; }
echo "box: $box"
step "build the desktop app" sh -c 'cd "$1/desktop/src" && JEB_OUT=JebDesktop.dev ./build.sh' _ "$REPO"
[ -x "$REPO/desktop/src/JebDesktop.dev" ] || BIN=$(ls "$REPO"/desktop/src/JebDesktop* 2>/dev/null | head -1)
BIN=${BIN:-$REPO/desktop/src/JebDesktop.dev}
[ -x "$BIN" ] || die "no built app at $BIN"
cp "$BIN" "$stage/JebDesktop" || die "stage the app"
step "build the gate helpers" sh -c 'cd "$1/desktop/src" &&
    swiftc -O tools/detect-src/main.swift Art.swift PixelArt.swift Farm.swift Holiday.swift -o "$2/detect" &&
    swiftc -O tools/png2raw.swift -o "$2/png2raw"' _ "$REPO" "$stage"
step "build jebctl" sh -c 'cd "$1/desktop/cli" && JEB_OUT="$2/jebctl" JEB_VERSION="$3" sh build.sh && codesign --force --sign - "$2/jebctl"' _ "$REPO" "$stage" "$NEW"
ssh-keygen -q -t ed25519 -N "" -f "$box/key" -C jeb-old-installs-e2e || die "ssh-keygen"
KEYBLOB=$(cut -d' ' -f2 "$box/key.pub")
printf 'jeb-release namespaces="git,jeb-release" %s\n' "$(cut -d' ' -f1,2 "$box/key.pub")" > "$box/signers"
for t in $PREV $NEW; do
    step "pack bundle $t" sh -c 'cd "$1" && ./release bundle --tag "$2" --out "$3/download/$2" --from-tree --app "$4" --key "$5/key" --signers "$5/signers"' _ "$REPO" "$t" "$rel" "$stage" "$box"
    [ -f "$rel/download/$t/Jeb-$t-macos-$ARCH.zip" ] || { ls -R "$rel/download/$t" >&2; die "no zip for $t"; }
done
printf '%s' "$NEW" > "$rel/latest"
echo "release tree:"; ls "$rel/download/$NEW" | sed 's/^/    /'

# ---------------- the standalone jebctl, trusting the throwaway key (built from a copy of the sources) ----------------
SA=""
if [ "$STANDALONE" = 1 ]; then
    mkdir -p "$box/sa-src"
    cp "$REPO"/desktop/cli/*.swift "$REPO/desktop/cli/build.sh" "$box/sa-src/" || die "copy cli sources"
    awk -v key="$(cut -d' ' -f1,2 "$box/key.pub")" '
        /^let signerLines = \[/ { print; printf "    \"jeb-release namespaces=\\\"jeb-release\\\" %s\",\n", key; skip = 1; next }
        skip && /^\]/ { skip = 0 }
        skip { next }
        { print }' "$box/sa-src/Signers.swift" > "$box/sa-src/Signers.swift.new" && mv "$box/sa-src/Signers.swift.new" "$box/sa-src/Signers.swift"
    grep -q "$KEYBLOB" "$box/sa-src/Signers.swift" || die "could not inject the throwaway signer into the standalone copy"
    if step "build the standalone jebctl (throwaway signer)" sh -c 'cd "$1" && JEB_OUT="$2/jebctl-standalone" JEB_VERSION="$3" sh build.sh && codesign --force --sign - "$2/jebctl-standalone"' _ "$box/sa-src" "$stage" "$NEW"; then SA=$stage/jebctl-standalone; fi
fi

# ---------------- the stub claude ----------------
# Stateful: it remembers a marketplace add and a plugin install in $HOME/.claude-stub so `list` and `marketplace list` answer
# what registerPlugin (desktop/cli/Plugin.swift) and the doctor read. Every call is logged to $HOME/claude-calls.log.
cat > "$box/stub/claude" <<'STUB'
#!/bin/sh
S="$HOME/.claude-stub"; mkdir -p "$S"
echo "$*" >> "$HOME/claude-calls.log"
[ "${1:-}" = plugin ] || { echo "UNEXPECTED non-plugin call: $*" >> "$HOME/claude-calls.log"; exit 0; }
shift
case "$1 ${2:-}" in
    "marketplace list") if [ -f "$S/market" ]; then printf '[{"name":"jeb","source":"directory","path":"%s"}]\n' "$(cat "$S/market")"; else echo '[]'; fi; exit 0;;
    "marketplace add") printf '%s' "$3" > "$S/market"; echo "Added marketplace jeb"; exit 0;;
    "marketplace update") exit 0;;
esac
case "$1" in
    list) if [ -f "$S/plugin" ]; then
              v=$(sed -n 's/.*"version"[^"]*"\([^"]*\)".*/\1/p' "$(cat "$S/market")/mod/.claude-plugin/plugin.json" 2>/dev/null | head -1)
              printf '[{"id":"jeb@jeb","version":"%s","scope":"user","enabled":true}]\n' "$v"
          else echo '[]'; fi; exit 0;;
    install) : > "$S/plugin"; echo "Installed $2"; exit 0;;
    update|configure) exit 0;;
    *) echo "UNEXPECTED plugin call: $*" >> "$HOME/claude-calls.log"; exit 0;;
esac
STUB
chmod 755 "$box/stub/claude"

# ---------------- the sandbox environment ----------------
# the same variables dev/run install-sandbox writes into env.sh, under env -i; JEB_HOME stays unset so the state folder
# migration is exercised; JEB_RELEASE_BASE keeps every release lookup on file://
H=""
sbx() { # sbx <command...>: run it in the sandbox world of $H
    env -i PATH="$box/stub:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$H" TMPDIR="$box/tmp" LANG=en_US.UTF-8 SHELL=/bin/zsh TERM=dumb \
        CLAUDE_CONFIG_DIR="$H/.claude" JEB_APP_DIR="$H/Applications" JEB_LAUNCHAGENTS="$H/Library/LaunchAgents" \
        JEB_SETTINGS="$H/.claude/settings.json" JEB_BACKUPS="$H/.claude/backups/jeb" JEB_STORE_DIR="$H/.claude/plugins/store" \
        JEB_BIN_DIR="$H/.local/bin" JEB_NO_LAUNCHCTL=1 JEB_RELEASE_BASE="file://$rel" "$@"
}
under_box() { case "$1" in "$box"/homes/*) return 0;; *) return 1;; esac; }
assert_boxed() {
    for v in "$H" "$H/Applications" "$H/Library/LaunchAgents" "$H/.claude/settings.json" "$H/.claude/backups/jeb" "$H/.claude/plugins/store" "$H/.local/bin" "$H/.jeb"; do
        under_box "$v" || die "unsafe path outside the box: $v"
    done
    case "$H" in "$HOME"|"$HOME"/*) case "$H" in "$box"/*) ;; *) die "HOME for the sandbox is inside the real home: $H";; esac;; esac
}
# the real home must stay untouched: a fingerprint of the places an install could write, taken before and after.
# ~/Library/Application Support/Jeb is left out: an installed Jeb that is running writes there all the time.
real_fp() { for p in "$HOME/.jeb" "$HOME/.local/bin/jebctl" "$HOME/Library/LaunchAgents" "$HOME/.claude/settings.json" "$HOME/Applications"; do
    printf '%s ' "$p"; if [ -e "$p" ] || [ -L "$p" ]; then stat -f '%m %z' "$p" 2>/dev/null || echo ?; else echo absent; fi; done; }
REAL_FP_BEFORE=$(real_fp)

# ---------------- seeding helpers ----------------
GITQ="git -c user.name=e2e -c user.email=e2e@example.invalid -c commit.gpgsign=false -c init.defaultBranch=main"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
new_home() { H=$box/homes/$1; rm -rf "$H"; mkdir -p "$H/.claude" "$H/.local/bin" "$H/Library/LaunchAgents" "$H/Applications" || die "mkdir $H"; assert_boxed; }
seed_clone() { # seed_clone <dir> [tag] [real-git|fake-git]: the old clone, as `git clone` left it
    d=$1; t=${2:-v1.2.0}; mkdir -p "$d"
    git -C "$REPO" archive "$t" | tar -x -C "$d" || die "git archive $t"
    if [ "${3:-real-git}" = real-git ]; then
        $GITQ -C "$d" init -q && $GITQ -C "$d" remote add origin https://github.com/clevyr/jeb.git && $GITQ -C "$d" add -A && $GITQ -C "$d" commit -q -m "v1" || die "git init in $d"
    else
        mkdir -p "$d/.git"; printf '[remote "origin"]\n\turl = https://github.com/clevyr/jeb.git\n' > "$d/.git/config"
    fi
}
plist() { # plist <label> <program-args-json> <env-json> <dir>
    printf '{"Label":"%s","ProgramArguments":%s,"EnvironmentVariables":%s,"RunAtLoad":true}' "$1" "$2" "$3" | plutil -convert xml1 -o "$4/$1.plist" - || die "plutil $1"
}
clone_plists() { # the four LaunchAgents as v1.2.0's plists() wrote them, for the clone at $1
    c=$1; env="{\"PATH\":\"/usr/bin:/bin\",\"JEB_MOD\":\"$c/mod\",\"JEB_SRC\":\"$c/desktop/src\"}"
    d=$H/Library/LaunchAgents
    plist com.jeb.desktop "[\"$H/Applications/JebDesktop.app/Contents/MacOS/JebDesktop\"]" "{\"PATH\":\"/usr/bin:/bin\",\"JEB_MOD\":\"$c/mod\",\"JEB_SRC\":\"$c/desktop/src\",\"JEB_START\":\"launchd\"}" "$d"
    plist com.jeb.desktop.watchdog "[\"/usr/bin/python3\",\"-I\",\"$c/desktop/watchdog.py\"]" "$env" "$d"
    plist com.jeb.desktop.update "[\"/usr/bin/python3\",\"-I\",\"$c/desktop/updater.py\"]" "$env" "$d"
    plist com.jeb.desktop.release "[\"/usr/bin/python3\",\"-I\",\"$c/desktop/jebctl\",\"follow\"]" "$env" "$d"
}
write_settings() { # write_settings <plugin-dirs-value>
    printf '{\n  "model": "opus",\n  "env": {\n    "CLAUDE_CODE_PLUGIN_DIRS": "%s",\n    "OTHER_KEY": "keep"\n  }\n}\n' "$1" > "$H/.claude/settings.json"
}
old_state_folder() { # the pre-1.5 state folder ~/.claude/jeb-desktop, pin = v1.2.0's signers (the "git" namespace only)
    s=$H/.claude/jeb-desktop; mkdir -p "$s"
    git -C "$REPO" show v1.2.0:desktop/release-signers > "$s/release-signers"; chmod 600 "$s/release-signers"
    printf 'release\n' > "$s/install-mode"
    printf 'marker-from-the-old-state-folder\n' > "$s/state-marker"
    printf 'old log\n' > "$s/run.log"; printf 'old release log\n' > "$s/release.log"
}
tree_sum() { # a listing plus a sha256 per file (the git index is left out: a `git status` may refresh it)
    (cd "$1" && { find . | LC_ALL=C sort; find . -type f ! -path ./.git/index -exec shasum -a 256 {} + | LC_ALL=C sort -k2; }) | shasum -a 256 | cut -d' ' -f1
}
tree_count() { (cd "$1" && find . -type f ! -path ./.git/index | wc -l | tr -d ' '); }
unpack_bundle() { # unpack_bundle <tag>: into the sandbox's versions folder, as a release update would
    mkdir -p "$H/.jeb/versions/$1" && ditto -x -k "$rel/download/$1/Jeb-$1-macos-$ARCH.zip" "$H/.jeb/versions/$1" || die "unpack $1"
}
NEWBIN() { echo "$H/.jeb/versions/$NEW/desktop/bin/jebctl"; }

# ---------------- running ----------------
OUT=""; RC=0
run_install() { # run_install <label>: the bundle's own jebctl, as dev/run install-sandbox runs it
    assert_boxed; OUT=$box/out-$SCEN-$1.txt
    sbx "$(NEWBIN)" install --no-agents --plain >"$OUT" 2>&1; RC=$?
    say "  -- install output ($1, exit $RC):"; sed 's/^/     /' "$OUT"
}
run_standalone() { # run_standalone <label>: the curled jebctl in ~/.jeb/bin
    assert_boxed; OUT=$box/out-$SCEN-$1.txt
    mkdir -p "$H/.jeb/bin"; cp "$SA" "$H/.jeb/bin/jebctl"; chmod 755 "$H/.jeb/bin/jebctl"
    sbx "$H/.jeb/bin/jebctl" install --no-agents --plain >"$OUT" 2>&1; RC=$?
    say "  -- standalone install output ($1, exit $RC):"; sed 's/^/     /' "$OUT"
}
DOCTOR=""
run_doctor() {
    assert_boxed; DOCTOR=$box/doctor-$SCEN-$1.txt
    sbx "$H/.local/bin/jebctl" doctor >"$DOCTOR" 2>&1; DRC=$?
}

# ---------------- assertions ----------------
JH_REL="Library/Application Support/Jeb"
c_exit() { [ "$RC" = 0 ] && pass "install exits 0" || fail "install exits 0" "exit $RC"; }
c_current() {
    cur=$(readlink "$H/.jeb/current" 2>/dev/null); res=$(cd "$H/.jeb/current" 2>/dev/null && pwd -P)
    if [ "$res" = "$(cd "$H/.jeb/versions/$NEW" 2>/dev/null && pwd -P)" ] && [ -x "$H/.jeb/current/desktop/bin/jebctl" ]; then pass "~/.jeb/current resolves to the new bundle ($cur)"
    else fail "~/.jeb/current resolves to the new bundle" "current -> '$cur' (resolves '$res'); versions: $(ls "$H/.jeb/versions" 2>/dev/null | tr '\n' ' ')"; fi
}
c_link() {
    t=$(readlink "$H/.local/bin/jebctl" 2>/dev/null)
    if [ "$t" = "$H/.jeb/current/desktop/bin/jebctl" ]; then pass "~/.local/bin/jebctl links to ~/.jeb/current/desktop/bin/jebctl"
    else fail "~/.local/bin/jebctl links to ~/.jeb/current/desktop/bin/jebctl" "link -> '$t'"; fi
}
c_pin() { # the pin is the new bundle's signers, and signers_from is set
    JH=$H/$JH_REL
    if [ -f "$JH/release-signers" ] && grep -q "$KEYBLOB" "$JH/release-signers" && grep 'jeb-release' "$JH/release-signers" | grep -q "$KEYBLOB"; then pass "pin holds the jeb-release key of the new bundle"
    else fail "pin holds the jeb-release key of the new bundle" "pin: $(cat "$JH/release-signers" 2>/dev/null | cut -c1-120)"; fi
    sf=$(plutil -extract signers_from raw -o - "$JH/release-state.json" 2>/dev/null)
    [ -n "$sf" ] && pass "signers_from is set in release-state ($sf)" || fail "signers_from is set in release-state" "$(cat "$JH/release-state.json" 2>/dev/null)"
}
c_state_moved() { # the old state folder moved, the old path links to the new one, the files came along
    JH=$H/$JH_REL
    if [ -d "$JH" ] && [ ! -L "$JH" ] && [ -L "$H/.claude/jeb-desktop" ] && [ "$(cd "$H/.claude/jeb-desktop" && pwd -P)" = "$(cd "$JH" && pwd -P)" ]; then pass "state folder moved to ~/Library/Application Support/Jeb; ~/.claude/jeb-desktop links there"
    else fail "state folder moved to ~/Library/Application Support/Jeb; ~/.claude/jeb-desktop links there" "JH dir=$([ -d "$JH" ] && echo y || echo n) old=$(ls -ld "$H/.claude/jeb-desktop" 2>&1)"; fi
    [ "$(cat "$JH/state-marker" 2>/dev/null)" = marker-from-the-old-state-folder ] && [ -f "$JH/run.log" ] && pass "the old state files came along" || fail "the old state files came along" "$(ls "$JH" 2>&1 | tr '\n' ' ')"
}
c_fresh_state() { [ -d "$H/$JH_REL" ] && pass "state folder exists at ~/Library/Application Support/Jeb" || fail "state folder exists at ~/Library/Application Support/Jeb"; }
c_settings() { # c_settings <old-mod-path>
    if [ -f "$H/.claude/settings.json" ] && ! grep -q "$1" "$H/.claude/settings.json" && grep -q '"model": "opus"' "$H/.claude/settings.json" && grep -q OTHER_KEY "$H/.claude/settings.json"; then pass "settings.json no longer lists $(echo "$1" | sed "s|$H|~|"), other keys kept"
    else fail "settings.json no longer lists the old mod, other keys kept" "$(cat "$H/.claude/settings.json" 2>&1)"; fi
    ls "$H"/.claude/backups/jeb/settings.*.json >/dev/null 2>&1 && pass "a settings backup exists" || fail "a settings backup exists" "$(ls -R "$H/.claude/backups" 2>&1 | head)"
}
c_clone_moved() { # c_clone_moved <orig> <expected-dest> <sum-before> <count-before>
    o=$1; dst=$2; sum=$3; cnt=$4; sd=$(echo "$dst" | sed "s|$H|~|")
    if [ ! -e "$o" ] && [ -d "$dst" ]; then pass "the clone moved to $sd"; else fail "the clone moved to $sd" "orig exists=$([ -e "$o" ] && echo y || echo n); aside: $(ls -d "$H"/jeb* "$H"/.jeb/repo* 2>&1 | tr '\n' ' ')"; fi
    if [ -d "$dst" ] && [ "$(tree_count "$dst")" = "$cnt" ] && [ "$(tree_sum "$dst")" = "$sum" ]; then pass "every file intact in $sd ($cnt files, same checksums)"
    else fail "every file intact in $sd" "files before=$cnt after=$(tree_count "$dst" 2>/dev/null)"; fi
    lc=$(plutil -extract legacy_clone raw -o - "$H/$JH_REL/release-state.json" 2>/dev/null)
    [ "$lc" = "$dst" ] && pass "legacy_clone recorded ($sd)" || fail "legacy_clone recorded ($sd)" "legacy_clone='$lc'"
}
c_plain() { # no line asks the user to run a flag or a manual command; $1 = an allowed pattern (optional)
    bad=$(grep -iE '(run|re-?run|use|pass|try)[: ].*(--[a-z]|jebctl [a-z]|install )|--replace-clone|--repin' "$OUT" | { if [ -n "${1:-}" ]; then grep -vE "$1"; else cat; fi; })
    [ -z "$bad" ] && pass "the plain output tells nobody to run a flag or a manual command" || fail "the plain output tells nobody to run a flag or a manual command" "$bad"
}
c_doctor() { # c_doctor <label> [allowed-Updates-FIX-regex]
    run_doctor "$1"
    sed 's/^/     doctor| /' "$DOCTOR"
    grep -qE '^ *ok ' "$DOCTOR" && pass "doctor ran (exit $DRC)" || fail "doctor ran (exit $DRC)" "$(head -3 "$DOCTOR")"
    # the Updates section only (the agents section says "update agent" too, and --no-agents leaves the old plists alone)
    bad=$(awk '/^[^ ]/ { sec = $0 } sec == "Updates" && /^ *FIX/' "$DOCTOR" | { if [ -n "${2:-}" ]; then grep -vE "$2"; else cat; fi; })
    [ -z "$bad" ] && pass "doctor reports no Updates or pin failures" || fail "doctor reports no Updates or pin failures" "$bad"
    other=$(awk '/^[^ ]/ { sec = $0 } sec != "Updates" && /^ *FIX/' "$DOCTOR")
    [ -n "$other" ] && say "  info  doctor's other FIX lines (not asserted):" && printf '%s\n' "$other" | sed 's/^/          | /'
}
c_stub_claude() { # the stub saw a marketplace add / install or update, and no claude call outside `plugin`
    if grep -qE '^plugin (marketplace add|install|update)' "$H/claude-calls.log" 2>/dev/null && ! grep -q UNEXPECTED "$H/claude-calls.log"; then pass "claude was only called as 'claude plugin ...' (stub)"
    else fail "claude was only called as 'claude plugin ...' (stub)" "$(cat "$H/claude-calls.log" 2>&1)"; fi
}
c_note() { # c_note <label> <regex>
    grep -qE "$2" "$OUT" && pass "$1" || fail "$1" "no line matches /$2/"
}
c_untouched() { # c_untouched <dir> <sum> <count> <label>
    if [ -d "$1" ] && [ "$(tree_sum "$1")" = "$2" ] && [ "$(tree_count "$1")" = "$3" ]; then pass "$4 is untouched"; else fail "$4 is untouched" "$(ls -la "$1" 2>&1 | head)"; fi
}

# ---------------- scenarios ----------------
sc_A() { # clone at ~/jeb (A), or at ~/.jeb/repo (B)
    where=$1
    if [ "$where" = jeb ]; then
        begin A "clone era (v1.0-1.2) at ~/jeb, wired"; C=$H/jeb
    else
        begin B "clone era at ~/.jeb/repo, wired"; C=$H/.jeb/repo; mkdir -p "$H/.jeb"
    fi
    seed_clone "$C" v1.2.0
    clone_plists "$C"; write_settings "$C/mod"; old_state_folder
    ln -s "$C/desktop/jebctl" "$H/.local/bin/jebctl"
    unpack_bundle $NEW
    sum=$(tree_sum "$C"); cnt=$(tree_count "$C")
    [ "$where" = jeb ] && dst=$H/jeb.old || dst=$H/jeb-repo.old
    run_install main
    c_exit; c_current; c_link; c_pin; c_state_moved; c_settings "$C/mod"; c_clone_moved "$C" "$dst" "$sum" "$cnt"; c_stub_claude
    ! grep -q 'local changes' "$OUT" && pass "no 'local changes' note for a clean clone" || fail "no 'local changes' note for a clean clone" "$(grep 'local changes' "$OUT")"
    c_plain; c_doctor main
}
sc_C() {
    begin C "clone era with updates paused; ~/jeb.old and ~/jeb.old-2 already present"
    C=$H/jeb; seed_clone "$C" v1.2.0; clone_plists "$C"; write_settings "$C/mod"; old_state_folder
    : > "$H/.claude/jeb-desktop/updates-paused"
    ln -s "$C/desktop/jebctl" "$H/.local/bin/jebctl"
    mkdir -p "$H/jeb.old" "$H/jeb.old-2"; echo a > "$H/jeb.old/a"; echo b > "$H/jeb.old-2/b"
    s1=$(tree_sum "$H/jeb.old"); s2=$(tree_sum "$H/jeb.old-2")
    unpack_bundle $NEW; sum=$(tree_sum "$C"); cnt=$(tree_count "$C")
    run_install main
    c_exit; c_current; c_link; c_pin; c_state_moved; c_settings "$C/mod"; c_clone_moved "$C" "$H/jeb.old-3" "$sum" "$cnt"
    c_untouched "$H/jeb.old" "$s1" 1 "the existing ~/jeb.old"; c_untouched "$H/jeb.old-2" "$s2" 1 "the existing ~/jeb.old-2"
    [ -e "$H/$JH_REL/updates-paused" ] && pass "updates stay paused (updates-paused in the new state folder)" || fail "updates stay paused" "$(ls -a "$H/$JH_REL")"
    c_note "the output prints the resume note" 'paused.*resume-updates'
    c_plain 'resume-updates'; c_doctor main 'Updates are paused'      # the pause is kept on purpose, so doctor says so
}
# D: a real v1.9-shaped install is made by running the older bundle's own install, then the half-migrated damage is added
seed_D() {
    unpack_bundle $PREV
    assert_boxed; sbx "$H/.jeb/versions/$PREV/desktop/bin/jebctl" install --no-agents --plain >"$box/seedD-$$.txt" 2>&1 || { cat "$box/seedD-$$.txt"; die "could not seed the v1.9-shaped install ($PREV)"; }
    unpack_bundle $NEW
    JH=$H/$JH_REL
    seed_clone "$H/jeb.old" v1.2.0                                  # the clone, already moved aside by the interrupted migration
    git -C "$REPO" show v1.6.0:desktop/release-signers | grep '^anthony' > "$JH/release-signers"; chmod 600 "$JH/release-signers"
    rm -f "$H/.local/bin/jebctl"; ln -s "$H/jeb/desktop/jebctl" "$H/.local/bin/jebctl"     # dangling: ~/jeb is gone
    write_settings "$H/jeb/mod"
    : > "$H/claude-calls.log"
}
sc_D() {
    begin D "Ryan's half-migrated state (v1.9 install, clone already at ~/jeb.old, dangling jebctl link, old personal pin)"
    seed_D
    s=$(tree_sum "$H/jeb.old"); n=$(tree_count "$H/jeb.old")
    [ -L "$H/.local/bin/jebctl" ] && [ ! -e "$H/.local/bin/jebctl" ] && pass "seed: the jebctl link dangles" || fail "seed: the jebctl link dangles"
    run_install main
    c_exit; c_current; c_link; c_pin; c_settings "$H/jeb/mod"; c_stub_claude
    c_untouched "$H/jeb.old" "$s" "$n" "the clone at ~/jeb.old"
    [ ! -e "$H/jeb" ] && pass "no ~/jeb appeared" || fail "no ~/jeb appeared"
    ! grep -q 'anthony' "$H/$JH_REL/release-signers" && pass "the old personal key is gone from the pin" || fail "the old personal key is gone from the pin"
    c_plain; c_doctor main
}
seed_E() {
    V=$H/.jeb/versions/v1.6.0; mkdir -p "$V/python/bin" "$H/.jeb"
    git -C "$REPO" archive v1.6.0 | tar -x -C "$V" || die "git archive v1.6.0"
    printf '#!/bin/sh\nexit 0\n' > "$V/python/bin/python3"; chmod 755 "$V/python/bin/python3"
    printf '{"schema": 1, "repo": "clevyr/jeb", "tag": "v1.6.0", "version": "1.6.0", "commit": "%s", "arch": "%s"}\n' "$(git -C "$REPO" rev-parse v1.6.0^{commit})" "$ARCH" > "$V/bundle.json"
    ln -s versions/v1.6.0 "$H/.jeb/current"
    seed_clone "$H/jeb" v1.2.0
    JH=$H/$JH_REL; mkdir -p "$JH"
    git -C "$REPO" show v1.6.0:desktop/release-signers > "$JH/release-signers"; chmod 600 "$JH/release-signers"
    printf 'release\n' > "$JH/install-mode"
    printf '{"failed": [], "checked": null, "last": null, "layout": "bundle", "installed": [{"tag": "v1.6.0", "stamp": null, "at": 1}], "signers_from": "v1.6.0", "legacy_clone": "%s/jeb"}\n' "$H" > "$JH/release-state.json"
    envv="{\"PATH\":\"/usr/bin:/bin\",\"JEB_MOD\":\"$H/.jeb/current/mod\",\"JEB_SRC\":\"$H/.jeb/current/desktop/src\"}"
    for l in com.jeb.desktop com.jeb.desktop.release; do plist $l "[\"/usr/bin/python3\",\"-I\",\"$H/.jeb/current/desktop/jebctl\",\"follow\"]" "$envv" "$H/Library/LaunchAgents"; done
    write_settings "$H/.jeb/current/mod"
    ln -s "$H/.jeb/current/desktop/jebctl" "$H/.local/bin/jebctl"
    unpack_bundle $NEW
}
sc_E() {
    begin E "v1.3-1.6 schema 1 bundle install; legacy_clone = ~/jeb (a clean clone)"
    seed_E; sum=$(tree_sum "$H/jeb"); cnt=$(tree_count "$H/jeb")
    run_install main
    c_exit; c_current; c_link; c_pin; c_settings "$H/.jeb/current/mod"; c_clone_moved "$H/jeb" "$H/jeb.old" "$sum" "$cnt"; c_stub_claude
    [ ! -d "$H/.jeb/versions/v1.6.0" ] && pass "the old v1.6.0 version folder is gone" || fail "the old v1.6.0 version folder is gone" "$(ls "$H/.jeb/versions")"
    c_plain; c_doctor main
}
sc_F() {
    begin F "not Jeb: an unrelated folder at ~/jeb, fresh machine otherwise"
    mkdir -p "$H/jeb/sub"; echo "my notes" > "$H/jeb/notes.txt"; echo x > "$H/jeb/sub/y"
    s=$(tree_sum "$H/jeb"); n=$(tree_count "$H/jeb"); unpack_bundle $NEW
    run_install main
    c_exit; c_current; c_link; c_pin; c_fresh_state; c_stub_claude
    c_untouched "$H/jeb" "$s" "$n" "~/jeb (not Jeb)"
    ! grep -qE 'safe to delete|old install' "$OUT" && pass "no old-install note for a folder that is not Jeb" || fail "no old-install note for a folder that is not Jeb" "$(grep -E 'safe to delete|old install' "$OUT")"
    [ ! -e "$H/jeb.old" ] && pass "nothing was moved aside" || fail "nothing was moved aside"
    c_plain; c_doctor main
}
sc_G() {
    begin G "an unwired Jeb clone at ~/jeb (nothing points at it)"
    seed_clone "$H/jeb" v1.2.0; s=$(tree_sum "$H/jeb"); n=$(tree_count "$H/jeb"); unpack_bundle $NEW
    run_install main
    c_exit; c_current; c_link; c_pin; c_fresh_state; c_stub_claude
    c_untouched "$H/jeb" "$s" "$n" "~/jeb (unwired clone)"
    [ ! -e "$H/jeb.old" ] && pass "nothing was moved aside" || fail "nothing was moved aside"
    c_note "the safe-to-delete note names ~/jeb" 'safe to delete'
    c_plain; c_doctor main
}
sc_H() {
    begin H "a dirty wired clone at ~/jeb (uncommitted changes)"
    C=$H/jeb; seed_clone "$C" v1.2.0
    printf '\n# local edit\n' >> "$C/README.md"; echo "scratch" > "$C/untracked.txt"
    clone_plists "$C"; write_settings "$C/mod"; old_state_folder; ln -s "$C/desktop/jebctl" "$H/.local/bin/jebctl"
    $GITQ -C "$C" status --porcelain | grep -q . && pass "seed: the clone has uncommitted changes" || fail "seed: the clone has uncommitted changes"
    unpack_bundle $NEW; sum=$(tree_sum "$C"); cnt=$(tree_count "$C")
    run_install main
    c_exit; c_current; c_link; c_pin; c_state_moved; c_settings "$C/mod"; c_clone_moved "$C" "$H/jeb.old" "$sum" "$cnt"; c_stub_claude
    c_note "the local-changes note is printed" 'had local changes.*jeb\.old'
    grep -q 'local edit' "$H/jeb.old/README.md" && [ -f "$H/jeb.old/untracked.txt" ] && pass "the local edit and the untracked file moved with the clone" || fail "the local edit and the untracked file moved with the clone"
    c_plain; c_doctor main
}
sc_standalone_D() {
    begin SD "standalone jebctl, scenario D shape (live schema 2 with a dangling older link: relink)"
    seed_D
    [ -n "$SA" ] || { fail "a standalone jebctl was built" ; return; }
    rm -rf "$H/.jeb/versions/$NEW"        # the standalone must find the release itself
    run_standalone main
    c_exit
    t=$(readlink "$H/.local/bin/jebctl" 2>/dev/null)
    case "$t" in "$H/.jeb/current/desktop/bin/jebctl") pass "~/.local/bin/jebctl links to ~/.jeb/current/desktop/bin/jebctl";; *) fail "~/.local/bin/jebctl links to ~/.jeb/current/desktop/bin/jebctl" "link -> '$t'";; esac
    [ -x "$H/.jeb/current/desktop/bin/jebctl" ] && pass "~/.jeb/current is a valid bundle ($(readlink "$H/.jeb/current"))" || fail "~/.jeb/current is a valid bundle"
    c_pin; c_plain; c_doctor main
}
sc_standalone_E() {
    begin SE "standalone jebctl, scenario E shape (schema 1 bundle: fresh path)"
    seed_E; rm -rf "$H/.jeb/versions/$NEW"
    [ -n "$SA" ] || { fail "a standalone jebctl was built"; return; }
    sum=$(tree_sum "$H/jeb"); cnt=$(tree_count "$H/jeb")
    run_standalone main
    c_exit; c_current; c_link; c_pin; c_settings "$H/.jeb/current/mod"; c_clone_moved "$H/jeb" "$H/jeb.old" "$sum" "$cnt"; c_stub_claude
    c_plain; c_doctor main
}

run_scen() { # run_scen <id> <function> [arg]
    want "$1" || return 0
    new_home "$1"; "$2" ${3:-}; finish
}
run_scen A sc_A jeb
run_scen B sc_A repo
run_scen C sc_C
run_scen D sc_D
run_scen E sc_E
run_scen F sc_F
run_scen G sc_G
run_scen H sc_H
if [ "$STANDALONE" = 1 ]; then
    run_scen SD sc_standalone_D
    run_scen SE sc_standalone_E
else
    say ""; say "standalone scenarios skipped (--no-standalone)"
fi

# ---------------- the real home must be untouched ----------------
say ""
REAL_FP_AFTER=$(real_fp)
if [ "$REAL_FP_BEFORE" = "$REAL_FP_AFTER" ]; then say "  PASS  the real ~/.jeb, ~/.local/bin/jebctl, LaunchAgents, settings and Application Support are unchanged"
else say "  FAIL  the real home changed during the run"; FAILS=$((FAILS + 1)); printf 'before:\n%s\nafter:\n%s\n' "$REAL_FP_BEFORE" "$REAL_FP_AFTER"; fi

say ""; say "=== summary"; printf '%s\n' "$SUMMARY"
[ "$KEEP" = 1 ] && say "box kept: $box"
[ "$FAILS" = 0 ] && { say "ALL PASS"; exit 0; } || { say "$FAILS FAIL"; exit 1; }
