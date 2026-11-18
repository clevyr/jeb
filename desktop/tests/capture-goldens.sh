#!/bin/sh
# capture-goldens.sh: freeze the observable behaviour of the Python parts (desktop/jebctl, updater.py, watchdog.py, jebhome.py,
# plugdirs.py, ./install, ./uninstall, ./release, the src/tools and mod/art generators) as goldens under desktop/tests/golden/, so each
# Swift port can be checked against them. Deterministic: TZ=America/Chicago, LC_ALL=C, a fixed clock (1780000000 = 2026-05-27
# 19:26:40 CDT), fixed pids and random seeds (monkeypatched from outside; no shipped Python file is edited), throwaway ssh keys whose
# public parts are normalized out of every golden. Everything runs in one temp dir (sandbox HOMEs, a file:// release tree, a fake claude,
# gh, launchctl and curl, a C stub for the native binaries); the real install is never read or written. No network.
#
#   sh desktop/tests/capture-goldens.sh            regenerate desktop/tests/golden/{runtime,release,art}
#   sh desktop/tests/capture-goldens.sh --check    regenerate into a temp dir and diff against desktop/tests/golden (exit 1 on a difference)
#   sh desktop/tests/capture-goldens.sh --render   also run parity.py compare against the frozen band-out.txt (needs a built desktop/src/JebDesktop)
#
# The art goldens need Pillow: JEB_ART_PY names the interpreter (default ~/.claude/venvs/jeb-art/bin/python); without one, art/ is skipped.
# This script goes away with the Python it captures.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLD="$ROOT/desktop/tests/golden"
CHECK=0; RENDER=0
for a in "$@"; do
  case "$a" in
    --check) CHECK=1;;
    --render) RENDER=1;;
    *) echo "usage: sh desktop/tests/capture-goldens.sh [--check] [--render]" >&2; exit 2;;
  esac
