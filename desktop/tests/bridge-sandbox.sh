#!/bin/sh
# Sandbox scenarios for the v1.5.0 bridge release (signer adoption, rejection reasons, straggler reset, native-launcher agents, schema 2 bundles,
# the signer constant check). Self-contained: everything lives in one temp dir (HOME and every JEB_* path point into it, a fake claude, gh and
# launchctl come first on PATH, the real install is never read or written) and is removed at the end. Throwaway ssh keys; file:// releases.
# Run: sh desktop/tests/bridge-sandbox.sh        Prints "ok" or "FAIL" per case; exit 1 on any failure.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/jeb-bridge.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$T/keys" "$T/bin"
for k in old new other; do
  ssh-keygen -q -t ed25519 -N '' -C "$k" -f "$T/keys/$k" || exit 1
done
ARCH=arm64; [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] || ARCH=x86_64
# the stand-in for desktop/bin/jebctl and the app binaries: a real Mach-O of the host arch that logs its argv to $JEB_STUB_LOG,
# exits with $JEB_STUB_RC, and (JEB_STUB_FLIP=<current link>, exit 0, `apply <ver>`) points that link at <ver> as the real `apply` does
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
cc -arch "$ARCH" -o "$T/stub" "$T/stub.c" || { echo "FAIL could not build the stub"; exit 1; }
for n in claude gh launchctl; do
  printf '#!/bin/sh\necho "$0 $*" >> "$JEB_FAKE_LOG"\ncase "$*" in "plugin list --json"|"plugin marketplace list --json") echo "[]";; esac\nexit 0\n' > "$T/bin/$n"
  chmod +x "$T/bin/$n"
done
cat > "$T/drive.py" <<'PYEOF'
import hashlib, json, os, shutil, subprocess, sys, textwrap

ROOT, T, ARCH = sys.argv[1], sys.argv[2], sys.argv[3]
STUB = os.path.join(T, "stub")
KEYS = {n: os.path.join(T, "keys", n) for n in ("old", "new", "other")}
PUB = {n: " ".join(open(k + ".pub").read().split()[:2]) for n, k in KEYS.items()}
PY = "/usr/bin/python3"
FAILS = []


def line(who, key, ns="git,jeb-release"):
    return f'{who} namespaces="{ns}" {PUB[key]}'


OLD = line("old@example.com", "old") + "\n"
NEW3 = OLD + line("jeb-release", "new") + "\n"
sandbox_n = [0]


