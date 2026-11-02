#!/usr/bin/python3 -I
"""updater.py: builds the desktop from a snapshot of src/, gates it, and swaps it in (phase 6).

Run by the LaunchAgent com.jeb.desktop.update (WatchPaths on src, plus a slow interval as a
net) and by `jebctl update-now` / `jebctl install`. Fully automatic: no human review, so
the gates are strict and any failure keeps the current app and records the source hash as
rejected (not retried until the source changes again).

  1. wait until the source has been quiet for 60 s (--force/--now skip); take the single-instance lock
  2. snapshot the source into build/<stamp>/; compile there (JebDesktop.dev)
  3. gates: (a) bench smoke over every parity fixture, (b) parity gen + compare all pass,
     (c) tools/day.py all, (d) 20 s headless start with the store watch on a scratch copy of
     the store's farm, live and areas keys
  4. bundle the very binary the gates ran, swap it into the app dir atomically, keep 3 old
  5. watch the heartbeat; roll back if the new build crashes or goes stale

Source = *.swift, build.sh, tools/*.py, tools/*.swift, tools/*.sh (never binaries, fixtures,
logs, runs, meas, modcopy, test, images). Never touches the store (but reads farm, areas and live:*
for gate d), the mod, the wallpaper or src itself.

Env/flags for dry runs: JEB_HOME (state root), JEB_SRC (the source, default src/ beside this
script), JEB_MOD (the mod, default mod/ beside desktop/; both reach the gates), JEB_BUNDLE_MOD (the mod
path written into the bundle's Info.plist instead of JEB_MOD; `jebctl follow` sets it to the clone, as JEB_MOD is a staging copy), JEB_APP_DIR,
--src, --app-dir, --versions-dir, --force, --no-watch, --watch-secs N, --gates-only (stop after
the gates: nothing bundled, swapped or recorded as built), --quick (first install: only the compile, smoke and start
gates; parity and the scripted day are logged as skipped; the rest is unchanged), --prebuilt PATH (copy that
binary in place of running build.sh; `jebctl` passes the release's verified one; every gate still runs on it; the release's detect and
png2raw beside that binary are copied into the snapshot's tools/ in place of compiling them), --no-compile (release mode: never run
build.sh or swiftc; no prebuilt, or a missing helper, is rejected with a plain reason). `jebctl follow` calls main() with a
before_swap hook (the release checkout) that runs after the gates and the bundle, before the swap.

Progress for the menu bar: while it holds the lock it keeps jebHome/update-status.json current (phase, step i of N, started,
and at the end a result: up-to-date, updated, failed, rolled-back or error, with a short detail). A jebHome/check-now file (the
menu's click) is consumed at the start: it skips the 60 s quiet wait but not the pause marker or the seen-hash checks.
`jebctl follow` sets STATUS_SOURCE = "release" and STATUS_FINAL = False: it owns the final result; the phases still go in.
Once the final result is written (status("done"), from finish() or from follow), it posts the Darwin notification
com.jeb.desktop.update-finished so the app can announce the run without polling.
"""
import argparse, concurrent.futures, fcntl, glob, hashlib, importlib.util, json, os, plistlib, re, shutil, subprocess, sys, tempfile, time, ctypes

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import jebhome, plugdirs
jebhome.pin_python()        # a bundle's code runs on the bundle's Python, through ~/.jeb/current when started from there

jebhome.use_dev_dir()       # before anything runs git or xcrun: fall back to the Command Line Tools if Xcode's license blocks
HOME = jebhome.resolve()
LOG = STATE = None


def set_home(home):
    """(Re)derive the paths that hang off the state folder; called at import and after a migration."""
    global HOME, LOG, STATE
    HOME = home
    LOG = os.path.join(HOME, "update.log")
    STATE = os.path.join(HOME, "updater-state.json")


set_home(HOME)
QUIET = 60
WATCH_SECS = 600
HEALTHY_SECS = 180      # a new build that has run this long, awake and not waiting, is accepted early
NO_BEAT_SECS = 240      # no heartbeat of the new stamp by then: nothing picked it up
STALE = 10
KEEP_VERSIONS = 1 if os.path.isfile(os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "bundle.json")) else 3      # a release bundle keeps one spare app: one version on disk
MOD = os.environ.get("JEB_MOD") or os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "mod")


