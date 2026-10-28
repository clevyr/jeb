#!/usr/bin/python3 -I
"""watchdog.py: keeps exactly one JebDesktop running (LaunchAgent com.jeb.desktop.watchdog, every 30 s).

- none running, no quit marker: write start-reason, `launchctl kickstart` the agent
- none running, quit marker: nothing (Quit stays quit until a login or `jebctl start`)
- two or more, and none waiting to take over (heartbeat "waiting"): SIGUSR1 to the newer ones
- one running whose heartbeat is stale (>5 s on two checks 10 s apart): TERM, then kickstart
Stale checks are skipped within 60 s of a wake from sleep, or when this watchdog itself
has not run for 90 s (the machine was asleep). Log: watchdog.log (0600, rotated at 256 KB).

After the supervision it samples the one running JebDesktop (CPU, RSS, footprint every 10 min, the
heartbeat counters) into telemetry/YYYY-MM-DD.csv (kept 14 days); see sample(). A telemetry error is
logged and never changes the exit status. --sample-only runs just that.

--dry-run logs to stdout and signals nothing; --fake-procs "pid:startEpoch:path,..." replaces ps.
"""
import argparse, datetime, json, os, re, signal, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jebhome

HOME = jebhome.resolve()
LOG = os.path.join(HOME, "watchdog.log")
QUIET_MARKER = os.path.join(HOME, "quit")
BEATS = os.path.join(HOME, "heartbeat")
TEL = os.path.join(HOME, "telemetry")
LABEL = "com.jeb.desktop"
APP_EXE = os.path.join(os.environ.get("JEB_APP_DIR") or os.path.expanduser("~/Applications"), "JebDesktop.app", "Contents", "MacOS", "JebDesktop")
SRC = os.environ.get("JEB_SRC") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")
STALE = 5
DRY = False