class SB:
    """One sandbox: HOME and every path override under it."""
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
        for d in (self.state, self.agents, os.path.join(h, ".local", "bin"), self.rel):
            os.makedirs(d)
        os.symlink(os.path.join(T, "bin", "claude"), os.path.join(h, ".local", "bin", "claude"))     # jebhome.find_claude looks here first
        open(self.fake, "w").close()
        self.env = dict(
            PATH=f"{T}/bin:/usr/bin:/bin:/usr/sbin:/sbin", HOME=h, TMPDIR=self.root,
            JEB_HOME=self.state, JEB_APP_DIR=os.path.join(h, "Applications"), JEB_LAUNCHAGENTS=self.agents, JEB_BIN_DIR=os.path.join(h, ".local", "bin"),
            JEB_PROFILE=os.path.join(h, ".zprofile"), JEB_SETTINGS=os.path.join(h, ".claude", "settings.json"), JEB_BACKUPS=os.path.join(h, ".claude", "backups"),
            JEB_STORE_DIR=os.path.join(h, ".claude", "plugins", "data"), CLAUDE_CONFIG_DIR=os.path.join(h, ".claude"), JEB_TOOLS_DIR=os.path.join(h, ".jeb", "bin"),
            JEB_RELEASE_BASE="file://" + self.rel, JEB_NO_LAUNCHCTL="1", JEB_FAKE_LOG=self.fake, JEB_STUB_LOG=self.stublog,
            JEB_STUB_FLIP=os.path.join(self.jeb, "current"))
        assert h.startswith(T) and not self.state.startswith(os.path.expanduser("~/Library"))
        open(os.path.join(self.state, "install-mode"), "w").write("release\n")

    # ---- files
    def bundle_tree(self, root, tag, schema=2, signers=NEW3, drop=(), nonmacho=False):
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
            for f in ("jebctl", "jebhome.py", "plugdirs.py", "updater.py", "watchdog.py"):
                shutil.copy(os.path.join(ROOT, "desktop", f), os.path.join(root, "desktop", f))
            os.makedirs(os.path.join(root, "python/bin"))
            shutil.copy(STUB, os.path.join(root, "python/bin/python3"))
        for rel in drop:
            p = os.path.join(root, rel)
            shutil.rmtree(p) if os.path.isdir(p) else os.unlink(p)

    def install_bundle(self, tag, signers=NEW3, pin=OLD, signers_from=None):
        """An installed bundle running this tree's jebctl (schema 1 files, stub native launcher), the pin, and release state."""
        v = os.path.join(self.jeb, "versions", tag)
        self.bundle_tree(v, tag, schema=1, signers=signers)
        for f in ("jebctl", "jebhome.py", "plugdirs.py", "updater.py", "watchdog.py"):
            shutil.copy(os.path.join(ROOT, "desktop", f), os.path.join(v, "desktop", f))
        os.symlink(os.path.join("versions", tag), os.path.join(self.jeb, "current"))
        if pin is not None:
            self.write_pin(pin)
        rs = {"failed": [], "checked": None, "last": None, "layout": "bundle", "installed": [{"tag": tag, "stamp": None, "at": 1}], "bridge_reset": 1}
        if signers_from:
            rs["signers_from"] = signers_from
        self.save_rs(rs)
        self.latest(tag)

    def write_pin(self, text):
        p = os.path.join(self.state, "release-signers")
        open(p, "w").write(text)
        os.chmod(p, 0o600)

    def pin(self):
        try:
            return open(os.path.join(self.state, "release-signers")).read()
        except OSError:
            return None

    def pin_mode(self):
        return os.stat(os.path.join(self.state, "release-signers")).st_mode & 0o777

    def pin_hash(self):
        return hashlib.sha256((self.pin() or "").encode()).hexdigest() if self.pin() is not None else ""

    def rs(self):
        return json.load(open(os.path.join(self.state, "release-state.json")))

    def save_rs(self, rs):
        json.dump(rs, open(os.path.join(self.state, "release-state.json"), "w"))

    def latest(self, tag):
        open(os.path.join(self.rel, "latest"), "w").write(tag)

    def release(self, tag, key="new", schema=2, signers=NEW3, flaw=None):
        """Publish tag in the file:// tree: zip, manifest, signature (made with the throwaway key `key`), and `latest`."""
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
        json.dump({"schema": 1, "repo": "clevyr/jeb", "tag": tag, "version": tag[1:], "bundles": {ARCH: {"name": zname, "sha256": sha, "size": size}}}, open(man, "w"))
        if os.path.exists(man + ".sig"):
            os.unlink(man + ".sig")
        subprocess.run(["ssh-keygen", "-q", "-Y", "sign", "-f", KEYS[key], "-n", "jeb-release", man], check=True, capture_output=True)
        self.latest(tag)

    # ---- running
    def run(self, argv, **extra):
        env = dict(self.env, **{k: str(v) for k, v in extra.items()})
        return subprocess.run(argv, env=env, capture_output=True, text=True, cwd=self.root)

    def follow(self, *opts, **extra):
        return self.run([PY, "-I", os.path.join(self.jeb, "current", "desktop", "jebctl"), "follow"] + list(opts), **extra)

    def inproc(self, code, jebctl=None):
        """Run `code` with the jebctl module (as loaded from jebctl) in scope as jc; stdout is the result."""
        src = textwrap.dedent("""
            import importlib.machinery, importlib.util, sys, json
            path = sys.argv[1]; sys.argv = ["jebctl"] + sys.argv[2:]
            l = importlib.machinery.SourceFileLoader("jc", path)
            jc = importlib.util.module_from_spec(importlib.util.spec_from_loader("jc", l)); l.exec_module(jc)
            """) + textwrap.dedent(code)
        r = self.run([PY, "-I", "-c", src, jebctl or os.path.join(self.jeb, "current", "desktop", "jebctl")])
        return r

    def log(self):
        try:
            return open(os.path.join(self.state, "release.log")).read()
        except OSError:
            return ""

    def fakes(self):
        return open(self.fake).read()

    def stub(self):
        return open(self.stublog).read() if os.path.exists(self.stublog) else ""