def log(msg):
    os.makedirs(HOME, mode=0o700, exist_ok=True)
    try:
        if os.path.getsize(LOG) > 256 * 1024:
            os.replace(LOG, LOG + ".1")
    except OSError:
        pass
    fd = os.open(LOG, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    with os.fdopen(fd, "a") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg.replace("\n", " | ") + "\n")


STATUS_SOURCE, STATUS_FINAL = "dev", True
FINISHED_NOTIFICATION = "com.jeb.desktop.update-finished"      # Darwin notification the app listens for (UpdateNotifier.swift)
_ST = {"started": None, "finished": False, "clicked": False}


def status(phase, detail="", step=None, steps=None, result=None):
    """Writes update-status.json (atomic, 0600). Never raises: a status that cannot be written must not stop an update."""
    now = int(time.time())
    _ST["started"] = _ST["started"] or now
    first_done = phase == "done" and not _ST["finished"]
    if phase == "done":
        _ST["finished"] = True
    doc = {"phase": phase, "detail": detail, "step": step, "steps": steps, "started": _ST["started"], "at": now,
           "result": result, "source": STATUS_SOURCE, "pid": os.getpid(), "clicked": _ST["clicked"]}
    try:
        os.makedirs(HOME, mode=0o700, exist_ok=True)
        tmp = os.path.join(HOME, "update-status.json.tmp")
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(doc, f)
        os.replace(tmp, os.path.join(HOME, "update-status.json"))
    except OSError:
        pass
    if first_done:
        notify_finished()


def notify_finished():
    """Tells the running app (a Darwin notification) to read the final status, once per run; after the file is written, never raises."""
    try:
        ctypes.CDLL("/usr/lib/libSystem.B.dylib").notify_post(FINISHED_NOTIFICATION.encode())
    except Exception:
        pass


def finish(result, detail):
    """The final status of this run; the release follower writes its own instead."""
    if STATUS_FINAL:
        status("done", detail[:160], result=result)


def tail(text, n=3):
    lines = [l.strip() for l in (text or "").strip().splitlines() if l.strip()]
    return " / ".join(lines[-n:])[:500]


# ---- source hash ----

def source_files(src):
    out = []
    for pat in ("*.swift", "build.sh", "tools/*.py", "tools/*.swift", "tools/*.sh"):
        out += glob.glob(os.path.join(src, pat))
    return sorted(set(p for p in out if os.path.isfile(p)))


def source_hash(src):
    h = hashlib.sha256()
    for p in source_files(src):
        h.update(os.path.relpath(p, src).encode() + b"\0" + hashlib.sha256(open(p, "rb").read()).digest())
    return h.hexdigest()


def newest_mtime(src):
    return max((os.path.getmtime(p) for p in source_files(src)), default=0)


# ---- state ----


def load_state():
    try:
        return json.load(open(STATE))
    except (OSError, ValueError):
        return {"built": None, "stamp": None, "rejected": [], "last": None}

def save_state(st):
    tmp = STATE + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(st, f, indent=1)
    os.replace(tmp, STATE)

def record(st, result, why, stamp=None, h=None):
    st["last"] = {"at": int(time.time()), "result": result, "why": why, "stamp": stamp, "hash": h}
    save_state(st)


# ---- environment for children ----

def clean_env(**extra):
    env = {k: v for k, v in os.environ.items() if not k.startswith("JEB_") or k in ("JEB_MOD", "JEB_SRC", "JEB_BUNDLE_MOD")}
    env.setdefault("JEB_MOD", MOD)
    env["PATH"] = jebhome.SYS_PATH + os.pathsep + jebhome.tools_dir()
    env.update(extra)
    return env


def run(cmd, cwd, timeout, env=None):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env or clean_env())
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired as e:
        return 124, e.stdout or "", "timed out after %ds" % timeout


# ---- snapshot ----

def snapshot(src, dest):
    os.makedirs(dest)
    for p in glob.glob(os.path.join(src, "*.swift")) + [os.path.join(src, "build.sh")]:
        shutil.copy2(p, dest)
    shutil.copytree(os.path.join(src, "tools"), os.path.join(dest, "tools"), ignore=shutil.ignore_patterns("__pycache__", "*.png"))
    os.makedirs(os.path.join(dest, "fixtures"))
    shutil.copy2(os.path.join(src, "fixtures", "band-out.txt"), os.path.join(dest, "fixtures"))