def log(msg):
    line = time.strftime("%Y-%m-%d %H:%M:%S ") + msg
    if DRY:
        print(line); return
    os.makedirs(HOME, mode=0o700, exist_ok=True)
    try:
        if os.path.getsize(LOG) > 256 * 1024:
            os.replace(LOG, LOG + ".1")
    except OSError:
        pass
    fd = os.open(LOG, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    with os.fdopen(fd, "a") as f:
        f.write(line + "\n")


def ours(path):
    """The installed app's executable, or a binary under JEB_SRC (the dev build): the only JebDesktops this signals."""
    p, src = os.path.realpath(path), os.path.realpath(SRC)
    return p == os.path.realpath(APP_EXE) or p.startswith(src + os.sep)


def procs(fake):
    """[(pid, start_epoch, path)] of the running JebDesktop instances (ours, owned by this uid), oldest first."""
    if fake is not None:
        out = [tuple([int(a), float(b), c]) for a, b, c in (x.split(":", 2) for x in fake.split(",") if x)]
    else:
        out = []
        ps = subprocess.run(["ps", "-axo", "pid=,uid=,lstart=,comm="], capture_output=True, text=True).stdout
        for l in ps.splitlines():
            m = re.match(r"\s*(\d+)\s+(\d+)\s+(\w{3} \w{3}\s+\d+ [\d:]{8} \d{4})\s+(.*)$", l)
            if m and int(m.group(2)) == os.getuid() and os.path.basename(m.group(4)) == "JebDesktop":
                out.append((int(m.group(1)), time.mktime(time.strptime(re.sub(r"\s+", " ", m.group(3)), "%a %b %d %H:%M:%S %Y")), m.group(4)))
    return sorted((p for p in out if ours(p[2])), key=lambda p: (p[1], p[0]))


def beats():
    """{pid: (waiting, age_seconds)}; files of dead pids are removed."""
    out = {}
    for n in (os.listdir(BEATS) if os.path.isdir(BEATS) else []):
        if not n.isdigit():
            continue
        p = os.path.join(BEATS, n)
        try:
            alive = True
            try:
                os.kill(int(n), 0)
            except ProcessLookupError:
                alive = False
            except PermissionError:
                pass
            if not alive:
                if not DRY:
                    os.unlink(p)
                continue
            j = json.load(open(p))
            out[int(n)] = (bool(j.get("waiting")), time.time() - os.path.getmtime(p))
        except (OSError, ValueError):
            pass
    return out


def woke_recently():
    try:
        m = re.search(r"sec = (\d+)", subprocess.run(["sysctl", "-n", "kern.waketime"], capture_output=True, text=True).stdout)
        return bool(m) and 0 < time.time() - int(m.group(1)) < 60
    except OSError:
        return False


def kickstart():
    cmd = ["launchctl", "kickstart", f"gui/{os.getuid()}/{LABEL}"]
    if DRY:
        log("would run: " + " ".join(cmd)); return
    r = subprocess.run(cmd, capture_output=True, text=True)
    log(f"kickstart: exit {r.returncode} {r.stderr.strip()[:200]}")


def mark_watchdog_start():
    if DRY:
        return
    os.makedirs(HOME, mode=0o700, exist_ok=True)
    fd = os.open(os.path.join(HOME, "start-reason"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.write(fd, b"watchdog\n"); os.close(fd)


def send(pid, sig, why):
    log(f"{'would send' if DRY else 'sending'} {signal.Signals(sig).name} to {pid}: {why}")
    if not DRY:
        try:
            os.kill(pid, sig)
        except (ProcessLookupError, PermissionError):
            pass


def stale_pids(running, bs):
    out = []
    for pid, start, path in running:
        b = bs.get(pid)
        if b is None:
            # no heartbeat at all: only an installed build (inside a bundle) that has run a while is judged
            if ".app/Contents/MacOS/" in path and time.time() - start > 90:
                out.append(pid)
        elif b[1] > STALE:
            out.append(pid)
    return out


def trim_run_log():
    """run.log is launchd's stderr for the app (held open, append mode): keep the last 200 KB in run.log.1 and empty it past 1 MB."""
    p = os.path.join(HOME, "run.log")
    try:
        if os.path.getsize(p) <= 1024 * 1024:
            return
        with open(p, "rb") as f:
            f.seek(-200 * 1024, 2)
            tail = f.read()
        fd = os.open(p + ".1", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.write(fd, tail); os.close(fd)
        os.truncate(p, 0)
    except OSError:
        pass


COUNTERS = ("tRun", "tPass", "tCov", "tPause")
CSV_HEADER = "epoch,stamp,pid,interval_s,cpu_pct,rss_mb,footprint_mb,sessions,class\n"


def cputime_seconds(text):
    """ps cputime ([[h:]m:]s.ss) in seconds."""
    secs = 0.0
    for part in text.strip().split(":"):
        secs = secs * 60 + float(part)
    return secs


def write_private(path, text):
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def read_json(path):
    try:
        return json.load(open(path))
    except (OSError, ValueError):
        return {}


def footprint_mb(pid):
    r = subprocess.run(["footprint", str(pid)], capture_output=True, text=True, timeout=30)
    m = re.search(r"Footprint:\s*([\d.]+)\s*(KB|MB|GB)", r.stdout)
    return float(m.group(1)) * {"KB": 1 / 1024, "MB": 1, "GB": 1024}[m.group(2)] if m else None


def interval_class(d, dt):
    half = dt / 2
    if d["tPass"] > half: return "passing"
    if d["tCov"] > half: return "covered"
    if d["tRun"] > half: return "calm"
    return "paused" if d["tPause"] > half else "mixed"


def sample(fake=None):
    """One row per run for the single running JebDesktop, from the cumulative CPU time and the
    heartbeat counters since the previous run (same pid, under 90 s apart)."""
    running = procs(fake)
    if len(running) != 1:
        return
    pid = running[0][0]
    hb_path = os.path.join(BEATS, str(pid))
    hb = read_json(hb_path)
    try:
        hb_age = time.time() - os.path.getmtime(hb_path)
    except OSError:
        hb_age = None
    if hb.get("waiting") or any(read_json(os.path.join(BEATS, n)).get("waiting") for n in (os.listdir(BEATS) if os.path.isdir(BEATS) else []) if n.isdigit()):
        return               # a handoff is in progress
    ps = subprocess.run(["ps", "-o", "cputime=,rss=", "-p", str(pid)], capture_output=True, text=True).stdout.split()
    if len(ps) != 2:
        return
    now = time.time()
    cpu, rss = cputime_seconds(ps[0]), int(ps[1]) / 1024
    os.makedirs(TEL, mode=0o700, exist_ok=True)
    os.chmod(TEL, 0o700)
    fp_state = read_json(os.path.join(TEL, "footprint.json"))
    fp = None
    if fp_state.get("pid") != pid or now - fp_state.get("at", 0) >= 600 or fp_state.get("at", 0) > now:
        fp = footprint_mb(pid)
        write_private(os.path.join(TEL, "footprint.json"), json.dumps({"pid": pid, "at": now}))
    counters = {k: hb[k] for k in COUNTERS if isinstance(hb.get(k), (int, float))} if hb_age is not None and hb_age < 10 else {}
    cur = {"pid": pid, "wall": now, "cpu": cpu, "c": counters}
    prev = read_json(os.path.join(TEL, "last.json"))
    write_private(os.path.join(TEL, "last.json"), json.dumps(cur))
    dt = now - prev.get("wall", 0)
    if prev.get("pid") != pid or not 0 < dt < 90 or cpu < prev.get("cpu", 0) or len(counters) != 4 or len(prev.get("c", {})) != 4:
        return
    d = {k: counters[k] - prev["c"][k] for k in COUNTERS}
    if min(d.values()) < 0:
        return
    path = os.path.join(TEL, time.strftime("%Y-%m-%d.csv", time.localtime(now)))
    new = not os.path.exists(path)
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    with os.fdopen(fd, "a") as f:
        if new:
            f.write(CSV_HEADER)
        f.write(f"{int(now)},{hb.get('stamp', '')},{pid},{dt:.1f},{(cpu - prev['cpu']) / dt * 100:.2f},{rss:.1f},"
                f"{'' if fp is None else f'{fp:.1f}'},{hb.get('sessions', '') if isinstance(hb.get('sessions'), int) else ''},{interval_class(d, dt)}\n")
    cutoff = (datetime.date.today() - datetime.timedelta(days=14)).isoformat()
    for n in os.listdir(TEL):
        if re.fullmatch(r"\d{4}-\d\d-\d\d\.csv", n) and n[:10] < cutoff:
            os.unlink(os.path.join(TEL, n))


def sample_safely(fake=None):
    """Telemetry never breaks supervision: an error is logged once per distinct message and swallowed."""
    try:
        sample(fake)
    except Exception as e:
        msg = f"telemetry error: {type(e).__name__}: {e}"
        try:
            seen = os.path.join(HOME, "telemetry-error.txt")
            if not (os.path.exists(seen) and open(seen).read() == msg):
                log(msg)
                write_private(seen, msg)
        except Exception:
            pass


def supervise(a):
    ranfile = os.path.join(HOME, "watchdog.ran")
    try:
        gap = time.time() - os.path.getmtime(ranfile)
    except OSError:
        gap = 0
    if not DRY:
        os.makedirs(HOME, mode=0o700, exist_ok=True)
        open(ranfile, "a").close(); os.utime(ranfile)
    if not DRY:
        trim_run_log()
    running = procs(a.fake_procs)
    marker = os.path.exists(QUIET_MARKER)
    if not running:
        if marker:
            return 0
        last = os.path.join(HOME, "watchdog.kick")
        try:
            if time.time() - os.path.getmtime(last) < 45:
                return 0     # launchd is still starting one (or throttling a crash loop)
        except OSError:
            pass
        log("none running, no quit marker: starting one")
        if not DRY:
            open(last, "a").close(); os.utime(last)
        mark_watchdog_start()
        kickstart()
        return 0
    bs = beats()
    if len(running) >= 2:
        if any(bs.get(p[0], (False, 0))[0] and bs[p[0]][1] < 60 for p in running):
            return 0         # a handoff is in progress
        for pid, _, path in running[1:]:
            send(pid, signal.SIGUSR1, f"{len(running)} running and none waiting; keeping {running[0][0]}")
        return 0
    stale = stale_pids(running, bs)
    if not stale:
        return 0
    if gap > 90 or woke_recently():
        log(f"heartbeat stale for pid {running[0][0]}, but the machine just woke; not acting")
        return 0
    if not a.no_recheck_wait and not DRY:
        time.sleep(10)
    running2 = procs(a.fake_procs)
    if [p[0] for p in running2] != [p[0] for p in running] or woke_recently() or not stale_pids(running2, beats()):
        return 0
    pid = running[0][0]
    log(f"pid {pid}: heartbeat stale on two checks; restarting")
    send(pid, signal.SIGTERM, "stale heartbeat")
    if not DRY and a.fake_procs is None:
        for _ in range(10):
            time.sleep(0.5)
            if not procs(None):
                break
        else:
            send(pid, signal.SIGKILL, "did not stop in 5 s")
            time.sleep(1)
    if not os.path.exists(QUIET_MARKER):
        mark_watchdog_start()
        kickstart()
    return 0


def main():
    global DRY
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--fake-procs")
    ap.add_argument("--no-recheck-wait", action="store_true", help="tests: skip the 10 s between stale checks")
    ap.add_argument("--sample-only", action="store_true", help="only the telemetry sample: no supervision, no signals")
    a = ap.parse_args()
    DRY = a.dry_run
    if a.sample_only:
        sample_safely(a.fake_procs); return 0
    rc = supervise(a)
    if not DRY and a.fake_procs is None:
        sample_safely()
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        log(f"watchdog error: {type(e).__name__}: {e}")
        sys.exit(1)