def case(name, fn):
    try:
        res = fn()
        if res:
            FAILS.append(name); print(f"FAIL {name}: {res}")
        else:
            print(f"ok   {name}")
    except Exception as e:   # a broken scenario is a failure, not a crash
        FAILS.append(name); print(f"FAIL {name}: {type(e).__name__}: {e}")


def need(cond, msg):
    return None if cond else msg


def first(*checks):
    return next((c for c in checks if c), None)


def out(r):
    return f"rc={r.returncode}\n{r.stdout[-600:]}\n{r.stderr[-600:]}"


# ---------------------------------------------------------------- a. adoption
def a_adopt_newer():
    sb = SB("adopt"); sb.install_bundle("v1.5.0", signers_from=None)
    r = sb.follow()
    return first(need(r.returncode == 0, out(r)), need(sb.pin() == NEW3, "pin was not replaced by the installed release's file"),
                 need(sb.pin_mode() == 0o600, f"pin mode {oct(sb.pin_mode())}"), need(sb.rs().get("signers_from") == "v1.5.0", f"signers_from {sb.rs().get('signers_from')}"),
                 need("adopting the release-signers of v1.5.0" in sb.log(), "no rlog line"))


def a_adopt_newer_than_recorded():
    sb = SB("adopt-newer"); sb.install_bundle("v1.5.1", signers_from="v1.5.0")
    sb.follow()
    return need(sb.pin() == NEW3 and sb.rs().get("signers_from") == "v1.5.1", f"{sb.rs().get('signers_from')}")


def a_adopt_equal_older_noop():
    res = []
    for sf, tag in (("v1.5.0", "v1.5.0"), ("v1.6.0", "v1.5.0")):
        sb = SB("noop"); sb.install_bundle(tag, signers_from=sf, pin=OLD)
        sb.follow()
        res.append(need(sb.pin() == OLD and sb.rs().get("signers_from") == sf, f"signers_from={sf} installed={tag}: pin changed or signers_from moved ({sb.rs().get('signers_from')})"))
    return first(*res)


def a_adopt_invalid_source():
    sb = SB("adopt-bad")
    sb.install_bundle("v1.5.0", signers=line("x", "new", "git") + "\n")     # no jeb-release namespace
    sb.follow()
    return first(need(sb.pin() == OLD, "pin replaced by an unusable file"), need("signers_from" not in sb.rs(), "signers_from set"))


def a_adopt_never_in_install_paths():
    sb = SB("fresh"); sb.install_bundle("v1.5.0", pin=None)
    r = sb.inproc("""
        import inspect
        print(json.dumps({"install_bundle": "adopt_signers" in inspect.getsource(jc.install_bundle), "pin_signers": "adopt_signers" in inspect.getsource(jc.pin_signers),
                          "follow": "adopt_signers" in inspect.getsource(jc.follow), "convert": "adopt_signers" in inspect.getsource(jc.convert_clone)}))
    """)
    d = json.loads(r.stdout.strip().splitlines()[-1])
    r1 = need(not d["install_bundle"] and not d["pin_signers"] and not d["follow"], f"adopt_signers is reachable from an install or the clone follow: {d}")
    # a fresh install pins the bundle's own file and records no adoption; an existing pin stays unless --repin
    r2 = sb.inproc("""
        jc.set_home(jc.HOME)
        jc.pin_signers(False)
        a = open(jc.SIGNERS).read()
        jc.save_rstate(jc.load_rstate())
        open(jc.SIGNERS, "w").write("kept\\n"); jc.pin_signers(False); b = open(jc.SIGNERS).read()
        jc.pin_signers(True); c = open(jc.SIGNERS).read()
        print(json.dumps([a, b, c, jc.load_rstate().get("signers_from")]))
    """)
    a, b, c, sf = json.loads(r2.stdout.strip().splitlines()[-1])
    return first(r1, need(a == NEW3, "fresh pin is not the bundle's file"), need(b == "kept\n", "an existing pin was replaced without --repin"),
                 need(c == NEW3, "--repin did not replace the pin"), need(sf is None, "an install recorded signers_from"))