GATE_TOOLS = {      # compiled helpers the parity gate runs; not in git, so a fresh clone builds them (cwd = the snapshot root)
    "detect": ["swiftc", "-O", "tools/detect-src/main.swift", "Art.swift", "PixelArt.swift", "Farm.swift", "Holiday.swift", "-o", "tools/detect"],
    "png2raw": ["swiftc", "-O", "tools/png2raw.swift", "-o", "tools/png2raw"],
}

def build_universal_tools(src, dest):
    """Release side: compiles each GATE_TOOLS helper for arm64 and x86_64 from the source tree and lipos them into dest/<name>.
    Returns an error text or None."""
    os.makedirs(dest, exist_ok=True)
    for n, cmd in GATE_TOOLS.items():
        parts = []
        for arch in ("arm64", "x86_64"):
            out = os.path.join(dest, f"{n}.{arch}")
            c = cmd[:-1] + [out]        # the last argument is the -o target
            rc, o, err = run(c + ["-target", f"{arch}-apple-macos12"], src, 300)
            if rc != 0:
                return f"{n} ({arch}): {tail(err or o, 3)}"
            parts.append(out)
        rc, o, err = run(["lipo", "-create", "-output", os.path.join(dest, n)] + parts, src, 60)
        if rc != 0:
            return f"{n} (lipo): {tail(err or o, 3)}"
        for p in parts:
            os.unlink(p)
    return None


def build_tools(snap):
    """Compiles the gate helpers that the snapshot lacks (the owner's tree has them prebuilt). Returns an error text or None."""
    for n, cmd in GATE_TOOLS.items():
        if not os.path.exists(os.path.join(snap, "tools", n)):
            rc, out, err = run(cmd, snap, 300)
            if rc != 0:
                return f"{n}: {tail(err or out, 3)}"
    return None


# ---- gates ----