done
ART_PY=${JEB_ART_PY:-$HOME/.claude/venvs/jeb-art/bin/python}
REALHOME=$HOME
TMP=${TMPDIR:-/tmp}; TMP=${TMP%/}      # macOS's default TMPDIR ends in "/"; a "//" in T would dodge the path normalizer
T=$(mktemp -d "$TMP/jeb-golden.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT INT TERM
if [ $CHECK = 1 ]; then OUT="$T/out"; else OUT="$GOLD"; fi
export TZ=America/Chicago LC_ALL=C LANG=C
unset DEVELOPER_DIR CLAUDE_CONFIG_DIR CLAUDE_CODE_PLUGIN_DIRS
for v in $(env | sed -n 's/^\(JEB_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
mkdir -p "$T/keys" "$T/bin"
for k in old new other; do
  ssh-keygen -q -t ed25519 -N '' -C "$k" -f "$T/keys/$k" || exit 1
done
ARCH=arm64; [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] || ARCH=x86_64
# the stand-in for desktop/bin/jebctl and the app binaries (same as bridge-sandbox.sh): logs its argv to $JEB_STUB_LOG, exits with
# $JEB_STUB_RC, and on `apply <ver>` with exit 0 points $JEB_STUB_FLIP at <ver> as the real apply does
cat > "$T/stub.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int c, char **v) {
  const char *log = getenv("JEB_STUB_LOG"), *rc = getenv("JEB_STUB_RC"), *flip = getenv("JEB_STUB_FLIP");
  if (log) { FILE *f = fopen(log, "a"); if (f) { for (int i = 0; i < c; i++) fprintf(f, "%s%s", i ? " " : "", v[i]); fputc('\n', f); fclose(f); } }
  int code = rc ? atoi(rc) : 0;
  if (flip && code == 0 && c > 2 && !strcmp(v[1], "apply")) {
    char tmp[4096], rel[4096], *b = strrchr(v[2], '/');
    snprintf(tmp, sizeof tmp, "%s.new", flip); snprintf(rel, sizeof rel, "versions/%s", b ? b + 1 : v[2]);
    unlink(tmp); if (symlink(rel, tmp) == 0) rename(tmp, flip);
  }
  return code;
}
EOF
cc -arch "$ARCH" -o "$T/stub" "$T/stub.c" || { echo "could not build the stub" >&2; exit 1; }
cc -arch x86_64 -o "$T/stub-x86_64" "$T/stub.c" 2>/dev/null || cp "$T/stub" "$T/stub-x86_64"
for n in claude gh launchctl; do
  printf '#!/bin/sh\necho "$0 $*" >> "$JEB_FAKE_LOG"\ncase "$*" in "plugin list --json"|"plugin marketplace list --json") echo "[]";; esac\nexit 0\n' > "$T/bin/$n"
  chmod +x "$T/bin/$n"
done
printf '#!/bin/sh\necho "curl: network is off in the golden capture" >&2\nexit 7\n' > "$T/bin/curl"; chmod +x "$T/bin/curl"

# ---- the in-process runner: loads a Python file with the clock, pid and random seed pinned, then runs its main or a probe
cat > "$T/run_jc.py" <<'PYEOF'
"""run_jc.py <spec json>: run a Jeb Python file in this process with time, pid and random pinned.
spec: module (path), argv (list), name (sys.argv[0]), mode: main (sys.exit(m.main(argv))), main0 (m.main()), load (import only),
probe (exec `code` with jc = the module), patches: running (jc.running -> []), notify (updater's notify_finished -> no-op),
git ({"args joined": [rc, stdout, stderr]} canned jc.git)."""
import importlib.machinery, importlib.util, json, os, random, subprocess, sys, time

spec = json.loads(sys.argv[1])
NOW = float(spec.get("now", 1780000000))
clock = [NOW]
_lt, _gm, _sf = time.localtime, time.gmtime, time.strftime
time.time = lambda: clock[0]
time.localtime = lambda t=None: _lt(clock[0] if t is None else t)
time.gmtime = lambda t=None: _gm(clock[0] if t is None else t)
time.strftime = lambda fmt, t=None: _sf(fmt, time.localtime() if t is None else t)


def _sleep(s):
    clock[0] += s       # the clock only moves when something sleeps (fake.py's loop ends; step timings stay 0 s)


time.sleep = _sleep
os.getpid = lambda: int(spec.get("pid", 4242))
random.seed(7)
sys.argv = [spec.get("name", os.path.basename(spec["module"]))] + list(spec.get("argv", []))
loader = importlib.machinery.SourceFileLoader(spec.get("modname", "jc"), spec["module"])
jc = importlib.util.module_from_spec(importlib.util.spec_from_loader(spec.get("modname", "jc"), loader))
patches = spec.get("patches", {})
if "git" in patches:
    canned = patches["git"]

    def fake_git(*a, **kw):
        rc, out, err = canned.get(" ".join(a), [1, "", "fake git: no answer for " + " ".join(a)])
        return subprocess.CompletedProcess(["git"] + list(a), rc, out, err)
try:
    loader.exec_module(jc)
except SystemExit as e:
    if spec.get("mode") == "load":
        raise
    raise
if "git" in patches:
    jc.git = fake_git
if patches.get("running"):
    jc.running = lambda: []
if patches.get("notify") and hasattr(jc, "load_updater"):
    _lu = jc.load_updater

    def load_updater():
        u = _lu()
        u.notify_finished = lambda: None
        return u
    jc.load_updater = load_updater
mode = spec.get("mode", "main")
if mode == "main":
    sys.exit(jc.main(list(spec.get("argv", []))))
elif mode == "main0":
    sys.exit(jc.main())
elif mode == "probe":
    exec(spec["code"], {"jc": jc, "json": json, "os": os, "sys": sys, "spec": spec, "NOW": NOW})
PYEOF

# ---- the driver: sandboxes, scenarios, normalization
cat > "$T/drive.py" <<'PYEOF'
import glob, hashlib, json, os, plistlib, re, shutil, subprocess, sys

ROOT, T, ARCH, OUT, RENDER, REALHOME = sys.argv[1:7]
RUNNER = os.path.join(T, "run_jc.py")
STUB = os.path.join(T, "stub")
KEYS = {n: os.path.join(T, "keys", n) for n in ("old", "new", "other")}
PUB = {n: " ".join(open(k + ".pub").read().split()[:2]) for n, k in KEYS.items()}
PY = "/usr/bin/python3"
NOW = 1780000000
DESK = os.path.join(ROOT, "desktop")
PYFILES = ("jebctl", "jebhome.py", "plugdirs.py", "updater.py", "watchdog.py")
HEAD = subprocess.run(["git", "-C", ROOT, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
PY_REAL = subprocess.run([PY, "-I", "-c", "import sys; print(sys.executable)"], capture_output=True, text=True).stdout.strip()    # what sys.executable resolves to
BASE_ENV = {"TZ": "America/Chicago", "LC_ALL": "C", "LANG": "C"}
COUNTS = {}
SKIPPED = []
FAKE_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"


def line(who, key, ns="git,jeb-release"):
    return f'{who} namespaces="{ns}" {PUB[key]}'


OLD = line("old@example.com", "old") + "\n"
NEW3 = OLD + line("jeb-release", "new") + "\n"
ONLY_NEW = line("jeb-release", "new") + "\n"
sandbox_n = [0]


def path_subs(roots):
    """(path, token) for every spelling of each root: as given, normalized and resolved (/var vs /private/var, "//", trailing "/").
    Longest first, so a nested root wins over its parent and a resolved form over a raw prefix."""
    out = {}
    for root, token in roots:
        for p in (root, os.path.normpath(root), os.path.realpath(root)):
            p = p.rstrip("/")
            if p and p not in out:
                out[p] = token
    return sorted(out.items(), key=lambda kv: -len(kv[0]))


def norm(s, sb=None):
    roots = ([(sb.root, "$SB")] if sb else []) + [(T, "$T"), (ROOT, "$REPO"), (REALHOME, "$REALHOME")]
    subs = path_subs(roots)
    subs += [(v, f"$PUB_{k}") for k, v in PUB.items()] + [(v.split()[1], f"$PUBBLOB_{k}") for k, v in PUB.items()]
    if PY_REAL and PY_REAL != PY:
        subs.append((PY_REAL, "$PYTHON3"))
    for a, b in subs:
        s = s.replace(a, b)
    if HEAD:
        s = re.sub(re.escape(HEAD[:7]) + r"[0-9a-f]*", "$HEAD", s)
    s = re.sub(r"gui/\d+\b", "gui/$UID", s)
    s = re.sub(r"\b[0-9a-f]{64}\b", "$SHA256", s)
    s = re.sub(r"SHA256:[A-Za-z0-9+/]{43}", "$FINGERPRINT", s)
    s = re.sub(r"\((\d+)s\)", "($Ns)", s)
    s = re.sub(r"\b\d+ (KB|MB)\b", r"$N \1", s)
    s = re.sub(r"sha256 [0-9a-f]{16}\b", "sha256 $SHA16", s)
    s = s.replace(ARCH, "$ARCH")
    return s


def write(rel, text):
    p = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text if text.endswith("\n") else text + "\n")
    COUNTS[rel.split("/")[0] + "/" + rel.split("/")[1]] = COUNTS.get(rel.split("/")[0] + "/" + rel.split("/")[1], 0) + 1


def section(title, body):
    body = body.rstrip("\n")
    return f"## {title}\n{body if body.strip() else '(empty)'}\n\n"


def pretty_json(text, sb=None):
    try:
        return json.dumps(json.loads(norm(text, sb)), indent=1, sort_keys=True)
    except ValueError:
        return "(not JSON) " + norm(text, sb)


def read(p):
    try:
        return open(p).read()
    except OSError:
        return None


class SB:
    """One sandbox: HOME and every path override under it (the layout of desktop/tests/bridge-sandbox.sh)."""
    def __init__(self, name):
        sandbox_n[0] += 1
        self.root = os.path.join(T, f"sb{sandbox_n[0]}-{name}")
        h = self.home = os.path.join(self.root, "home")
        self.jeb = os.path.join(h, ".jeb")
        self.state = os.path.join(h, "Library", "Application Support", "Jeb")
        self.agents = os.path.join(h, "Library", "LaunchAgents")
        self.rel = os.path.join(self.root, "rel")
        self.fake = os.path.join(self.root, "fake.log")
        self.stublog = os.path.join(self.root, "stub.log")
        for d in (self.state, self.agents, os.path.join(h, ".local", "bin"), self.rel, os.path.join(h, "Applications")):
            os.makedirs(d)
        os.symlink(os.path.join(T, "bin", "claude"), os.path.join(h, ".local", "bin", "claude"))
        open(self.fake, "w").close()
        self.env = dict(
            PATH=f"{T}/bin:/usr/bin:/bin:/usr/sbin:/sbin", HOME=h, TMPDIR=self.root,
            JEB_HOME=self.state, JEB_APP_DIR=os.path.join(h, "Applications"), JEB_LAUNCHAGENTS=self.agents, JEB_BIN_DIR=os.path.join(h, ".local", "bin"),
            JEB_PROFILE=os.path.join(h, ".zprofile"), JEB_SETTINGS=os.path.join(h, ".claude", "settings.json"), JEB_BACKUPS=os.path.join(h, ".claude", "backups"),
            JEB_STORE_DIR=os.path.join(h, ".claude", "plugins", "data"), CLAUDE_CONFIG_DIR=os.path.join(h, ".claude"), JEB_TOOLS_DIR=os.path.join(h, ".jeb", "bin"),
            JEB_RELEASE_BASE="file://" + self.rel, JEB_NO_LAUNCHCTL="1", JEB_FAKE_LOG=self.fake, JEB_STUB_LOG=self.stublog,
            JEB_STUB_FLIP=os.path.join(self.jeb, "current"))
        assert h.startswith(T) and not self.state.startswith(os.path.expanduser("~/Library"))
        self.mode("release")

    def mode(self, m):
        open(os.path.join(self.state, "install-mode"), "w").write(m + "\n")

    def bundle_tree(self, root, tag, schema=2, signers=NEW3, drop=(), nonmacho=False, scripts=False):
        v = tag[1:]
        for d in ("desktop/bin", "mod/.claude-plugin", ".claude-plugin", "app"):
            os.makedirs(os.path.join(root, d), exist_ok=True)
        json.dump({"schema": schema, "repo": "clevyr/jeb", "tag": tag, "version": v, "commit": "0" * 40, "arch": ARCH}, open(os.path.join(root, "bundle.json"), "w"))
        json.dump({"name": "jeb", "version": v}, open(os.path.join(root, "mod/.claude-plugin/plugin.json"), "w"))
        open(os.path.join(root, ".claude-plugin/marketplace.json"), "w").write("{}")
        open(os.path.join(root, "install"), "w").write("#!/bin/sh\n")
        open(os.path.join(root, "desktop/release-signers"), "w").write(signers)
        for n in ("JebDesktop", "detect", "png2raw"):
            shutil.copy(STUB, os.path.join(root, "app", n))
        ctl = os.path.join(root, "desktop/bin/jebctl")
        if nonmacho:
            open(ctl, "w").write("#!/bin/sh\nexit 0\n")
        else:
            shutil.copy(STUB, ctl)
        os.chmod(ctl, 0o755)
        if schema == 1:
            for f in PYFILES:
                shutil.copy(os.path.join(DESK, f), os.path.join(root, "desktop", f))
            os.makedirs(os.path.join(root, "python/bin"))
            shutil.copy(STUB, os.path.join(root, "python/bin/python3"))
        if scripts:
            for f in ("install", "uninstall"):
                shutil.copy(os.path.join(ROOT, f), os.path.join(root, f))
        for rel in drop:
            p = os.path.join(root, rel)
            shutil.rmtree(p) if os.path.isdir(p) else os.unlink(p)

    def install_bundle(self, tag, signers=NEW3, pin=OLD, signers_from=None, scripts=False, rs=None):
        v = os.path.join(self.jeb, "versions", tag)
        self.bundle_tree(v, tag, schema=1, signers=signers, scripts=scripts)
        os.symlink(os.path.join("versions", tag), os.path.join(self.jeb, "current"))
        if pin is not None:
            self.write_pin(pin)
        if rs is None:
            rs = {"failed": [], "checked": None, "last": None, "layout": "bundle", "installed": [{"tag": tag, "stamp": None, "at": 1}], "bridge_reset": 1}
            if signers_from:
                rs["signers_from"] = signers_from
        self.save_rs(rs)
        self.latest(tag)
        return v

    def write_pin(self, text):
        p = os.path.join(self.state, "release-signers")
        open(p, "w").write(text)
        os.chmod(p, 0o600)

    def save_rs(self, rs):
        json.dump(rs, open(os.path.join(self.state, "release-state.json"), "w"))

    def latest(self, tag):
        open(os.path.join(self.rel, "latest"), "w").write(tag)

    def release(self, tag, key="new", schema=2, signers=NEW3, flaw=None, manifest_tag=None):
        """Publish tag in the file:// tree: zip, manifest, signature (throwaway key `key`), and `latest`."""
        work = os.path.join(self.root, "work-" + tag)
        shutil.rmtree(work, ignore_errors=True)
        self.bundle_tree(work, tag, schema=schema, signers=signers, drop=("mod",) if flaw == "content" else (), nonmacho=flaw == "arch")
        d = os.path.join(self.rel, "download", tag)
        os.makedirs(d, exist_ok=True)
        zname = f"Jeb-{tag}-macos-{ARCH}.zip"
        zp = os.path.join(d, zname)
        if os.path.exists(zp):
            os.unlink(zp)
        subprocess.run(["ditto", "-c", "-k", "--norsrc", "--noextattr", work, zp], check=True)
        sha, size = hashlib.sha256(open(zp, "rb").read()).hexdigest(), os.path.getsize(zp)
        if flaw == "sha":
            sha = "0" * 64
        if flaw == "size":
            size -= 10
        man = os.path.join(d, f"Jeb-{tag}-manifest.json")
        body = {"schema": 1, "repo": "clevyr/jeb", "tag": manifest_tag or tag, "version": tag[1:], "bundles": {ARCH: {"name": zname, "sha256": sha, "size": size}}}
        if flaw == "json":
            open(man, "w").write("{not json")
        else:
            json.dump(body, open(man, "w"))
        if os.path.exists(man + ".sig"):
            os.unlink(man + ".sig")
        subprocess.run(["ssh-keygen", "-q", "-Y", "sign", "-f", KEYS[key], "-n", "jeb-release", man], check=True, capture_output=True)
        self.latest(tag)
        return man, man + ".sig"

    def current_jebctl(self):
        return os.path.join(self.jeb, "current", "desktop", "jebctl")

    # ---- running
    def run(self, argv, cwd=None, **extra):
        env = dict(BASE_ENV, **self.env, **{k: str(v) for k, v in extra.items()})
        return subprocess.run(argv, env=env, capture_output=True, text=True, cwd=cwd or self.root)

    def jc(self, argv, module=None, mode="main", code=None, patches=None, name="jebctl", cwd=None, **extra):
        spec = {"module": module or self.current_jebctl(), "argv": argv, "mode": mode, "name": name,
                "patches": dict({"running": True, "notify": True}, **(patches or {}))}
        if code:
            spec["code"] = code
        return self.run([PY, "-I", RUNNER, json.dumps(spec)], cwd=cwd, **extra)

    def snapshot(self, r, plists=True):
        out = section("rc", str(r.returncode)) + section("stdout", norm(r.stdout, self)) + section("stderr", norm(r.stderr, self))
        for label, p in (("release-state.json", os.path.join(self.state, "release-state.json")), ("update-status.json", os.path.join(self.state, "update-status.json")),
                         ("updater-state.json", os.path.join(self.state, "updater-state.json"))):
            t = read(p)
            if t is not None:
                out += section(label, pretty_json(t, self))
        t = read(os.path.join(self.state, "release.log"))
        if t:
            out += section("release.log", norm(t, self))
        t = read(self.stublog)
        if t:
            keep = [l for l in t.splitlines() if " prune-versions " not in l and " reload-agents" not in l]
            out += section("stub.log (argv of every native binary the run executed; detached prune-versions/reload-agents calls filtered)", norm("\n".join(keep), self))
        t = read(self.fake)
        if t:
            out += section("fake.log (claude, gh, launchctl calls)", norm(t, self))
        try:
            cur = os.readlink(os.path.join(self.jeb, "current"))
            out += section("~/.jeb/current", norm(cur, self))
        except OSError:
            pass
        if plists:
            for d, label in ((self.agents, "LaunchAgents"), (os.path.join(self.state, "launchd"), "JEB_HOME/launchd")):
                for p in sorted(glob.glob(os.path.join(d, "*.plist"))):
                    out += section(f"{label}/{os.path.basename(p)}", norm(plistlib.dumps(plistlib.load(open(p, "rb"))).decode(), self))
        return out


def plain_sb(name, mode="release"):
    """A sandbox that runs the repo's own desktop/jebctl (git-clone layout: CLONE = the repo)."""
    sb = SB(name)
    sb.mode(mode)
    return sb


def bundle_sb(name, **kw):
    sb = SB(name)
    sb.install_bundle(kw.pop("tag", "v1.4.0"), **kw)
    return sb


# ======================================================================================================================
# usage texts
def usage():
    sb = plain_sb("usage")
    repo_jc = os.path.join(DESK, "jebctl")
    write("runtime/usage/jebctl-help.txt", sb.snapshot(sb.jc(["--help"], module=repo_jc), plists=False))
    write("runtime/usage/jebctl-perf-bad-args.txt", sb.snapshot(sb.jc(["perf", "--days"], module=repo_jc), plists=False))
    write("runtime/usage/jebctl-install-bad-mode.txt", sb.snapshot(sb.jc(["install", "--mode", "bogus", "--dry-run"], module=repo_jc), plists=False))
    write("runtime/usage/jebctl-no-agents-wrong-command.txt", sb.snapshot(sb.jc(["status", "--no-agents"], module=repo_jc), plists=False))
    write("runtime/usage/jebctl-release-from-bundle.txt", sb.snapshot(bundle_sb("usage-bundle").jc(["release", "--dry-run"]), plists=False))
    write("runtime/usage/install-bad-flag.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(ROOT, "install"), "--bogus"]), plists=False))
    write("runtime/usage/uninstall-bad-flag.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(ROOT, "uninstall"), "--bogus"]), plists=False))
    write("runtime/usage/updater-help.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(DESK, "updater.py"), "--help"]), plists=False))
    write("runtime/usage/watchdog-help.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(DESK, "watchdog.py"), "--help"]), plists=False))
    rel = os.path.join(ROOT, "release")
    # no `./release` without a command: that is `release auto`, a real release (it unlocks the owner's signing key via git config)
    write("release/usage/release-bad-command.txt", sb.snapshot(sb.run([PY, "-I", rel, "bogus"]), plists=False))
    write("release/usage/release-bundle-bad-args.txt", sb.snapshot(sb.run([PY, "-I", rel, "bundle", "--tag", "1.2"]), plists=False))
    write("release/usage/release-bundle-no-app.txt", sb.snapshot(sb.run([PY, "-I", rel, "bundle", "--tag", "v9.9.9", "--out", os.path.join(sb.root, "out"), "--app", os.path.join(sb.root, "nope")]), plists=False))
    write("release/usage/release-smoke-bad-tag.txt", sb.snapshot(sb.run([PY, "-I", rel, "smoke", "1.2.3", "--dry-run"]), plists=False))
    write("release/usage/release-smoke-too-old.txt", sb.snapshot(sb.run([PY, "-I", rel, "smoke", "v1.4.0", "--dry-run"]), plists=False))


# ======================================================================================================================
# LaunchAgent plists
def plists():
    sb = bundle_sb("plists-bundle")
    write("runtime/plists/bundle-release.txt", sb.snapshot(sb.jc(["plists"])))
    repo_jc = os.path.join(DESK, "jebctl")
    for m in ("dev", "release"):
        sb = plain_sb("plists-clone-" + m, m)
        write(f"runtime/plists/clone-{m}.txt", sb.snapshot(sb.jc(["plists"], module=repo_jc)))


# ======================================================================================================================
# status, perf, doctor
TELEMETRY_HEADER = "epoch,stamp,pid,dt,cpu,rss,fp,sessions,class\n"


def telemetry(sb, rows, day_offset=0):
    d = os.path.join(sb.state, "telemetry")
    os.makedirs(d, exist_ok=True)
    import time
    name = time.strftime("%Y-%m-%d", time.localtime(NOW - day_offset * 86400)) + ".csv"
    with open(os.path.join(d, name), "a") as f:
        if f.tell() == 0:
            f.write(TELEMETRY_HEADER)
        for epoch, stamp, cpu, rss, fp, cls in rows:
            f.write(f"{epoch},{stamp},777,1.0,{cpu},{rss},{fp},2,{cls}\n")


def status_fixtures(sb):
    telemetry(sb, [(NOW - 600 + i * 30, "20260527-190000", 0.3 + 0.1 * (i % 3), 40 + i, 80 + i, "calm") for i in range(10)]
                  + [(NOW - 300 + i * 30, "20260527-190000", 5.0 + i, 70 + i, "", "passing") for i in range(5)]
                  + [(NOW - 5000, "20260526-120000", 0.05, 30, 50, "covered")])
    telemetry(sb, [(NOW - 86400 - 100 + i * 10, "20260526-120000", 9.0, 100, 200, "calm") for i in range(4)], day_offset=1)
    telemetry(sb, [(NOW - 5 * 86400, "20260522-120000", 1.0, 10, 10, "calm")], day_offset=5)
    json.dump({"last": {"result": "ok", "stamp": "20260527-190000", "at": NOW - 7200, "why": "smoke and start passed"}, "rejected": ["20260520-010101", "20260521-020202"]},
              open(os.path.join(sb.state, "updater-state.json"), "w"))
    for v in ("20260527-190000.app", "20260520-010101.app", "notes.txt"):
        os.makedirs(os.path.join(sb.state, "versions", v), exist_ok=True)


def status():
    sb = bundle_sb("status-fresh")
    write("runtime/status/bundle-fresh.txt", sb.snapshot(sb.jc(["status"]), plists=False))
    sb = bundle_sb("status-full")
    status_fixtures(sb)
    open(os.path.join(sb.state, "updates-paused"), "w").close()
    open(os.path.join(sb.state, "quit"), "w").close()
    rs = {"failed": ["v1.5.0", "v1.5.1"], "checked": NOW - 3600, "last": {"at": NOW - 3600, "tag": "v1.5.1", "result": "gates-rejected", "app": "prebuilt"},
          "layout": "bundle", "installed": [{"tag": "v1.4.0", "stamp": None, "at": 1}], "bridge_reset": 1}
    sb.save_rs(rs)
    os.makedirs(sb.agents, exist_ok=True)
    open(os.path.join(sb.agents, "com.jeb.desktop.plist"), "w").write("<plist/>")
    write("runtime/status/bundle-full.txt", sb.snapshot(sb.jc(["status"]), plists=False))
    write("runtime/status/perf-default.txt", sb.snapshot(sb.jc(["perf"]), plists=False))
    write("runtime/status/perf-days-2.txt", sb.snapshot(sb.jc(["perf", "--days", "2"]), plists=False))
    write("runtime/status/perf-days-7-stamp.txt", sb.snapshot(sb.jc(["perf", "--days", "7", "--stamp", "20260526-120000"]), plists=False))
    write("runtime/status/perf-stamp-none.txt", sb.snapshot(sb.jc(["perf", "--stamp", "nope"]), plists=False))
    write("runtime/status/pause-updates.txt", sb.snapshot(sb.jc(["pause-updates"]), plists=False))
    write("runtime/status/resume-updates.txt", sb.snapshot(sb.jc(["resume-updates"]), plists=False))
    repo_jc = os.path.join(DESK, "jebctl")
    for m in ("dev", "release"):
        sb = plain_sb("status-clone-" + m, m)
        write(f"runtime/status/clone-{m}.txt", sb.snapshot(sb.jc(["status"], module=repo_jc), plists=False))
    # doctor
    sb = bundle_sb("doctor-bundle")
    write("runtime/doctor/bundle-no-app.txt", sb.snapshot(sb.jc(["doctor"]), plists=False))
    sb = bundle_sb("doctor-bundle-agents")
    sb.jc(["plists"])
    for p in glob.glob(os.path.join(sb.state, "launchd", "*.plist")):
        shutil.copy(p, sb.agents)
    app = os.path.join(sb.home, "Applications", "JebDesktop.app", "Contents", "MacOS")
    os.makedirs(app)
    shutil.copy(STUB, os.path.join(app, "JebDesktop"))
    status_fixtures(sb)
    write("runtime/doctor/bundle-with-app-and-agents.txt", sb.snapshot(sb.jc(["doctor"]), plists=False))
    sb = bundle_sb("doctor-bundle-nopin", pin=None)
    os.unlink(os.path.join(sb.rel, "latest"))
    write("runtime/doctor/bundle-no-signers-no-release.txt", sb.snapshot(sb.jc(["doctor"]), plists=False))
    sb = bundle_sb("doctor-bundle-paused")
    open(os.path.join(sb.state, "updates-paused"), "w").close()
    sb.save_rs({"failed": ["v1.5.0"], "checked": NOW - 100, "last": {"at": NOW - 100, "tag": "v1.5.0", "result": "rejected", "app": "prebuilt"}, "layout": "bundle",
                "installed": [{"tag": "v1.4.0", "stamp": None, "at": 1}]})
    write("runtime/doctor/bundle-paused-failed.txt", sb.snapshot(sb.jc(["doctor"]), plists=False))
    for m in ("dev", "release"):
        sb = plain_sb("doctor-clone-" + m, m)
        write(f"runtime/doctor/clone-{m}.txt", sb.snapshot(sb.jc(["doctor"], module=repo_jc), plists=False))


# ======================================================================================================================
# follow / rollback / update on an installed schema 1 bundle with schema 2 releases (the native apply is the stub)
def follow():
    def case(name, sb, opts=(), **env):
        write(f"runtime/follow/{name}.txt", sb.snapshot(sb.jc(["follow"] + list(opts), **env)))

    case("up-to-date", bundle_sb("f-current"))
    sb = bundle_sb("f-ok"); sb.release("v1.5.0"); case("ok", sb)
    sb = bundle_sb("f-ok-quick"); sb.release("v1.5.0"); case("ok-quick", sb, ["--quick"])
    sb = bundle_sb("f-gates"); sb.release("v1.5.0"); case("gates-rejected", sb, JEB_STUB_RC=2)
    sb = bundle_sb("f-rolled"); sb.release("v1.5.0"); case("rolled-back", sb, JEB_STUB_RC=3)
    sb = bundle_sb("f-error"); sb.release("v1.5.0"); case("apply-error", sb, JEB_STUB_RC=7)
    sb = bundle_sb("f-gates-only"); sb.release("v1.5.0"); case("gates-only-pass", sb, ["--gates-only"])
    sb = bundle_sb("f-gates-only-fail"); sb.release("v1.5.0"); case("gates-only-fail", sb, ["--gates-only"], JEB_STUB_RC=2)
    sb = bundle_sb("f-net"); os.unlink(os.path.join(sb.rel, "latest")); case("network-error", sb)
    sb = bundle_sb("f-net-dl"); sb.release("v1.5.0"); shutil.rmtree(os.path.join(sb.rel, "download")); case("download-missing", sb)
    sb = bundle_sb("f-sig"); sb.release("v1.5.0", key="other"); case("signature-rejected", sb)
    sb = bundle_sb("f-nopin", pin=None); sb.release("v1.5.0"); case("no-pinned-signers", sb)
    sb = bundle_sb("f-adopt", pin=OLD, signers_from="v1.3.0"); sb.release("v1.5.0"); case("adopt-signers-then-ok", sb)
    sb = bundle_sb("f-adopt-same", pin=NEW3, signers_from="v1.4.0"); sb.release("v1.5.0"); case("adopt-signers-already-match", sb)
    sb = bundle_sb("f-adopt-bad", signers="# nothing usable\n", pin=OLD, signers_from="v1.3.0"); sb.release("v1.5.0"); case("adopt-signers-unusable", sb)
    for flaw in ("sha", "size", "content", "arch", "json"):
        sb = bundle_sb("f-" + flaw); sb.release("v1.5.0", flaw=flaw); case("flaw-" + flaw, sb)
    sb = bundle_sb("f-replay"); sb.release("v1.5.0", manifest_tag="v1.4.9"); case("flaw-replayed-manifest", sb)
    sb = bundle_sb("f-paused"); open(os.path.join(sb.state, "updates-paused"), "w").close(); sb.release("v1.5.0"); case("paused", sb)
    sb = bundle_sb("f-dev"); sb.mode("dev"); sb.release("v1.5.0"); case("not-release-mode", sb)
    sb = bundle_sb("f-dry"); sb.release("v1.5.0"); case("dry-run", sb, ["--dry-run"])
    case("dry-run-current", bundle_sb("f-dry-cur"), ["--dry-run"])
    sb = bundle_sb("f-noagents"); sb.release("v1.5.0"); case("ok-no-agents", sb, ["--no-agents"])
    # a failed tag stays skipped; the feed supplies the older candidate
    sb = bundle_sb("f-skip"); sb.release("v1.5.0"); sb.release("v1.6.0", key="other")
    rs = {"failed": ["v1.6.0"], "failed_why": {"v1.6.0": {"why": "gates", "pin": "x"}}, "checked": None, "last": None, "layout": "bundle",
          "installed": [{"tag": "v1.4.0", "stamp": None, "at": 1}], "bridge_reset": 1}
    sb.save_rs(rs)
    open(os.path.join(sb.rel + ".atom"), "w").write('<feed><entry><link href="https://x/releases/tag/v1.6.0"/></entry><entry><link href="https://x/releases/tag/v1.5.0"/></entry><entry><link href="https://x/releases/tag/v1.4.0"/></entry></feed>')
    case("failed-skipped-feed-fallback", sb)
    # straggler: rejected under the old code without a recorded reason (bridge_reset absent) gets another look
    sb = bundle_sb("f-straggler"); sb.release("v1.5.0")
    sb.save_rs({"failed": ["v1.5.0"], "checked": None, "last": None, "layout": "bundle", "installed": [{"tag": "v1.4.0", "stamp": None, "at": 1}]})
    case("straggler-reset", sb)
    # a signature rejection under a different pin gets another look once the pin changes
    sb = bundle_sb("f-repin"); sb.release("v1.5.0")
    sb.save_rs({"failed": ["v1.5.0"], "failed_why": {"v1.5.0": {"why": "signature", "pin": "0" * 64}}, "checked": None, "last": None, "layout": "bundle",
                "installed": [{"tag": "v1.4.0", "stamp": None, "at": 1}], "bridge_reset": 1})
    case("signature-retry-after-repin", sb)
    # stale LaunchAgents (older command) are healed
    sb = bundle_sb("f-heal")
    sb.jc(["plists"])
    for p in glob.glob(os.path.join(sb.state, "launchd", "*.plist")):
        d = plistlib.load(open(p, "rb"))
        if d["Label"] in ("com.jeb.desktop.release", "com.jeb.desktop.watchdog"):
            d["ProgramArguments"] = [os.path.join(sb.jeb, "current", "python", "bin", "python3"), "-I", os.path.join(sb.jeb, "current", "desktop", "jebctl"), d["ProgramArguments"][-1]]
        plistlib.dump(d, open(os.path.join(sb.agents, os.path.basename(p)), "wb"))
    open(sb.stublog, "w").close()
    case("heal-plists", sb)
    # rollback (the Python rollback runs on the installed schema 1 bundle, before any handoff; the target is a published schema 2 release
    # whose native jebctl (the stub) gates and swaps)
    def installed(sb, *tags):
        rs = {"failed": [], "checked": None, "last": None, "layout": "bundle", "installed": [{"tag": t, "stamp": None, "at": i + 1} for i, t in enumerate(tags)], "bridge_reset": 1}
        sb.save_rs(rs)

    sb = bundle_sb("rb-floor", tag="v1.5.1", pin=NEW3); installed(sb, "v1.4.0", "v1.5.1")
    write("runtime/rollback/floor.txt", sb.snapshot(sb.jc(["rollback"])))
    sb = bundle_sb("rb-ok", tag="v1.5.1", pin=NEW3); sb.release("v1.5.0"); sb.latest("v1.5.1"); installed(sb, "v1.5.0", "v1.5.1")
    write("runtime/rollback/ok.txt", sb.snapshot(sb.jc(["rollback"])))
    sb = bundle_sb("rb-gates", tag="v1.5.1", pin=NEW3); sb.release("v1.5.0"); sb.latest("v1.5.1"); installed(sb, "v1.5.0", "v1.5.1")
    write("runtime/rollback/gates-rejected.txt", sb.snapshot(sb.jc(["rollback"], JEB_STUB_RC=2)))
    sb = bundle_sb("rb-dl", tag="v1.5.1", pin=NEW3); installed(sb, "v1.5.0", "v1.5.1")
    write("runtime/rollback/download-fails.txt", sb.snapshot(sb.jc(["rollback"])))
    sb = bundle_sb("rb-skip-failed", tag="v1.5.2", pin=NEW3); sb.release("v1.5.0"); sb.latest("v1.5.2"); installed(sb, "v1.5.0", "v1.5.1", "v1.5.2")
    rs = json.load(open(os.path.join(sb.state, "release-state.json"))); rs["failed"] = ["v1.5.1"]; sb.save_rs(rs)
    write("runtime/rollback/skips-failed-tag.txt", sb.snapshot(sb.jc(["rollback"])))
    sb = bundle_sb("rb-none"); installed(sb)
    write("runtime/rollback/nothing-recorded.txt", sb.snapshot(sb.jc(["rollback"])))
    sb = bundle_sb("rb-dry", tag="v1.5.1", pin=NEW3); sb.release("v1.5.0"); sb.latest("v1.5.1"); installed(sb, "v1.5.0", "v1.5.1")
    write("runtime/rollback/dry-run.txt", sb.snapshot(sb.jc(["rollback", "--dry-run"])))
    # update / retry
    sb = bundle_sb("u-dry")
    write("runtime/update/bundle-dry-run.txt", sb.snapshot(sb.jc(["update", "--dry-run"]), plists=False))
    open(os.path.join(sb.state, "updates-paused"), "w").close()
    write("runtime/update/bundle-paused.txt", sb.snapshot(sb.jc(["update"]), plists=False))
    sb = plain_sb("u-dev", "dev")
    write("runtime/update/clone-dev-dry-run.txt", sb.snapshot(sb.jc(["update", "--dry-run"], module=os.path.join(DESK, "jebctl")), plists=False))
    sb = bundle_sb("u-retry")
    sb.save_rs({"failed": ["v1.5.0", "v1.6.0"], "failed_why": {"v1.5.0": {"why": "gates", "pin": "x"}, "v1.6.0": {"why": "gates", "pin": "x"}}, "checked": None, "last": None,
                "layout": "bundle", "installed": [{"tag": "v1.4.0", "stamp": None, "at": 1}], "bridge_reset": 1})
    write("runtime/update/bundle-retry-update.txt", sb.snapshot(sb.jc(["retry-update"]), plists=False))


# ======================================================================================================================
# install / uninstall dry runs
def installs():
    # bundle layout: the repo's install/uninstall scripts inside an unpacked bundle at ~/.jeb/versions/<tag>
    sb = bundle_sb("i-bundle", scripts=True, pin=None)
    sb.save_rs({})
    v = os.path.join(sb.jeb, "versions", "v1.4.0")
    for flags, name in ((["--dry-run"], "bundle-dry-run"), (["--dry-run", "--verbose"], "bundle-dry-run-verbose"), (["--dry-run", "--no-agents", "--verbose"], "bundle-dry-run-no-agents"),
                        (["--dry-run", "--dev"], "bundle-dev-refused"), (["--dry-run", "--build-from-source"], "bundle-build-refused"), (["--dry-run", "--repin", "--add-path", "--verbose"], "bundle-dry-run-repin-add-path")):
        write(f"runtime/install/{name}.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(v, "install")] + flags), plists=False))
    write("runtime/install/jebctl-bundle-dry-run-verbose.txt", sb.snapshot(sb.jc(["install", "--dry-run", "--verbose", "--no-agents"]), plists=False))
    write("runtime/install/jebctl-bundle-mode-dev-refused.txt", sb.snapshot(sb.jc(["install", "--mode", "dev", "--dry-run"]), plists=False))
    # a bundle unpacked somewhere else is refused
    sb2 = SB("i-bundle-elsewhere")
    sb2.bundle_tree(os.path.join(sb2.root, "Downloads", "v1.4.0"), "v1.4.0", schema=1, scripts=True)
    write("runtime/install/bundle-wrong-location.txt", sb2.snapshot(sb2.run([PY, "-I", os.path.join(sb2.root, "Downloads", "v1.4.0", "install"), "--dry-run", "--verbose"]), plists=False))
    for flags, name in ((["--dry-run"], "bundle-dry-run"), (["--dry-run", "--verbose"], "bundle-dry-run-verbose"), (["--dry-run", "--purge", "--verbose"], "bundle-dry-run-purge"),
                        (["--dry-run", "--remove-files", "--purge-farm", "--verbose"], "bundle-dry-run-remove-files-purge-farm")):
        sb = bundle_sb("un-" + name, scripts=True)
        v = os.path.join(sb.jeb, "versions", "v1.4.0")
        os.makedirs(os.path.join(sb.home, ".claude", "plugins", "data"), exist_ok=True)
        open(os.path.join(sb.home, ".claude", "plugins", "data", "jeb_jeb-abc123.json"), "w").write("{}")
        write(f"runtime/uninstall/{name}.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(v, "uninstall")] + flags), plists=False))
    sb = bundle_sb("un-jebctl")
    write("runtime/uninstall/jebctl-bundle-dry-run-verbose.txt", sb.snapshot(sb.jc(["uninstall", "--dry-run", "--verbose"]), plists=False))
    write("runtime/uninstall/jebctl-bundle-dry-run-purge-verbose.txt", sb.snapshot(sb.jc(["uninstall", "--purge", "--dry-run", "--verbose"]), plists=False))
    # git-clone layout: a local clone of this repo (no tags, so no release verification touches the repo's real tags)
    clone = os.path.join(T, "clone")
    subprocess.run(["git", "clone", "-q", "--no-tags", "--no-hardlinks", ROOT, clone], check=True, capture_output=True)
    sb = plain_sb("i-clone-dev", "dev")
    write("runtime/install/clone-dev-dry-run.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(clone, "install"), "--dev", "--dry-run"]), plists=False))
    write("runtime/install/clone-dev-dry-run-verbose.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(clone, "install"), "--dev", "--dry-run", "--verbose"]), plists=False))
    sb = plain_sb("i-clone-release", "release")
    write("runtime/install/clone-release-dry-run-verbose.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(clone, "install"), "--dry-run", "--verbose"]), plists=False))
    write("runtime/install/clone-release-dry-run.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(clone, "install"), "--dry-run"]), plists=False))
    sb.write_pin(NEW3)
    write("runtime/install/clone-release-dry-run-pinned-no-tags.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(clone, "install"), "--dry-run", "--verbose"]), plists=False))
    sb = plain_sb("un-clone", "dev")
    write("runtime/uninstall/clone-dry-run-verbose.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(clone, "uninstall"), "--dry-run", "--verbose"]), plists=False))
    write("runtime/uninstall/clone-dry-run-remove-clone.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(clone, "uninstall"), "--dry-run", "--remove-clone", "--verbose"]), plists=False))
    # the clone has local changes
    open(os.path.join(clone, "README.md"), "a").write("\nlocal edit\n")
    write("runtime/install/clone-release-dirty.txt", sb.snapshot(sb.run([PY, "-I", os.path.join(clone, "install"), "--dry-run"]), plists=False))


# ======================================================================================================================
# watchdog (dry run, fake process list)
def watchdog():
    wd = os.path.join(DESK, "watchdog.py")

    def case(name, sb, argv):
        write(f"runtime/watchdog/{name}.txt", sb.snapshot(sb.jc(argv, module=wd, mode="main0", name="watchdog.py", patches={"running": False, "notify": False}), plists=False))

    sb = bundle_sb("wd-none")
    case("none-running-start", sb, ["--dry-run", "--no-recheck-wait", "--fake-procs", ""])
    sb = bundle_sb("wd-marker"); open(os.path.join(sb.state, "quit"), "w").close()
    case("none-running-quit-marker", sb, ["--dry-run", "--no-recheck-wait", "--fake-procs", ""])
    sb = bundle_sb("wd-one")
    exe = os.path.join(sb.home, "Applications", "JebDesktop.app", "Contents", "MacOS", "JebDesktop")
    os.makedirs(os.path.dirname(exe)); shutil.copy(STUB, exe)
    case("one-running", sb, ["--dry-run", "--no-recheck-wait", "--fake-procs", f"100:{NOW - 500}:{exe}"])
    sb = bundle_sb("wd-two")
    exe = os.path.join(sb.home, "Applications", "JebDesktop.app", "Contents", "MacOS", "JebDesktop")
    os.makedirs(os.path.dirname(exe)); shutil.copy(STUB, exe)
    case("two-running", sb, ["--dry-run", "--no-recheck-wait", "--fake-procs", f"100:{NOW - 500}:{exe},200:{NOW - 50}:{exe}"])
    sb = bundle_sb("wd-fresh")
    exe = os.path.join(sb.home, "Applications", "JebDesktop.app", "Contents", "MacOS", "JebDesktop")
    os.makedirs(os.path.dirname(exe)); shutil.copy(STUB, exe)
    os.makedirs(os.path.join(sb.state, "heartbeat"))
    open(os.path.join(sb.state, "heartbeat", "1"), "w").write('{"waiting": false, "stamp": "20260527-190000"}')    # pid 1 always exists (launchd)
    case("one-running-fresh-heartbeat", sb, ["--dry-run", "--no-recheck-wait", "--fake-procs", f"1:{NOW - 500}:{exe}"])
    sb = bundle_sb("wd-kick"); open(os.path.join(sb.state, "watchdog.kick"), "w").close()
    case("recent-kick-skipped", sb, ["--dry-run", "--no-recheck-wait", "--fake-procs", ""])


# ======================================================================================================================
# in-process probes of pure functions
PROBES = {
    "tag-order": """
tags = "v1.10.0 v1.2.0 v1.9.3 v2.0.0 v1.2.0-rc1 foo v1.2 v0.0.1 v01.2.3".split()
print(json.dumps({"tag_key": {t: jc.tag_key(t) for t in tags}, "sorted": sorted((t for t in tags if jc.tag_key(t)), key=jc.tag_key)}, indent=1))
""",
    "release-tags-canned": """
print(json.dumps({"release_tags": jc.release_tags(), "head_tags": jc.head_tags()}))
""",
    "failed-skip": """
cases = {
 "no-failed": {"failed": []},
 "plain-list": {"failed": ["v1.5.0", "v1.6.0"]},
 "gates-same-pin": {"failed": ["v1.5.0"], "failed_why": {"v1.5.0": {"why": "gates", "pin": jc.pin_hash()}}},
 "signature-same-pin": {"failed": ["v1.5.0"], "failed_why": {"v1.5.0": {"why": "signature", "pin": jc.pin_hash()}}},
 "signature-other-pin": {"failed": ["v1.5.0"], "failed_why": {"v1.5.0": {"why": "signature", "pin": "x"}}},
 "mixed": {"failed": ["v1.5.0", "v1.6.0", "v1.7.0"], "failed_why": {"v1.5.0": {"why": "signature", "pin": "x"}, "v1.6.0": {"why": "sha", "pin": "x"}, "v1.7.0": "junk"}},
}
out = {k: jc.failed_skip(v) for k, v in cases.items()}
rs = {"failed": []}
jc.mark_failed(rs, "v1.5.0", "gates"); jc.mark_failed(rs, "v1.5.0", "sha"); jc.mark_failed(rs, "v1.6.0", "signature")
out["mark_failed"] = rs
jc.clear_failed(rs, "v1.5.0"); jc.clear_failed(rs, "v9.9.9")
out["after_clear"] = rs
out["pin_hash_is_sha256_of_pin_text"] = jc.pin_hash() == __import__("hashlib").sha256(open(jc.SIGNERS, "rb").read()).hexdigest()
print(json.dumps(out, indent=1))
""",
    "signers-parse": """
K = spec["pub"]
lines = {
 "plain": f"jeb-release {K}",
 "ns-jeb": f'jeb-release namespaces="jeb-release" {K}',
 "ns-both": f'me@example.com namespaces="git,jeb-release" {K}',
 "ns-git-only": f'me@example.com namespaces="git" {K}',
 "other-option": f'me@example.com cert-authority namespaces="jeb-release" {K}',
 "valid-after": f'me@example.com namespaces="jeb-release",valid-after="20250101" {K}',
 "comment": "# a comment",
 "blank": "",
 "no-key": "jeb-release namespaces=\\"jeb-release\\"",
 "ecdsa": "me ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGQ",
 "sk": "me sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIA",
}
out = {"key_line": {n: jc.key_line(l) for n, l in lines.items()}}
texts = {
 "two-good": lines["ns-jeb"] + "\\n" + lines["ns-both"] + "\\n",
 "comment-and-good": "# c\\n\\n" + lines["ns-jeb"] + "\\n",
 "git-only": lines["ns-git-only"] + "\\n",
 "other-option": lines["other-option"] + "\\n",
 "plain-no-ns": lines["plain"] + "\\n",
 "empty": "",
 "only-comments": "# c\\n",
 "mixed-bad": lines["ns-jeb"] + "\\n" + lines["ns-git-only"] + "\\n",
}
out["parse_signers"] = {n: jc.parse_signers(t) for n, t in texts.items()}
print(json.dumps(out, indent=1))
""",
    "new-tags": """
out = {}
for cur, skip in (("v1.4.0", []), ("v1.4.0", ["v1.6.0"]), ("v1.6.0", []), (None, []), ("v1.4.0", ["v1.6.0", "v1.5.0"]), ("v1.5.0", ["v1.6.0"])):
    out[f"cur={cur} skip={','.join(skip) or '-'}"] = jc.new_tags(cur, skip)
print(json.dumps(out, indent=1))
""",
    "check-sandbox": """
out = {"status": jc.check_sandbox("status"), "install": jc.check_sandbox("install")}
jc.APP_DIR = "/Applications"
out["app-dir-outside"] = jc.check_sandbox("follow")
print(json.dumps(out, indent=1))
""",
    "constants": """
out = {k: getattr(jc, k) for k in ("ALL_LABELS", "INITIAL_VERSION", "MANIFEST_MAX", "ROLLBACK_FLOOR", "NOTE_GROUPS", "CPU_TARGETS", "RSS_TARGET", "FP_TARGET", "PATH") if hasattr(jc, k)}
out["TAG_RE"] = jc.TAG_RE.pattern
out["CC_RE"] = jc.CC_RE.pattern
out["labels_for"] = {m: jc.labels_for(m) for m in ("dev", "release")}
out["app_name"] = jc.app_name("v1.5.0") if hasattr(jc, "app_name") else None
print(json.dumps(out, indent=1, default=str))
""",
    "release-plan": """
out = {}
for name, log in spec["logs"].items():
    jc.git = lambda *a, _l=log, **kw: __import__("subprocess").CompletedProcess(a, 0, _l, "") if a[:1] == ("log",) else __import__("subprocess").CompletedProcess(a, 1, "", "")
    level, notes = jc.release_plan("v1.2.0")
    out[name] = {"level": level, "notes": notes}
print(json.dumps(out, indent=1))
""",
    "plugdirs": """
import importlib.machinery, importlib.util
l = importlib.machinery.SourceFileLoader("plugdirs", os.path.join(jc.CODE, "plugdirs.py"))
pd = importlib.util.module_from_spec(importlib.util.spec_from_loader("plugdirs", l)); l.exec_module(pd)
mod = os.path.join(spec["sb"], "home", ".jeb", "current", "mod")
out = {"plan": {}}
for v in (None, "", mod, "/x/other", f"/x/other:{mod}", f"{mod}:/x/other", mod + "/", "/x/a:/x/b"):
    for rm in (False, True):
        out["plan"][f"value={v!r} remove={rm}"] = pd.plan(v, mod, rm)
out["store_name"] = {p: pd.store_name(p) for p in ("jeb@jeb", "inline", "a@b@c")}
out["store_dir"] = pd.store_dir(); out["store_path"] = pd.store_path(); out["settings_path"] = pd.settings_path(); out["backup_dir"] = pd.backup_dir()
out["norm"] = {p: pd.norm(p) for p in ("~/x", "/a/b/../c", "rel")}
out["info"] = pd.info()
said = []
for value in (None, "/x/other", mod, f"/x/other:{mod}"):
    os.makedirs(os.path.dirname(pd.settings_path()), exist_ok=True)
    with open(pd.settings_path(), "w") as f:
        json.dump({"env": {"CLAUDE_CODE_PLUGIN_DIRS": value}} if value is not None else {}, f)
    for rm in (False, True):
        said.append(f"--- settings env value {value!r}, remove={rm}")
        act = pd.edit(mod, rm, True, said.append)
        said.append(f"=> {act}")
os.unlink(pd.settings_path())
said.append("--- no settings file, add")
said.append("=> " + str(pd.edit(mod, False, True, said.append)))
said.append("--- register dry")
said.append("=> " + str(pd.register(os.path.dirname(mod), True, said.append)))
said.append("--- register dry with an extra old entry")
said.append("=> " + str(pd.register(os.path.dirname(mod), True, said.append, ["/x/old"])))
said.append("--- sync dry")
said.append("=> " + str(pd.sync(True, said.append)))
said.append("--- unregister dry (keep farm)")
said.append("=> " + str(pd.unregister(False, True, said.append, os.path.dirname(mod))))
said.append("--- unregister dry (purge farm)")
said.append("=> " + str(pd.unregister(True, True, said.append, os.path.dirname(mod))))
out["edit_register_dry_transcript"] = said
print(json.dumps(out, indent=1))
""",
    "verify-manifest": """
out = {}
for name, (man, sig, tag) in spec["cases"].items():
    out[name] = jc.verify_manifest(man, sig, tag)
print(json.dumps(out, indent=1))
""",
    "updater-status": """
u = jc.load_updater()
u.set_home(jc.HOME)
u.STATUS_SOURCE, u.STATUS_FINAL = "release", False
u.status("checking GitHub")
a = json.load(open(os.path.join(jc.HOME, "update-status.json")))
u.status("downloading v1.5.0", "step 2", step=2, steps=5)
b = json.load(open(os.path.join(jc.HOME, "update-status.json")))
u.STATUS_FINAL = True
u.status("done", "updated to v1.5.0", result="updated")
c = json.load(open(os.path.join(jc.HOME, "update-status.json")))
mode = oct(os.stat(os.path.join(jc.HOME, "update-status.json")).st_mode & 0o777)
print(json.dumps({"phase1": a, "phase2": b, "final": c, "mode": mode, "load_state_empty": u.load_state(), "bundle_stamp_missing": u.bundle_stamp("/nonexistent")}, indent=1))
""",
    "jebhome": """
import importlib.machinery, importlib.util
l = importlib.machinery.SourceFileLoader("jebhome", os.path.join(jc.CODE, "jebhome.py"))
jh = importlib.util.module_from_spec(importlib.util.spec_from_loader("jebhome", l)); l.exec_module(jh)
out = {"release_base": {r: jh.release_base(r) for r in ("clevyr/jeb", "x/y")}}
os.environ.pop("JEB_RELEASE_BASE", None)
out["release_base_default"] = jh.release_base("clevyr/jeb")
os.environ["JEB_RELEASE_BASE"] = "file://" + os.path.join(spec["sb"], "rel")
out["paths"] = {k: getattr(jh, k)() for k in ("resolve", "old_path", "new_path", "jeb_dir", "versions_dir", "current_dir", "tools_dir") if hasattr(jh, k)}
out["find_claude"] = jh.find_claude()
out["read_bundle"] = {"current": jh.read_bundle(jh.current_dir()), "missing": jh.read_bundle("/nonexistent")}
out["macho_archs"] = {"stub": jh.macho_archs(spec["stub"]), "script": jh.macho_archs(os.path.join(jc.CODE, "jebctl")), "missing": jh.macho_archs("/nonexistent")}
errs = {}
base = jh.release_base("clevyr/jeb")
for name, fn in (("latest_tag", lambda: jh.latest_tag(base)), ("feed_tags", lambda: jh.feed_tags(base)), ("fetch-missing", lambda: jh.fetch(base + "/nope", os.path.join(spec["sb"], "dl"), limit=10)),
                 ("fetch-toobig", lambda: jh.fetch(base + "/latest", os.path.join(spec["sb"], "dl"), limit=2)), ("fetch-ok", lambda: jh.fetch(base + "/latest", limit=100).decode())):
    try:
        errs[name] = fn()
    except jh.FetchError as e:
        errs[name] = {"FetchError": str(e), "status": getattr(e, "status", None)}
    except jh.TooBig as e:
        errs[name] = {"TooBig": str(e)}
out["fetch"] = errs
print(json.dumps(out, indent=1, default=str))
""",
}


def probes():
    sb = bundle_sb("probe")
    sb.release("v1.5.0"); sb.release("v1.6.0")
    open(os.path.join(sb.rel + ".atom"), "w").write('<feed><entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.6.0"/></entry>'
                                                    '<entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.5.0"/></entry><entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.4.0"/></entry>'
                                                    '<entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.6.0"/></entry><entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.2"/></entry></feed>')

    def probe(name, code, extra=None, patches=None, sandbox=None):
        s = sandbox or sb
        spec_extra = dict(extra or {})
        r = s.run([PY, "-I", RUNNER, json.dumps(dict({"module": s.current_jebctl(), "argv": [], "mode": "probe", "code": code, "patches": dict({"running": True, "notify": True}, **(patches or {})),
                                                        "sb": s.root, "pub": FAKE_KEY, "stub": STUB}, **spec_extra))])
        write(f"runtime/probes/{name}.txt", section("rc", str(r.returncode)) + section("stdout", norm(r.stdout, s)) + section("stderr", norm(r.stderr, s)))

    probe("tag-order", PROBES["tag-order"])
    probe("release-tags-canned", PROBES["release-tags-canned"], patches={"git": {"tag --list v*": [0, "v1.10.0\nv1.2.0\nfoo\nv1.9.3\nv2.0.0\nv1.2\n", ""], "tag --list v* --points-at HEAD": [0, "v1.9.3\nv1.2\n", ""]}})
    probe("failed-skip", PROBES["failed-skip"])
    probe("signers-parse", PROBES["signers-parse"])
    probe("new-tags", PROBES["new-tags"])
    probe("check-sandbox", PROBES["check-sandbox"])
    probe("constants", PROBES["constants"])
    probe("updater-status", PROBES["updater-status"])
    probe("jebhome", PROBES["jebhome"])
    probe("plugdirs", PROBES["plugdirs"], sandbox=bundle_sb("probe-plugdirs"))
    logs = {
        "feat-and-fix": "abc1234\0feat: add the still\0\x1edef5678\0fix(desktop): no more leaks\0\x1e",
        "fix-only": "abc1234\0fix: leak\0\x1e",
        "bang-major": "abc1234\0feat!: drop the old store\0\x1edef5678\0fix: tidy\0\x1e",
        "breaking-footer": "abc1234\0refactor: new layout\0Moves things.\n\nBREAKING CHANGE: the store moved\0\x1e",
        "breaking-change-dash": "abc1234\0chore: deps\0BREAKING-CHANGE: node 22\0\x1e",
        "nothing": "abc1234\0chore: deps\0\x1edef5678\0docs: readme\0\x1e9999999\0Update stuff\0\x1e",
        "perf-revert-scoped": "a1\0perf(scene): fewer layers\0\x1eb2\0revert: feat: add the still\0\x1ec3\0fix(mod)!: hooks\0body\0\x1ed4\0feat(desktop): night sky\0\x1e",
        "empty": "",
        "odd-shapes": "a1\0feat:no space\0\x1eb2\0FEAT: upper\0\x1ec3\0feat (x): spaced scope\0\x1ed4\0feat: \0\x1e",
    }
    probe("release-plan", PROBES["release-plan"], extra={"logs": logs})
    # verify_manifest outcomes on real signed files
    vs = bundle_sb("probe-verify", pin=NEW3)
    good = vs.release("v1.5.0")
    other = vs.release("v1.5.1", key="other")
    replay = vs.release("v1.5.2", manifest_tag="v1.5.0")
    badjson = vs.release("v1.5.3", flaw="json")
    cases = {"good": [good[0], good[1], "v1.5.0"], "unknown-signer": [other[0], other[1], "v1.5.1"], "replayed-tag": [replay[0], replay[1], "v1.5.2"],
             "invalid-json": [badjson[0], badjson[1], "v1.5.3"], "wrong-sig-for-manifest": [good[0], other[1], "v1.5.0"], "missing-sig": [good[0], good[1] + ".nope", "v1.5.0"]}
    probe("verify-manifest", PROBES["verify-manifest"], extra={"cases": cases}, sandbox=vs)
    vs2 = bundle_sb("probe-verify-nopin", pin=None)
    g = vs2.release("v1.5.0")
    probe("verify-manifest-no-pin", PROBES["verify-manifest"], extra={"cases": {"good-but-no-pin": [g[0], g[1], "v1.5.0"]}}, sandbox=vs2)


# ======================================================================================================================
# ./release: version bump and notes (jebctl release --dry-run in a throwaway repo), constants, smoke --dry-run, bundle
def git_env(home):
    return dict(BASE_ENV, HOME=home, PATH=f"{T}/bin:/usr/bin:/bin", GIT_AUTHOR_NAME="Golden", GIT_AUTHOR_EMAIL="golden@example.com", GIT_COMMITTER_NAME="Golden",
                GIT_COMMITTER_EMAIL="golden@example.com", GIT_AUTHOR_DATE="2026-05-01T12:00:00Z", GIT_COMMITTER_DATE="2026-05-01T12:00:00Z", GIT_CONFIG_NOSYSTEM="1")


def make_repo(name, commits, tag_at=None, signingkey=True, branch="main"):
    """A throwaway clone: desktop/jebctl & co. live in it (gitignored, so the tree stays clean and the commit ids depend only on the fixtures)."""
    d = os.path.join(T, "repos", name)
    os.makedirs(os.path.join(d, "desktop", "cli"))
    os.makedirs(os.path.join(d, "mod", ".claude-plugin"))
    env = git_env(os.path.join(T, "repos", "home"))
    os.makedirs(env["HOME"], exist_ok=True)

    def g(*a):
        return subprocess.run(["git", "-C", d] + list(a), env=env, capture_output=True, text=True, check=True)
    g("init", "-q", "-b", branch)
    g("config", "commit.gpgsign", "false")
    if signingkey:
        g("config", "user.signingkey", "~/.ssh/jeb-release.pub")
    for f in PYFILES:
        shutil.copy(os.path.join(DESK, f), os.path.join(d, "desktop", f))
    open(os.path.join(d, ".gitignore"), "w").write("desktop/jebctl\ndesktop/*.py\n__pycache__/\n")
    open(os.path.join(d, "desktop", "release-signers"), "w").write(f'jeb-release namespaces="jeb-release" {FAKE_KEY}\n')
    open(os.path.join(d, "desktop", "cli", "main.swift"), "w").write('let signerLines = [\n    "jeb-release namespaces=\\"jeb-release\\" ' + FAKE_KEY + '",\n]\n')
    json.dump({"name": "jeb", "version": "1.2.0"}, open(os.path.join(d, "mod", ".claude-plugin", "plugin.json"), "w"))
    g("add", "-A")
    g("commit", "-q", "-m", "chore: fixtures")
    for i, (subject, body) in enumerate(commits):
        if tag_at == i:
            g("tag", "v1.2.0")
        open(os.path.join(d, f"f{i}.txt"), "w").write(subject + "\n")
        g("add", "-A")
        g("commit", "-q", "-m", subject + (("\n\n" + body) if body else ""))
    if tag_at == len(commits):
        g("tag", "v1.2.0")
    return d, env


def release_steps():
    def case(name, repo, env, args):
        spec = {"module": os.path.join(repo, "desktop", "jebctl"), "argv": ["release", "--dry-run", "--parity"] + args, "mode": "main", "name": "jebctl", "patches": {"running": True}}
        sb_env = dict(env, JEB_HOME=os.path.join(T, "repos", "state-" + name), JEB_APP_DIR=os.path.join(T, "repos", "apps"), JEB_LAUNCHAGENTS=os.path.join(T, "repos", "agents"), JEB_NO_LAUNCHCTL="1")
        os.makedirs(sb_env["JEB_HOME"], exist_ok=True)
        open(os.path.join(sb_env["JEB_HOME"], "install-mode"), "w").write("dev\n")
        r = subprocess.run([PY, "-I", RUNNER, json.dumps(spec)], env=sb_env, capture_output=True, text=True, cwd=repo)
        write(f"release/steps/{name}.txt", section("rc", str(r.returncode)) + section("stdout", norm(r.stdout)) + section("stderr", norm(r.stderr)))

    feat_fix = [("feat: add the still", ""), ("fix(desktop): no more leaks", ""), ("docs: readme", ""), ("Update stuff", "")]
    d, env = make_repo("feat-fix", feat_fix, tag_at=0)
    case("auto-minor", d, env, [])
    case("forced-patch", d, env, ["--bump", "patch"])
    case("forced-major", d, env, ["--bump", "major"])
    case("bad-bump", d, env, ["--bump", "bogus"])
    case("bad-bump-missing", d, env, ["--bump"])
    d, env = make_repo("fix-only", [("fix: leak", "")], tag_at=0)
    case("auto-patch", d, env, [])
    d, env = make_repo("bang", [("feat!: drop the old store", ""), ("fix: tidy", "")], tag_at=0)
    case("auto-major-bang", d, env, [])
    d, env = make_repo("footer", [("refactor: new layout", "Moves things.\n\nBREAKING CHANGE: the store moved")], tag_at=0)
    case("auto-major-footer", d, env, [])
    d, env = make_repo("nothing", [("chore: deps", ""), ("docs: readme", "")], tag_at=0)
    case("nothing-to-release", d, env, [])
    case("nothing-forced-patch", d, env, ["--bump", "patch"])
    d, env = make_repo("mixed", [("perf(scene): fewer layers", ""), ("revert: feat: add the still", ""), ("fix(mod)!: hooks", "body"), ("feat(desktop): night sky", ""), ("chore(release): v1.2.1", "")], tag_at=0)
    case("mixed-groups", d, env, [])
    d, env = make_repo("no-tags", [("feat: first", "")])
    case("first-release", d, env, [])
    case("first-release-forced-minor", d, env, ["--bump", "minor"])
    d, env = make_repo("head-tagged", [("feat: x", "")], tag_at=1)
    case("head-already-tagged", d, env, [])
    d, env = make_repo("no-key", [("feat: x", "")], tag_at=0, signingkey=False)
    case("no-signing-key", d, env, [])
    d, env = make_repo("branch", [("feat: x", "")], tag_at=0, branch="work")
    case("wrong-branch", d, env, [])
    d, env = make_repo("dirty", [("feat: x", "")], tag_at=0)
    open(os.path.join(d, "f0.txt"), "a").write("dirty\n")
    case("dirty-tree", d, env, [])
    d, env = make_repo("signer-mismatch", [("feat: x", "")], tag_at=0)
    open(os.path.join(d, "desktop", "release-signers"), "w").write(f'other namespaces="jeb-release" {FAKE_KEY}\n')
    subprocess.run(["git", "-C", d, "commit", "-qam", "chore: change the signers"], env=env, check=True, capture_output=True)
    case("signer-constant-mismatch", d, env, [])


def release_tool():
    rel = os.path.join(ROOT, "release")
    sb = plain_sb("release-tool")
    code = """
out = {k: getattr(jc, k) for k in ("PBS_TAG", "PBS_PY", "PBS", "TREE", "PRUNE", "REPO", "SMOKE_MIN", "SMOKE_TAG_RE") if hasattr(jc, k)}
out["PBS_CACHE"] = jc.PBS_CACHE
out["local_imports"] = jc.local_imports()
out["rosetta_available_on_capture_host"] = jc.rosetta()
out["host_arch"] = jc.host_arch()
print(json.dumps(out, indent=1, default=str))
"""
    r = sb.run([PY, "-I", RUNNER, json.dumps({"module": rel, "argv": [], "mode": "probe", "code": code, "name": "release", "modname": "jebrelease"})])
    write("release/tool/constants.txt", section("rc", str(r.returncode)) + section("stdout", norm(r.stdout, sb)) + section("stderr", norm(r.stderr, sb)))
    write("release/tool/smoke-dry-run.txt", sb.snapshot(sb.run([PY, "-I", rel, "smoke", "--dry-run"]), plists=False))
    write("release/tool/smoke-dry-run-tag.txt", sb.snapshot(sb.run([PY, "-I", rel, "smoke", "v1.5.0", "--dry-run"]), plists=False))
    nc = "jc.check_notices(); print('notices ok')\ntry:\n    jc.check_notices(root=spec['sb'])\nexcept SystemExit as e:\n    print('missing:', e)"
    write("release/tool/check-notices.txt", sb.snapshot(sb.run([PY, "-I", RUNNER, json.dumps({"module": rel, "argv": [], "mode": "probe", "name": "release", "modname": "jebrelease", "sb": sb.root, "code": nc})]), plists=False))
    # the bundles, offline: both python-build-standalone tarballs must already sit in ~/Library/Caches/jeb-release with the pinned hashes
    consts = json.loads(r.stdout) if r.returncode == 0 else {}
    pbs = consts.get("PBS", {})
    cache = os.path.join(REALHOME, "Library", "Caches", "jeb-release")
    have = all(os.path.isfile(os.path.join(cache, n)) and hashlib.sha256(open(os.path.join(cache, n), "rb").read()).hexdigest() == h for n, h in pbs.values()) if pbs else False
    if not have:
        SKIPPED.append("release/bundle: the python-build-standalone tarballs are not in ~/Library/Caches/jeb-release (no network in the capture)")
        return
    stage = os.path.join(sb.root, "stage")
    os.makedirs(stage)
    for n in ("JebDesktop", "detect", "png2raw", "jebctl"):
        shutil.copy(STUB, os.path.join(stage, n))
    subprocess.run(["codesign", "-s", "-", "-f", os.path.join(stage, "jebctl")], capture_output=True)
    signers = os.path.join(sb.root, "signers")
    open(signers, "w").write(ONLY_NEW)
    out = os.path.join(sb.root, "out")
    env = dict(BASE_ENV, HOME=REALHOME, PATH=f"{T}/bin:/usr/bin:/bin:/usr/sbin:/sbin", TMPDIR=sb.root)
    r = subprocess.run([PY, "-I", rel, "bundle", "--tag", "v9.9.9", "--out", out, "--ref", "HEAD", "--app", stage, "--key", KEYS["new"], "--signers", signers],
                       env=env, capture_output=True, text=True, cwd=sb.root)
    text = section("rc", str(r.returncode)) + section("stdout", norm(r.stdout, sb)) + section("stderr", norm(r.stderr, sb))
    man = os.path.join(out, "Jeb-v9.9.9-manifest.json")
    if os.path.isfile(man):
        m = json.load(open(man))
        m["created"] = "$CREATED"
        for b in list(m.get("bundles", {}).values()) + [m.get("jebctl", {})]:
            if "size" in b: b["size"] = "$SIZE"
        text += section("manifest (created/size/sha256/commit normalized)", norm(json.dumps(m, indent=1, sort_keys=True), sb))
        text += section("files made", norm("\n".join(sorted(os.listdir(out))), sb))
    for arch in ("arm64", "x86_64"):
        zp = os.path.join(out, f"Jeb-v9.9.9-macos-{arch}.zip")
        if not os.path.isfile(zp):
            continue
        ex = os.path.join(sb.root, "unz-" + arch)
        subprocess.run(["ditto", "-x", "-k", zp, ex], check=True)
        names = []
        for dp, dn, fn in os.walk(ex):
            for n in fn:
                names.append(os.path.relpath(os.path.join(dp, n), ex))
        names.sort()
        py = [n for n in names if n.startswith("python/")]
        rest = [n for n in names if not n.startswith("python/")]
        text += section(f"{arch} bundle.json", pretty_json(open(os.path.join(ex, "bundle.json")).read(), sb))
        text += section(f"{arch}: repo files in the bundle (git archive HEAD of TREE, plus app/, desktop/bin/jebctl, bundle.json; tied to $HEAD)", "\n".join(rest))
        text += section(f"{arch}: python/ after PRUNE: {len(py)} files; top-level folders and lib/python3.*/ entries",
                        "\n".join(sorted({n.split("/")[1] for n in py})) + "\n--\n" + "\n".join(sorted({"/".join(n.split("/")[:4]) for n in py if n.startswith("python/lib/python3.")})))
        text += section(f"{arch}: PRUNE globs present under python/?", "\n".join(f"{pat}: {'present' if glob.glob(os.path.join(ex, 'python', pat)) else 'absent'}" for pat in consts.get("PRUNE", [])))
    write("release/bundle/v9.9.9.txt", text)


# ======================================================================================================================
# src/tools: parity.py gen, fake.py
def tools():
    tools_src = os.path.join(DESK, "src", "tools")
    p = os.path.join(T, "ptools", "src")
    os.makedirs(os.path.join(p, "tools"))
    os.makedirs(os.path.join(p, "fixtures"))
    shutil.copy(os.path.join(tools_src, "parity.py"), os.path.join(p, "tools", "parity.py"))
    # the tracked fixtures and band-out.txt were generated under America/New_York (parity.py's ms() uses time.mktime): the one TZ exception
    env = dict(BASE_ENV, TZ="America/New_York", PATH="/usr/bin:/bin", HOME=os.path.join(T, "ptools", "home"), JEB_MOD=os.path.join(ROOT, "mod"))
    r = subprocess.run([PY, "-I", os.path.join(p, "tools", "parity.py"), "gen"], env=env, capture_output=True, text=True, cwd=os.path.join(T, "ptools"))
    text = section("invocation", "JEB_MOD=$REPO/mod TZ=America/New_York /usr/bin/python3 -I <copy of desktop/src/tools/parity.py at <scratch>/src/tools/parity.py> gen\n(writes <scratch>/src/fixtures/<name>.store.json; no modcopy, so no band test)")
    text += section("rc", str(r.returncode)) + section("stdout", norm(r.stdout)) + section("stderr", norm(r.stderr))
    rows = []
    for f in sorted(os.listdir(os.path.join(p, "fixtures"))):
        mine = open(os.path.join(p, "fixtures", f), "rb").read()
        tracked = os.path.join(DESK, "src", "fixtures", f)
        same = os.path.isfile(tracked) and open(tracked, "rb").read() == mine
        rows.append(f"{f}  sha256 {hashlib.sha256(mine).hexdigest()}  {len(mine)} bytes  tracked desktop/src/fixtures/{f}: {'same bytes' if same else ('DIFFERENT' if os.path.isfile(tracked) else 'not tracked')}")
    text += section("stores written (every one must equal the tracked fixture byte for byte)", "\n".join(rows))
    write("release/parity/gen.txt", text)
    # with a modcopy: the band's scratch test
    os.makedirs(os.path.join(p, "modcopy", "tests"))
    r = subprocess.run([PY, "-I", os.path.join(p, "tools", "parity.py"), "gen"], env=env, capture_output=True, text=True, cwd=os.path.join(T, "ptools"))
    tsx = os.path.join(p, "modcopy", "tests", "zz-parity.test.tsx")
    body = open(tsx).read() if os.path.isfile(tsx) else ""
    text = section("rc", str(r.returncode)) + section("stdout", norm(r.stdout)) + section("stderr", norm(r.stderr))
    text += section("modcopy/tests/zz-parity.test.tsx", f"sha256 {hashlib.sha256(body.encode()).hexdigest()}  {len(body)} bytes  {body.count(chr(10))} lines")
    if len(body) <= 65536:
        text += section("zz-parity.test.tsx text", norm(body))
    write("release/parity/gen-with-modcopy.txt", text)
    if RENDER == "1":
        jb = os.path.join(DESK, "src", "JebDesktop")
        if os.path.isfile(jb):
            r = subprocess.run([PY, "-I", os.path.join(tools_src, "parity.py"), "compare", os.path.join(DESK, "src", "fixtures", "band-out.txt")], env=dict(env, JEB_BIN="JebDesktop"), capture_output=True, text=True, cwd=tools_src)
            write("release/parity/compare.txt", section("rc", str(r.returncode)) + section("stdout", norm(r.stdout)) + section("stderr", norm(r.stderr)))
        else:
            SKIPPED.append("release/parity/compare: --render asked but desktop/src/JebDesktop is not built")
    # fake.py: the scratch store writer, with the clock advancing only through its sleeps
    for mode in ("idle", "busy"):
        d = os.path.join(T, "fake-" + mode)
        os.makedirs(d)
        store = os.path.join(d, "store.json")
        spec = {"module": os.path.join(tools_src, "fake.py"), "argv": [store, "3", mode, "6"], "mode": "load", "name": "fake.py", "modname": "fakestore"}
        r = subprocess.run([PY, "-I", RUNNER, json.dumps(spec)], env=dict(BASE_ENV, PATH="/usr/bin:/bin", HOME=d), capture_output=True, text=True, cwd=d)
        text = section("invocation", f"fake.py <store> 3 {mode} 6  (clock pinned at {NOW}, advancing 0.5 s per sleep; random.seed(7); the module's own random.Random(7))")
        text += section("rc", str(r.returncode)) + section("stdout", norm(r.stdout)) + section("stderr", norm(r.stderr))
        if os.path.isfile(store):
            text += section("final store.json", pretty_json(open(store).read()))
        if os.path.isfile(store + ".writes"):
            text += section("store.json.writes (ms wall time of each write)", open(store + ".writes").read())
        write(f"release/tools/fake-{mode}.txt", text)


def main():
    for d in ("runtime", "release"):
        shutil.rmtree(os.path.join(OUT, d), ignore_errors=True)
    usage(); plists(); status(); follow(); installs(); watchdog(); probes(); release_steps(); release_tool(); tools()
    for k in sorted(COUNTS):
        print(f"  {k}: {COUNTS[k]}")
    for s in SKIPPED:
        print("  skipped: " + s)


main()
PYEOF

# ---- art: Pillow generators, exact bytes for the tracked outputs, decoded-frame hashes for the rest
cat > "$T/art.py" <<'PYEOF'
import hashlib, json, os, subprocess, sys
from PIL import Image, ImageSequence
import PIL

ROOT, T, OUT = sys.argv[1:4]
SRC = os.path.join(ROOT, "mod", "art", "src")
work = os.path.join(T, "art")
os.makedirs(work)
py = sys.executable
env = {"PATH": "/usr/bin:/bin", "HOME": work, "TZ": "America/Chicago", "LC_ALL": "C", "PYTHONHASHSEED": "0"}
ts = os.path.join(work, "pixel-art.ts")
b = subprocess.run([py, "-I", os.path.join(SRC, "build.py"), work, ts], env=env, capture_output=True, text=True, cwd=work)
logo_dir = os.path.join(work, "logo")
icon = os.path.join(work, "icon.png")
l = subprocess.run([py, "-I", os.path.join(SRC, "logo.py"), ts, logo_dir, icon], env=env, capture_output=True, text=True, cwd=work)


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


def norm(s):
    subs = {}
    for root, token in ((work, "$WORK"), (T, "$T"), (ROOT, "$REPO"), (os.path.expanduser("~"), "$REALHOME")):
        for q in (root, os.path.normpath(root), os.path.realpath(root)):
            subs.setdefault(q.rstrip("/"), token)
    for a, b in sorted(subs.items(), key=lambda kv: -len(kv[0])):     # every spelling of each root, longest first
        s = s.replace(a, b)
    return s


def section(title, body):
    body = body.rstrip("\n")
    return f"## {title}\n{body if body.strip() else '(empty)'}\n\n"


def write(rel, text):
    p = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(text if text.endswith("\n") else text + "\n")


exact = []
for made, tracked in ((ts, "mod/hooks/pixel-art.ts"), (os.path.join(logo_dir, "logo.svg"), "docs/logo.svg"), (os.path.join(logo_dir, "logo.png"), "docs/logo.png"), (icon, "mod/.claude-plugin/icon.png")):
    tp = os.path.join(ROOT, tracked)
    if not os.path.isfile(made):
        exact.append(f"{tracked}: NOT MADE"); continue
    same = os.path.isfile(tp) and open(tp, "rb").read() == open(made, "rb").read()
    exact.append(f"{tracked}: sha256 {sha(made)}  {os.path.getsize(made)} bytes  tracked file {'same bytes' if same else 'DIFFERENT'}")
text = section("interpreter", f"$ART_PY (Python {sys.version.split()[0]}, Pillow {PIL.__version__}); build.py <work> <work>/pixel-art.ts; logo.py <work>/pixel-art.ts <work>/logo <work>/icon.png")
text += section("build.py rc", str(b.returncode)) + section("build.py stdout", norm(b.stdout)) + section("build.py stderr", norm(b.stderr))
text += section("logo.py rc", str(l.returncode)) + section("logo.py stdout", norm(l.stdout)) + section("logo.py stderr", norm(l.stderr))
text += section("exact-byte outputs (the tracked file is the golden; this records that the generator still reproduces it)", "\n".join(exact))
write("art/generators.txt", text)

frames = {}
for sub in ("sheets", "gifs", "."):
    d = os.path.join(work, sub)
    for n in sorted(os.listdir(d)):
        p = os.path.join(d, n)
        if not n.endswith((".png", ".gif")) or not os.path.isfile(p):
            continue
        rel = n if sub == "." else f"{sub}/{n}"
        if sub == "." and n == "icon.png":
            continue
        im = Image.open(p)
        fr = []
        for f in ImageSequence.Iterator(im):
            rgba = f.convert("RGBA")
            fr.append({"ms": f.info.get("duration"), "sha256": hashlib.sha256(rgba.tobytes()).hexdigest()})
        frames[rel] = {"size": list(im.size), "format": im.format, "frames": fr, "loop": im.info.get("loop"), "file_sha256": sha(p), "file_bytes": os.path.getsize(p)}
write("art/decoded-frames.json", json.dumps(frames, indent=1, sort_keys=True))
print(f"  art: {len(frames)} images, {sum(len(v['frames']) for v in frames.values())} frames; " + "; ".join(e.split(':')[0] + ' ' + e.split('  ')[-1] for e in exact))
PYEOF

echo "capture into $OUT"
/usr/bin/python3 -I "$T/drive.py" "$ROOT" "$T" "$ARCH" "$OUT" "$RENDER" "$REALHOME" || { echo "drive.py failed" >&2; exit 1; }
if [ -x "$ART_PY" ] && "$ART_PY" -c "import PIL" 2>/dev/null; then
  rm -rf "$OUT/art"
  "$ART_PY" -I "$T/art.py" "$ROOT" "$T" "$OUT" || { echo "art.py failed" >&2; exit 1; }
  ART_DONE=1
else
  echo "  art: skipped (no Pillow interpreter at $ART_PY; set JEB_ART_PY)"
  ART_DONE=0
fi
if [ $CHECK = 1 ]; then
  EXCL="-x README.md -x parity"
  [ $ART_DONE = 1 ] || EXCL="$EXCL -x art"
  # shellcheck disable=SC2086
  if diff -r $EXCL "$GOLD" "$OUT"; then echo "check: goldens match"; else echo "check: goldens DIFFER" >&2; exit 1; fi
fi