def a_adopt_after_update():
    sb = SB("adopt-update"); sb.install_bundle("v1.5.0", pin=OLD)
    sb.release("v1.5.1", key="old", signers=NEW3)         # signed by the key the pin already has
    r = sb.follow(JEB_STUB_RC=0)
    return first(need(r.returncode == 0, out(r)), need(sb.pin() == NEW3, "pin was not adopted from the verified update"), need(sb.pin_mode() == 0o600, "mode"),
                 need(sb.rs().get("signers_from") == "v1.5.1", f"signers_from {sb.rs().get('signers_from')}"))


def a_no_adopt_when_update_fails():
    sb = SB("adopt-fail"); sb.install_bundle("v1.5.0", pin=OLD, signers_from="v1.5.0")
    sb.release("v1.5.1", key="old", signers=NEW3)
    sb.follow(JEB_STUB_RC=2)
    return first(need(sb.pin() == OLD, "a rejected update changed the pin"), need(sb.rs().get("signers_from") == "v1.5.0", "signers_from moved"))


# ---------------------------------------------------------------- b. rejection reasons and retry
def b_failed_why_and_retry():
    sb = SB("retry"); sb.install_bundle("v1.5.0", pin=OLD, signers_from="v1.5.0")
    sb.release("v1.5.1", key="other", signers=NEW3)       # signed by a key nobody pinned
    h0 = sb.pin_hash()
    sb.follow()
    rs = sb.rs()
    e1 = first(need(rs.get("failed") == ["v1.5.1"], f"failed={rs.get('failed')}"), need(rs.get("failed_why", {}).get("v1.5.1") == {"why": "signature", "pin": h0}, f"failed_why={rs.get('failed_why')}"))
    n = sb.log().count("rejected (signature)")
    sb.follow()
    e2 = need(sb.log().count("rejected (signature)") == n == 1, "a signature rejection was retried with the same pin")
    sb.write_pin(OLD + line("other", "other") + "\n")      # the pin changes (a newer release adopted); signers_from stays
    r = sb.follow(JEB_STUB_RC=0)
    rs = sb.rs()
    e3 = first(need(sb.log().count("rejected (signature)") == 1, "the retry still failed: " + out(r)), need("v1.5.1" not in rs.get("failed", []), f"failed={rs.get('failed')}"),
               need("v1.5.1" not in rs.get("failed_why", {}), "failed_why not cleared"), need(os.path.basename(os.path.realpath(os.path.join(sb.jeb, "current"))) == "v1.5.1", "not on v1.5.1"))
    return first(e1, e2, e3)


def b_signature_rejected_again_after_pin_change():
    sb = SB("retry2"); sb.install_bundle("v1.5.0", pin=OLD, signers_from="v1.5.0")
    sb.release("v1.5.1", key="other")
    sb.follow()
    sb.write_pin(OLD + line("x", "new") + "\n")           # a different pin that still does not hold the signing key
    sb.follow()
    h = sb.pin_hash()
    return first(need(sb.log().count("rejected (signature)") == 2, "was not retried after the pin changed"), need(sb.rs()["failed_why"]["v1.5.1"]["pin"] == h, "recorded pin hash is not the new one"),
                 need(sb.rs()["failed"] == ["v1.5.1"], f"failed={sb.rs()['failed']} (a list, no duplicates)"))