def load_parity(snap):
    os.environ.setdefault("JEB_MOD", MOD)     # parity finds the art through JEB_MOD; a snapshot has no mod/ beside it
    spec =importlib.util.spec_from_file_location("parity_snap", os.path.join(snap, "tools", "parity.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def gate_smoke(snap, binary):
    """Every parity fixture renders offscreen without a crash, one place root, no more than one Jeb and one Blue
    (also in the tree), and exactly 1/1 wherever the scene is at home."""
    par = load_parity(snap)
    problems = []
    def one(f):
        name = f["name"]
        env = clean_env(JEB_BENCH="0.01", JEB_BENCH_FREEZE="1", JEB_BENCH_SCALE="1", JEB_BENCH_STORY="1",
                        JEB_STORE_PATH=os.path.join(snap, "fixtures", name + ".store.json"), JEB_NOW=str(f["now"]), JEB_PLACE=f["place"], **f["env"])
        if f["since"] is not None:
            env["JEB_PLACE_SINCE"] = str(f["since"])
        rc, out, err = run([binary], snap, 90, env)
        if rc != 0:
            return f"{name}: exit {rc} {tail(err, 1)}"
        g = re.search(r"place (\S+) roots (\d+) farm (\d+) camp (\d+) road (\d+)", out)
        st = re.search(r"step t=\S+ start cast=(\d+)/(\d+) tree=(\d+)/(\d+) roots=(\d+)", out)
        if not g or not st:
            return f"{name}: no geometry/step line"
        kind, roots = g.group(1), int(g.group(2))
        jeb, blue, jebAll, blueAll = map(int, st.groups()[:4])
        if roots != 1:
            return f"{name}: {roots} place roots"
        if max(jeb, blue, jebAll, blueAll) > 1:
            return f"{name}: cast {jeb}/{blue} tree {jebAll}/{blueAll}"
        if kind == "home" and (jeb, blue, jebAll, blueAll) != (1, 1, 1, 1):
            return f"{name}: at home cast {jeb}/{blue} tree {jebAll}/{blueAll}"
        return None
    with concurrent.futures.ThreadPoolExecutor(4) as ex:
        for r in ex.map(one, par.F):
            if r:
                problems.append(r)
    return (not problems), f"{len(par.F)} fixtures, {len(problems)} problems" + ("".join("; " + p for p in problems[:4]))


def gate_parity(snap):
    env = clean_env(JEB_BIN="JebDesktop.dev")
    rc, out, err = run([sys.executable, "-I", "tools/parity.py", "gen"], snap, 120, env)
    if rc != 0:
        return False, "gen failed: " + tail(err)
    rc, out, err = run([sys.executable, "-I", "tools/parity.py", "compare", "fixtures/band-out.txt"], snap, 1500, env)
    m = re.search(r"-- (\d+) of (\d+) fixtures pass", out)
    if rc != 0 or not m:
        return False, "compare failed: " + tail(err or out)
    ok = int(m.group(1)) == int(m.group(2)) and int(m.group(2)) > 0
    bad = [l[:200] for l in out.splitlines() if l.startswith("FAIL")]
    return ok, f"{m.group(1)} of {m.group(2)} fixtures pass" + ("".join("; " + b for b in bad[:3]))


def gate_day(snap):
    rc, out, err = run([sys.executable, "-I", "tools/day.py", "all"], snap, 900, clean_env(JEB_BIN="JebDesktop.dev"))
    ok = rc == 0 and "scripted day: all good" in out
    return ok, "scripted day all good" if ok else tail("\n".join(l for l in out.splitlines() if "FAIL" in l or l.startswith("    ")) or err or out)


def gate_start(snap, binary):
    """20 s headless with the store watch on, over a scratch copy of the store's farm, live and areas keys only."""
    scratch = os.path.join(snap, "scratch-store")
    shutil.rmtree(scratch, ignore_errors=True)
    os.makedirs(scratch, mode=0o700)
    try:
        return _gate_start(snap, binary, scratch)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)      # every path: pass, fail, timeout, exception


def _gate_start(snap, binary, scratch):
    store = os.path.join(scratch, "store.json")
    note = ""
    try:
        data = json.load(open(plugdirs.store_path()))
        keep = {k: v for k, v in data.items() if k in ("farm", "areas") or k.startswith("live:")}
        del data
    except FileNotFoundError:
        keep = {}       # a fresh machine: no Claude session has loaded the mod yet
    except (OSError, ValueError) as e:
        keep = {}       # unreadable live store: the build is not at fault, run the gate with an empty one
        note = f"; store unreadable ({type(e).__name__}), ran with an empty store"
    def put(content):
        fd = os.open(store + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(content, f)
        os.replace(store + ".tmp", store)
    put(keep)
    env = clean_env(JEB_BENCH="20", JEB_BENCH_WATCH="1", JEB_BENCH_STORY="1", JEB_STORE_PATH=store, JEB_STORY_PATH=os.path.join(scratch, "story.json"))
    p = subprocess.Popen([binary], cwd=snap, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    try:
        time.sleep(6)
        put(keep)           # a store write while it runs: the watch must apply it
        out, err = p.communicate(timeout=60)
    except subprocess.TimeoutExpired:
        p.kill(); p.communicate()
        return False, "did not finish in 60 s"
    except BaseException:
        p.kill(); p.communicate()
        raise
    if p.returncode != 0 or not re.search(r"^bench .*20 s", out, re.M):
        return False, f"exit {p.returncode} {tail(err or out, 2)}"
    return True, "20 s headless run, no crash" + note


# ---- swap, versions, rollback ----

libc = ctypes.CDLL(None, use_errno=True)

def swap_dirs(a, b):
    """Atomically exchange two directories (APFS renamex_np RENAME_SWAP)."""
    if libc.renamex_np(a.encode(), b.encode(), 2) != 0:
        e = ctypes.get_errno()
        raise OSError(e, os.strerror(e), f"{a} <-> {b}")


def bundle_stamp(app):
    try:
        return plistlib.load(open(os.path.join(app, "Contents", "Info.plist"), "rb")).get("CFBundleVersion")
    except (OSError, plistlib.InvalidFileException, ValueError):
        return None


def install_bundle(new_app, app_dir, versions_dir):
    """Puts new_app at app_dir/JebDesktop.app; the old one goes to versions/<its stamp>.app. Returns the old stamp or None."""
    os.makedirs(app_dir, exist_ok=True)
    os.makedirs(versions_dir, exist_ok=True)
    cur = os.path.join(app_dir, "JebDesktop.app")
    stage = os.path.join(app_dir, ".JebDesktop.staging")
    shutil.rmtree(stage, ignore_errors=True)
    subprocess.run(["ditto", new_app, stage], check=True)
    old_stamp = None
    if os.path.isdir(cur):
        old_stamp = bundle_stamp(cur) or "unknown-" + time.strftime("%Y%m%d-%H%M%S")
        swap_dirs(stage, cur)                      # cur is the new build now, stage the old
        dest = os.path.join(versions_dir, old_stamp + ".app")
        shutil.rmtree(dest, ignore_errors=True)
        shutil.move(stage, dest)
    else:
        os.rename(stage, cur)
    olds = sorted((d for d in os.listdir(versions_dir) if d.endswith(".app")), reverse=True)
    for d in olds[KEEP_VERSIONS:]:
        shutil.rmtree(os.path.join(versions_dir, d), ignore_errors=True)
    return old_stamp


def restore_bundle(old_stamp, app_dir, versions_dir):
    cur = os.path.join(app_dir, "JebDesktop.app")
    old = os.path.join(versions_dir, old_stamp + ".app")
    stage = os.path.join(app_dir, ".JebDesktop.staging")
    shutil.rmtree(stage, ignore_errors=True)
    shutil.move(old, stage)
    swap_dirs(stage, cur)
    shutil.rmtree(stage, ignore_errors=True)       # the bad build


def beats():
    """[(pid, stamp, waiting, age_seconds, alive)] from the heartbeat files."""
    d = os.path.join(HOME, "heartbeat")
    out = []
    for n in (os.listdir(d) if os.path.isdir(d) else []):
        if not n.isdigit():
            continue
        p = os.path.join(d, n)
        try:
            j = json.load(open(p))
            age = time.time() - os.path.getmtime(p)
            try:
                os.kill(int(n), 0); alive = True
            except ProcessLookupError:
                alive = False
            except PermissionError:
                alive = True
            out.append((int(n), j.get("stamp"), bool(j.get("waiting")), age, alive))
        except (OSError, ValueError):
            pass
    return out


def watch_new_build(stamp, secs, runlog_offset):
    """Returns None if the new build is healthy, else the reason to roll back."""
    t0 = time.time()
    seen = False
    healthy_since = None
    runlog = os.path.join(HOME, "run.log")
    while time.time() - t0 < secs:
        time.sleep(2)
        try:
            with open(runlog, "rb") as f:
                f.seek(runlog_offset)
                m = re.findall(rb"new binary \(pid \d+\) exited with (-?\d+)", f.read())
                if any(x != b"0" for x in m):
                    return "the new binary exited non-zero (run.log)"
        except OSError:
            pass
        mine = [b for b in beats() if b[1] == stamp]
        if mine:
            seen = True
        dead = [b for b in mine if not b[4]]
        if dead:
            return f"pid {dead[0][0]} of the new build died without a clean exit"
        stale = [b for b in mine if b[3] > STALE]
        if stale:
            return f"heartbeat of pid {stale[0][0]} stale {stale[0][3]:.0f} s"
        if mine and not any(b[2] for b in mine):
            healthy_since = healthy_since or time.time()
            if time.time() - healthy_since >= HEALTHY_SECS:
                return None
        else:
            healthy_since = None
        if not seen and time.time() - t0 > NO_BEAT_SECS:
            return f"no heartbeat from the new build after {NO_BEAT_SECS} s"
    return None if seen else "no heartbeat from the new build"


# ---- main ----

def main(argv=None, before_swap=None):
    # before the lock: migrate takes it too; paused updates leave the folder where it is
    if not os.path.exists(os.path.join(HOME, "updates-paused")) and jebhome.migrate(log) in ("moved", "failed"):
        set_home(jebhome.resolve())
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.environ.get("JEB_SRC") or os.path.join(os.path.dirname(os.path.realpath(__file__)), "src"))
    ap.add_argument("--app-dir", default=os.environ.get("JEB_APP_DIR") or os.path.expanduser("~/Applications"))
    ap.add_argument("--versions-dir", default=os.path.join(HOME, "versions"))
    ap.add_argument("--force", action="store_true", help="skip the debounce, the pause marker and the seen-hash checks")
    ap.add_argument("--now", action="store_true", help="skip the debounce and the pause marker (the seen-hash checks stay)")
    ap.add_argument("--no-watch", action="store_true", help="do not watch the new build after the swap (install)")
    ap.add_argument("--watch-secs", type=int, default=WATCH_SECS)
    ap.add_argument("--gates-only", action="store_true", help="stop after the gates; nothing is bundled or swapped")
    ap.add_argument("--quick", action="store_true", help="first install: compile, smoke and start gates only (parity and day skipped)")
    ap.add_argument("--prebuilt", help="use this binary instead of compiling the snapshot (a verified release asset)")
    ap.add_argument("--no-compile", action="store_true", help="release mode: never compile; reject when the prebuilt app or its helpers are missing")
    a = ap.parse_args(argv)
    os.makedirs(HOME, mode=0o700, exist_ok=True)
    lock = open(os.path.join(HOME, "updater.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("another update is running"); return 0
    _ST["finished"] = False
    try:
        return update(a, before_swap)
    except BaseException as e:
        if not _ST["finished"]:
            finish("error", f"{type(e).__name__}: {e}")
        raise


def update(a, before_swap):
    """Everything after the lock; every exit writes the final status."""
    try:
        os.unlink(os.path.join(HOME, "check-now"))      # the menu's click: skip the quiet wait, nothing else
        clicked = True
    except OSError:
        clicked = False
    _ST["clicked"] = clicked        # the app notifies an up-to-date result only for a click
    if not (a.force or a.now) and os.path.exists(os.path.join(HOME, "updates-paused")):
        if clicked:
            finish("error", "updates are paused")
        return 0
    status("checking")
    if not os.path.isfile(os.path.join(a.src, "build.sh")) or len(source_files(a.src)) < 10:
        log(f"no source at {a.src}; nothing to do"); finish("error", "no source to build"); return 1
    st = load_state()
    if not (a.force or a.now or clicked):
        status("waiting for the source to settle")
        deadline = time.time() + 20 * 60
        while time.time() - newest_mtime(a.src) < QUIET:
            if time.time() > deadline:
                log("source never quiet for 60 s; giving up for now"); finish("error", "source never settled; will retry"); return 0
            time.sleep(min(10, max(1, QUIET - (time.time() - newest_mtime(a.src)) + 1)))
    h = source_hash(a.src)
    if not a.force and h in (st.get("built"), *st.get("rejected", [])):
        if h == st.get("built"):
            finish("up-to-date", "no changes")
        else:       # this source failed a gate before; it is not retried until it changes
            finish("failed", "no changes since a rejected build; see update.log")
        return 0
    stamp = time.strftime("%Y%m%d-%H%M%S", time.gmtime()) + "-" + h[:8]
    snap = os.path.join(HOME, "build", stamp)
    log(f"update {stamp}: " + ("using the prebuilt binary" if a.prebuilt else "building"))
    gates = [g for g in (("smoke",), ("parity", "day"), ("start",)) if not (a.quick and g[0] == "parity")]     # parity and day run together
    steps = 1 + len(gates) + (0 if a.gates_only else 1 + (0 if a.no_watch else 1))     # compile, gates, swap, watch
    status("using the prebuilt binary" if a.prebuilt else "building", step=1, steps=steps)
    try:
        snapshot(a.src, snap)
    except OSError as e:
        log(f"update {stamp}: snapshot failed: {e}"); finish("error", f"snapshot failed: {e}"); return 1
    if source_hash(snap) != h:
        log(f"update {stamp}: source changed during the copy; trying again later")
        shutil.rmtree(snap, ignore_errors=True); finish("error", "source changed; will retry"); return 0

    def reject(gate, why):
        log(f"update {stamp}: REJECTED at {gate}: {why}")
        st.setdefault("rejected", []).append(h)
        st["rejected"] = st["rejected"][-50:]
        record(st, "rejected", f"{gate}: {why}", stamp, h)
        finish("failed", f"{gate}: {why}")
        return 2

    binary = os.path.join(snap, "JebDesktop.dev")
    if a.prebuilt:
        try:
            shutil.copy2(a.prebuilt, binary)
            os.chmod(binary, 0o755)
            for n in GATE_TOOLS:        # the release's helpers sit beside its binary
                tool = os.path.join(os.path.dirname(os.path.abspath(a.prebuilt)), n)
                if os.path.isfile(tool):
                    shutil.copy2(tool, os.path.join(snap, "tools", n))
                    os.chmod(os.path.join(snap, "tools", n), 0o755)
            rc, out, err = 0, "", ""
        except OSError as e:
            rc, out, err = 1, "", f"cannot copy the prebuilt binary: {e}"
    elif a.no_compile:
        return reject("compile", "this release's app could not be downloaded, and Jeb does not compile on this Mac; it will try again later")
    else:
        rc, out, err = run(["sh", "build.sh"], snap, 900, clean_env(JEB_OUT="JebDesktop.dev"))
    if rc != 0 or not os.path.exists(binary):
        return reject("compile", tail(err or out, 4))
    if a.no_compile:
        miss = [n for n in GATE_TOOLS if not os.path.exists(os.path.join(snap, "tools", n))]
        if miss:
            return reject("tools", f"this release's app download lacks the check tools ({', '.join(miss)}), and Jeb does not compile on this Mac; a newer release will fix it")
    why = build_tools(snap)
    if why:
        return reject("tools", why)
    fns = {"smoke": lambda: gate_smoke(snap, binary), "parity": lambda: gate_parity(snap), "day": lambda: gate_day(snap), "start": lambda: gate_start(snap, binary)}
    def gate(name):
        t = time.time()
        ok, why = fns[name]()
        log(f"update {stamp}: gate {name} {'ok' if ok else 'FAILED'} ({time.time() - t:.0f} s): {why}")
        return ok, why
    if a.quick:
        log(f"update {stamp}: gate parity skipped (quick)")
        log(f"update {stamp}: gate day skipped (quick)")
    for i, names in enumerate(gates):
        status("gate " + " + ".join(names), step=2 + i, steps=steps)
        with concurrent.futures.ThreadPoolExecutor(len(names)) as ex:
            res = list(ex.map(gate, names))
        for name, (ok, why) in zip(names, res):
            if not ok:
                return reject(name, why)

    if a.gates_only:
        log(f"update {stamp}: gates passed (gates-only: nothing installed)"); finish("up-to-date", "gates passed; nothing installed"); return 0
    status("swapping", step=steps - (0 if a.no_watch else 1), steps=steps)
    new_app = os.path.join(snap, "JebDesktop.app")
    rc, out, err = run(["sh", os.path.join(snap, "tools", "bundle.sh"), snap, new_app], snap, 120, clean_env(JEB_STAMP=stamp, JEB_PREBUILT=binary))
    if rc != 0 or subprocess.run(["codesign", "--verify", new_app], capture_output=True).returncode != 0:
        return reject("bundle", tail(err or out))
    if before_swap:
        why = before_swap()
        if why:
            log(f"update {stamp}: before-swap step failed, current app kept: {why}")
            record(st, "before-swap-failed", why, stamp, h); finish("error", f"before swap: {why}"); return 1
    offset = os.path.getsize(os.path.join(HOME, "run.log")) if os.path.exists(os.path.join(HOME, "run.log")) else 0
    try:
        old_stamp = install_bundle(new_app, a.app_dir, a.versions_dir)
    except (OSError, subprocess.CalledProcessError) as e:
        log(f"update {stamp}: swap failed, current app kept: {e}")
        record(st, "swap-failed", str(e), stamp, h); finish("error", f"swap failed: {e}"); return 1
    st["built"], st["stamp"] = h, stamp
    log(f"update {stamp}: swapped in (previous {old_stamp})")
    record(st, "swapped", f"previous {old_stamp}", stamp, h)
    if not a.no_watch:
        status("watching the new build", step=steps, steps=steps)
        why = watch_new_build(stamp, a.watch_secs, offset)
        if why:
            log(f"update {stamp}: ROLLBACK: {why}")
            if old_stamp and os.path.isdir(os.path.join(a.versions_dir, old_stamp + ".app")):
                try:
                    restore_bundle(old_stamp, a.app_dir, a.versions_dir)
                except OSError as e:
                    log(f"update {stamp}: rollback failed: {e}"); record(st, "rollback-failed", str(e), stamp, h); finish("error", f"rollback failed: {e}"); return 1
            st.setdefault("rejected", []).append(h)
            st["built"], st["stamp"] = None, old_stamp
            record(st, "rolled-back", why, stamp, h)
            finish("rolled-back", why)
            return 3
        log(f"update {stamp}: healthy")
        record(st, "ok", "healthy", stamp, h)
    else:
        record(st, "ok", "installed", stamp, h)
    finish("updated", f"updated to {stamp}")
    return 0


def prune_builds():
    """Keep the two newest snapshots (a rejected one stays around for a look)."""
    for d in sorted(glob.glob(os.path.join(HOME, "build", "*")))[:-2]:
        shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    try:
        code = main()
    except Exception as e:
        log(f"updater error: {type(e).__name__}: {e}")
        code = 1
    prune_builds()
    sys.exit(code)