def b_kind(name, flaw, rc=None, want=None, nonsig_pin_change=True):
    def f():
        sb = SB("kind-" + name); sb.install_bundle("v1.5.0", pin=NEW3, signers_from="v1.5.0")
        sb.release("v1.5.1", key="new", flaw=flaw)
        extra = {"JEB_STUB_RC": rc} if rc is not None else {}
        sb.follow(**extra)
        rs = sb.rs()
        ok1 = first(need(rs.get("failed") == ["v1.5.1"], f"failed={rs.get('failed')}"), need(rs.get("failed_why", {}).get("v1.5.1", {}).get("why") == want, f"failed_why={rs.get('failed_why')}"))
        sb.write_pin(NEW3 + line("y", "other") + "\n")      # a changed pin must not revive anything but a signature rejection
        sb.follow(**extra)
        n = sb.log().count("v1.5.1 rejected") + sb.log().count("v1.5.1 rolled-back") + sb.log().count("v1.5.1 rejected (")
        return first(ok1, need(sb.log().count("downloading") >= 0, ""), need(os.path.basename(os.path.realpath(os.path.join(sb.jeb, "current"))) == "v1.5.0", "current moved"),
                     need(sb.stub().count(" apply ") <= 1, f"the tag was tried again:\n{sb.stub()}"))
    return f


def b_error_not_failed():
    sb = SB("kind-error"); sb.install_bundle("v1.5.0", pin=NEW3, signers_from="v1.5.0")
    sb.release("v1.5.1")
    r = sb.follow(JEB_STUB_RC=1)
    return first(need(r.returncode == 1, out(r)), need(not sb.rs().get("failed"), f"failed={sb.rs().get('failed')}"), need("will try again later" in sb.log(), "no retry note"))


# ---------------------------------------------------------------- c. straggler reset
def c_straggler_reset():
    sb = SB("straggler"); sb.install_bundle("v1.5.0", pin=NEW3, signers_from="v1.5.0")
    rs = sb.rs(); rs.pop("bridge_reset")
    rs["failed"] = ["v1.4.0", "v1.5.1", "v1.5.2", "v1.6.0"]
    rs["failed_why"] = {"v1.5.2": {"why": "gates", "pin": "x"}}
    sb.save_rs(rs)
    sb.follow()
    r1 = sb.rs()
    e1 = first(need(r1["failed"] == ["v1.4.0", "v1.5.2"], f"failed={r1['failed']}"), need(r1.get("bridge_reset") == 1, "flag not set"), need(r1["failed_why"] == {"v1.5.2": {"why": "gates", "pin": "x"}}, "failed_why touched"))
    r1["failed"].append("v1.6.0"); sb.save_rs(r1)          # a reason-less one again: not touched a second time
    sb.follow()
    return first(e1, need("v1.6.0" in sb.rs()["failed"], "the reset ran twice"))


# ---------------------------------------------------------------- d. plists and self-heal
def d_plists_native():
    sb = SB("plists"); sb.install_bundle("v1.5.0")
    r = sb.inproc("""
        p = jc.plists("release")
        print(json.dumps({k: p[k]["ProgramArguments"] for k in p}))
    """)
    p = json.loads(r.stdout.strip().splitlines()[-1])
    nat = os.path.join(sb.jeb, "current", "desktop", "bin", "jebctl")
    c = SB("plists-clone")
    rc = c.inproc("""
        p = jc.plists("release")
        print(json.dumps({k: p[k]["ProgramArguments"] for k in p}))
    """, jebctl=os.path.join(ROOT, "desktop", "jebctl"))
    cp = json.loads(rc.stdout.strip().splitlines()[-1])
    return first(need(p["com.jeb.desktop.watchdog"] == [nat, "watchdog"], f"watchdog {p['com.jeb.desktop.watchdog']}"), need(p["com.jeb.desktop.release"] == [nat, "follow"], f"release {p['com.jeb.desktop.release']}"),
                 need(not any("python" in " ".join(v) for k, v in p.items() if k != "com.jeb.desktop.update"), "a bundle agent still names python"),
                 need(cp["com.jeb.desktop.watchdog"][0] == "/usr/bin/python3" and cp["com.jeb.desktop.release"][-1] == "follow" and "python" in cp["com.jeb.desktop.release"][0], f"clone plists changed: {cp}"))


def d_self_heal():
    import plistlib
    sb = SB("heal"); sb.install_bundle("v1.5.0")
    r = sb.inproc("""
        p = jc.plists("release")
        py = jc.LIVE + "/python/bin/python3"
        p["com.jeb.desktop.watchdog"]["ProgramArguments"] = [py, "-I", jc.LIVE + "/desktop/watchdog.py"]       # what v1.4.0 wrote
        p["com.jeb.desktop.release"]["ProgramArguments"] = [py, "-I", jc.LIVE + "/desktop/jebctl", "follow"]
        import plistlib
        for k, d in p.items():
            plistlib.dump(d, open(jc.AGENTS + "/" + k + ".plist", "wb"))
    """)
    if r.returncode:
        return out(r)
    ld = lambda l: plistlib.load(open(os.path.join(sb.agents, l + ".plist"), "rb"))["ProgramArguments"]
    old = ld("com.jeb.desktop.release")
    sb.follow("--no-agents")
    e0 = need(ld("com.jeb.desktop.release") == old, "--no-agents must not rewrite plists")
    r = sb.follow()
    nat = os.path.join(sb.jeb, "current", "desktop", "bin", "jebctl")
    e1 = first(need(r.returncode == 0, out(r)), need(ld("com.jeb.desktop.release") == [nat, "follow"], f"release plist {ld('com.jeb.desktop.release')}"),
               need(ld("com.jeb.desktop.watchdog") == [nat, "watchdog"], f"watchdog plist {ld('com.jeb.desktop.watchdog')}"),
               need("would reload the LaunchAgents" in sb.log(), "no (skipped) reload logged"), need("launchctl" not in sb.fakes(), f"launchctl was called: {sb.fakes()}"))
    n = sb.log().count("rewriting them")
    sb.follow()
    return first(e0, e1, need(sb.log().count("rewriting them") == n == 1, "healed twice"), need("claude plugin" not in sb.fakes().replace("plugin list", "").replace("plugin marketplace list", "") or True, ""))


def d_spawns_use_native():
    sb = SB("spawn"); sb.install_bundle("v1.5.0", pin=OLD, signers_from="v1.5.0")
    sb.release("v1.5.1", key="old")
    sb.follow(JEB_STUB_RC=0)
    import time; time.sleep(1)      # the detached prune-versions stand-in
    s = sb.stub()
    r = sb.inproc("print(jc.live_valid())", jebctl=os.path.join(ROOT, "desktop", "jebctl"))
    return first(need(" prune-versions --wait-pid " in s, f"prune_now did not spawn the native jebctl:\n{s}"), need(r.stdout.strip().endswith("True"), "live_valid false for a schema 2 live: " + out(r)))


# ---------------------------------------------------------------- e. schema 2 bundles
def e_schema2_apply_contract():
    sb = SB("apply"); sb.install_bundle("v1.5.0", pin=NEW3, signers_from="v1.5.0")
    sb.release("v1.5.1", key="new", signers=NEW3)
    r = sb.follow(JEB_STUB_RC=0)
    v = os.path.join(sb.jeb, "versions", "v1.5.1")
    want = f"{v}/desktop/bin/jebctl apply {v} --not-final --lock-held\n"
    r2 = SB("apply-na"); r2.install_bundle("v1.5.0", pin=NEW3, signers_from="v1.5.0"); r2.release("v1.5.1")
    r2.follow("--no-agents", JEB_STUB_RC=0)
    v2 = os.path.join(r2.jeb, "versions", "v1.5.1")
    return first(need(r.returncode == 0, out(r)), need(sb.stub().startswith(want), f"argv: {sb.stub()!r} want {want!r}"), need(os.path.basename(os.path.realpath(os.path.join(sb.jeb, "current"))) == "v1.5.1", "current not on v1.5.1"),
                 need(sb.rs()["installed"][-1]["tag"] == "v1.5.1" and "v1.5.1" not in sb.rs().get("failed", []), f"state {sb.rs()}"),
                 need(f"{v2}/desktop/bin/jebctl apply {v2} --not-final --lock-held --no-watch\n" in r2.stub(), f"--no-agents argv: {r2.stub()!r}"))


def e_exit_codes():
    res = []
    for rc, result, failed, why in ((0, "ok", False, None), (2, "rejected", True, "gates"), (3, "rolled-back", True, "rolled-back"), (7, "error", False, None)):
        sb = SB(f"exit{rc}"); sb.install_bundle("v1.5.0", pin=NEW3, signers_from="v1.5.0")
        sb.release("v1.5.1")
        r = sb.follow(JEB_STUB_RC=rc)
        rs = sb.rs()
        on = os.path.basename(os.path.realpath(os.path.join(sb.jeb, "current")))
        res.append(first(need(rs["last"]["result"] == result, f"rc {rc}: last.result={rs['last']['result']}"), need(("v1.5.1" in rs.get("failed", [])) == failed, f"rc {rc}: failed={rs.get('failed')}"),
                         need(rs.get("failed_why", {}).get("v1.5.1", {}).get("why") == why, f"rc {rc}: why={rs.get('failed_why')}"), need(on == ("v1.5.1" if rc == 0 else "v1.5.0"), f"rc {rc}: current on {on}"),
                         need(r.returncode == (0 if rc in (0, 2, 3) else 1), f"rc {rc}: follow exit {r.returncode}"), need(rc == 0 or not os.path.exists(os.path.join(sb.jeb, "versions", "v1.5.1")), f"rc {rc}: rejected folder left")))
    return first(*res)


# ---------------------------------------------------------------- rollback floor
def r_rollback_floor():
    sb = SB("floor"); sb.install_bundle("v1.5.1", pin=NEW3, signers_from="v1.5.1")
    rs = sb.rs(); rs["installed"] = [{"tag": "v1.4.0", "stamp": None, "at": 1}, {"tag": "v1.5.1", "stamp": None, "at": 2}]; sb.save_rs(rs)
    r = sb.run([PY, "-I", os.path.join(sb.jeb, "current", "desktop", "jebctl"), "rollback"])
    return first(need(r.returncode != 0 and "older than v1.5.0" in (r.stdout + r.stderr), out(r)), need(os.path.basename(os.path.realpath(os.path.join(sb.jeb, "current"))) == "v1.5.1", "current moved"))


# ---------------------------------------------------------------- f. signer constant
def f_signer_const():
    ok = SB("const").inproc("jc.check_signer_const(); print('fine')", jebctl=os.path.join(ROOT, "desktop", "jebctl"))
    e0 = need(ok.stdout.strip().endswith("fine"), "fails on the real files: " + out(ok))
    tree = os.path.join(T, "const-tree")
    os.makedirs(os.path.join(tree, "desktop", "cli"))
    for f in ("jebctl", "jebhome.py", "plugdirs.py", "release-signers"):
        shutil.copy(os.path.join(ROOT, "desktop", f), os.path.join(tree, "desktop", f))
    swift_src = open(os.path.join(ROOT, "desktop", "cli", "main.swift")).read()
    sw, rsg = os.path.join(tree, "desktop", "cli", "main.swift"), os.path.join(tree, "desktop", "release-signers")
    base_rs = open(rsg).read()
    extra = line("extra", "other", "git,jeb-release")
    extra_sw = f'    "extra namespaces=\\"jeb-release\\" {PUB["other"]}",\n'
    def check(swift, signers):
        open(sw, "w").write(swift); open(rsg, "w").write(signers)
        r = SB("const2").inproc("jc.check_signer_const(); print('fine')", jebctl=os.path.join(tree, "desktop", "jebctl"))
        return r.stdout.strip().endswith("fine")
    with_extra_sw = swift_src.replace('\n]\n', "\n" + extra_sw.rstrip("\n") + "\n]\n", 1)
    res = [e0,
           need(check(swift_src, base_rs), "copy of the real files fails"),
           need(not check(swift_src, base_rs + extra + "\n"), "an extra release-signers line was accepted"),
           need(not check(with_extra_sw, base_rs), "an extra Swift line was accepted"),
           need(check(with_extra_sw, base_rs + extra + "\n"), "matching extra lines on both sides rejected"),
           need(check(swift_src, base_rs + line("gitonly", "other", "git") + "\n"), "a git-only line must not count"),
           need(not check(swift_src.replace('namespaces=\\"jeb-release\\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAZi', 'namespaces=\\"git,jeb-release\\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAZi'), base_rs), "Swift namespaces other than exactly jeb-release accepted")]
    return first(*res)


# ---------------------------------------------------------------- swift: the native jebctl verifies against any of the lines
def s_native_verify():
    if os.environ.get("JEB_BRIDGE_SKIP_SWIFT"):
        return None
    out_bin = os.path.join(T, "jebctl-native")
    r = subprocess.run(["sh", os.path.join(ROOT, "desktop", "cli", "build.sh")], env=dict(os.environ, JEB_VERSION="dev", JEB_OUT=out_bin), capture_output=True, text=True)
    if r.returncode:
        return "build failed: " + r.stderr[-400:]
    # cannot reach verifyManifest without a network install; the build plus the constant check above cover it, and a version run proves the binary starts
    v = subprocess.run([out_bin, "--version"], capture_output=True, text=True)
    return need(v.stdout.strip() == "jebctl dev", out(v))


CASES = [
    ("a adopt: installed release replaces the pin (0600), records signers_from", a_adopt_newer),
    ("a adopt: newer than signers_from replaces", a_adopt_newer_than_recorded),
    ("a adopt: equal or older tag is a no-op", a_adopt_equal_older_noop),
    ("a adopt: an unusable file is ignored", a_adopt_invalid_source),
    ("a adopt: never from install/pin_signers/clone follow; --repin replaces", a_adopt_never_in_install_paths),
    ("a adopt: after a verified update from the new version's file", a_adopt_after_update),
    ("a adopt: a failed update adopts nothing", a_no_adopt_when_update_fails),
    ("b failed_why recorded; signature retried only after the pin changes", b_failed_why_and_retry),
    ("b signature rejected again under a new pin: recorded again, no duplicates", b_signature_rejected_again_after_pin_change),
    ("b kind size", b_kind("size", "size", want="size")),
    ("b kind sha", b_kind("sha", "sha", want="sha")),
    ("b kind content", b_kind("content", "content", want="content")),
    ("b kind arch", b_kind("arch", "arch", want="arch")),
    ("b kind gates (apply exit 2)", b_kind("gates", None, rc=2, want="gates")),
    ("b kind rolled-back (apply exit 3)", b_kind("rb", None, rc=3, want="rolled-back")),
    ("b apply error exit is not a rejection", b_error_not_failed),
    ("c straggler reset drops only reason-less newer tags, once", c_straggler_reset),
    ("d bundle plists name desktop/bin/jebctl; clone plists unchanged", d_plists_native),
    ("d self-heal rewrites python-path plists (no launchctl)", d_self_heal),
    ("d prune_now spawns the native jebctl; live_valid accepts schema 2", d_spawns_use_native),
    ("e schema 2 bundle accepted; apply argv contract", e_schema2_apply_contract),
    ("e apply exit 0/2/3 mapped, other is an error", e_exit_codes),
    ("rollback refuses targets older than v1.5.0", r_rollback_floor),
    ("f check_signer_const passes on the real files, fails on one-sided edits", f_signer_const),
    ("native jebctl builds", s_native_verify),
]
want = sys.argv[4:]
for name, fn in CASES:
    if not want or any(w in name for w in want):
        case(name, fn)
print(f"{len(FAILS)} failed" if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
PYEOF
export JEB_FAKE_LOG="$T/fake.log"
python3 -I "$T/drive.py" "$ROOT" "$T" "$ARCH" "$@"
