#!/usr/bin/python3 -I
"""day.py: a scripted day for the desktop's story, on a scratch store (never the real one).

Runs the dev binary (JEB_BIN, default JebDesktop.dev) offscreen as a bench (JEB_BENCH, JEB_BENCH_WATCH=1) on a
scratch store, with the story's durations cut by JEB_STORY_SCALE (30: a 15 minute home spell is 30 s), while this
script writes the store: records come and go and things turn on. The bench prints one `step` line each time the
story or the store moved the scene: the place, the calls waiting, the cast and the place roots in the tree. Checks, at every step:
exactly one place root and only that place's strip in the tree, one Jeb and one Blue (also counting layers
not shown); and over the day: he is home most of the time, acting out the busy session; the places he stops at and
the reasons for each trip are the expected ones (every trip has a call's reason, a goodbye, or the way home); the
pacing holds (the home spell a call's priority needs, at most 4 outbound trips an hour, visits between 1 and 3
minutes, night: home unless a high call); no unfilled slot or over-long line; and story.json (mode 0600, only the
date, thread id and step, one step a trip, closed on the evening trip home, surviving a restart).
    python3 -I tools/day.py [day|kinds|limit|evening|again|night|all]
"""
import hashlib, json, os, re, subprocess, sys, tempfile, threading, time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(HERE, os.environ.get("JEB_BIN", "JebDesktop.dev"))
SCALE = 30
MIN_STAY, CAP_STAY = 60 / SCALE, 180 / SCALE
SPELL = {"high": 60 / SCALE, "medium": 300 / SCALE, "low": 900 / SCALE}
PRIORITY = {"newArea": "high", "areaAgain": "medium", "event": "medium", "hands": "low", "longWork": "low", "ship": "low", "weather": "low", "errand": "low"}
WINDOW, LIMIT = 3600 / SCALE, 4
HOME_SHARE = 0.6
TOL = 0.35

def farm():
    return json.load(open(os.path.join(HERE, "fixtures", "farm-day.store.json")))["farm"]

def rec(**k):
    r = {"v": 1, "at": int(time.time() * 1000), "frame": 0}
    r.update(k)
    return r

BUSY = dict(busy=True, pose="read", mood="working")
QUIET = dict()
EVENT = dict(event={"id": "bells", "t": 0, "dur": 60, "v": 0})
HANDS = dict(hands=[{"plot": "tobacco", "look": 2}])
SHIP = dict(truck={"t": 3, "load": "bale", "sputter": 0, "dog": False})
RAIN = dict(weather={"kind": "rain", "plot": "corn"})

def akey(tok):
    return hashlib.md5(tok.encode()).hexdigest()[:8]

def area_of(r):
    """A read area made and worked today (so it is new), with generic text."""
    today = time.strftime("%Y-%m-%d")
    return {"v": 1, "made": "offline", "day": today, "seen": today, "name": "Test Area", "terrain": "meadow", "palette": "clay", "weather": "clear",
            "mood": "noon", "motif": "light", "props": ["lantern", "birdhouse", "puddle"], "lore": ["Plain test lore one.", "Plain test lore two."],
            "beats": [{"line": "Test beat one.", "prop": "lantern", "zone": "yard"}, {"line": "Test beat two.", "prop": None, "zone": "porch"},
                      {"line": "Test beat three.", "prop": "cloud", "zone": "sky"}]}

def write(path, records, aged=None):
    """aged: {area key: (made, seen)} for areas made and worked on earlier days (with or without a record naming them)."""
    store = {"farm": farm()}
    areas = {}
    for tok, r in records.items():
        store["live:" + tok] = r
        if r and r.get("area"): areas[r["area"]] = area_of(r)
    for k, (made, seen) in (aged or {}).items(): areas[k] = dict(area_of(None), day=made, seen=seen)
    if areas: store["areas"] = areas
    tmp = path + ".tmp"
    json.dump(store, open(tmp, "w"))
    os.rename(tmp, path)

STEP = re.compile(r"step t=(\S+) (\S+) cast=(\d+)/(\d+) tree=(\d+)/(\d+) roots=(\d+) farm=(\d+) camp=(\d+) road=(\d+) sessions=(\d+) place=(\S+) phase=(\S+) queue=(\S*) to=(\S+) reason=(\S+) acting=(\S+) step=(-?\d+) area=(\S+) arealines=(\d) line=(.*)")
KEYS = ("t", "tag", "jeb", "blue", "jebAll", "blueAll", "roots", "farm", "camp", "road", "sessions", "place", "phase", "queue", "to", "reason", "acting", "step", "area", "arealines", "line")

def run(name, hour, seconds, script, story_path, expect_stops, expect_reasons, expect_step=None, extra=None, night=False, home_share=None, lead=None, away_ok=False):
    """script: [(t, {token: record or None})]; the first entry is the store before the start. lead: (t from, t to, token) he acts out at home."""
    tmp = tempfile.mkdtemp(prefix="jebday")
    store = os.path.join(tmp, "store.json")
    live = dict(script[0][1])
    aged = live.pop("@aged", {})
    write(store, live, aged)
    env = dict(os.environ, JEB_BENCH=str(seconds), JEB_BENCH_WATCH="1", JEB_BENCH_STORY="1", JEB_STORE_PATH=store, JEB_STORY_SCALE=str(SCALE),
               JEB_HOUR=str(hour), JEB_STORY_PATH=story_path)
    env.pop("JEB_PLACE", None); env.pop("JEB_PLACE_SINCE", None)
    env.update(extra or {})
    p = subprocess.Popen([BIN], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=env)
    lines, origin = [], [None]
    def read():
        for line in p.stdout:
            m = STEP.match(line.strip())
            if m:
                if origin[0] is None: origin[0] = time.time()
                lines.append(m.groups())
    th = threading.Thread(target=read); th.start()
    while origin[0] is None and p.poll() is None: time.sleep(0.02)
    for t, change in script[1:]:
        wait = origin[0] + t - time.time()
        if wait > 0: time.sleep(wait)
        for tok, r in change.items():
            if tok == "@aged": aged = dict(aged, **r)
            elif r is None: live.pop(tok, None)
            else: live[tok] = dict(r, at=int(time.time() * 1000))
        write(store, live, aged)
    p.wait(); th.join()
    problems = []
    steps = [dict(zip(KEYS, g)) for g in lines]
    if not steps: problems.append("no step lines")
    seq, reasons = [], []
    prev = None
    homeAt = -float((extra or {}).get("JEB_PLACE_SINCE", 0))  # when he last got home (the home spell counts from there)
    outbound = []          # times an outbound trip started
    for s in steps:
        kind = s["place"].split(":")[0]
        want = {"home": (1, 0, 0), "camp": (0, 1, 0), "road": (0, 0, 1)}[kind]
        if (int(s["roots"]), int(s["farm"]), int(s["camp"]), int(s["road"])) != (1,) + want:
            problems.append(f"t={s['t']}: roots {s['roots']} farm {s['farm']} camp {s['camp']} road {s['road']} at {s['place']}")
        # (a happening's truck takes Jeb away for its trip: none shown then, never two)
        jebs = ("0", "1") if away_ok else ("1",)
        if s["jeb"] not in jebs or s["jebAll"] not in jebs or s["blue"] != "1" or s["blueAll"] != "1":
            problems.append(f"t={s['t']}: cast {s['jeb']}/{s['blue']} (tree {s['jebAll']}/{s['blueAll']}) at {s['place']} {s['phase']}")
        line = s["line"]
        if line != "-" and ("{" in line or len(line) > 60): problems.append(f"t={s['t']}: bad line {line!r}")
        t = float(s["t"])
        if s["place"] != "road" and (not seq or seq[-1][0] != s["place"]):
            seq.append((s["place"], t))
        if s["place"] == "home" and s["phase"] == "arrive": homeAt = t
        if s["phase"] == "leave" and s["reason"] != "-" and (prev is None or prev["phase"] != "leave" or prev["place"] != s["place"]):
            reasons.append((s["reason"], t, s["place"], s["to"]))
            r = s["reason"]
            if s["place"] == "home":
                outbound.append(t)
                need = SPELL[PRIORITY[r]]
                if r not in PRIORITY: problems.append(f"t={s['t']}: trip from home for {r}")
                elif t - homeAt < need - TOL: problems.append(f"t={s['t']}: {r} left {t - homeAt:.1f} s after getting home, needs {need:.1f} s")
                if night and r != "newArea": problems.append(f"t={s['t']}: night trip for {r}")
            elif r not in PRIORITY and r not in ("ended", "homeward", "night"):
                problems.append(f"t={s['t']}: trip with reason {r}")
            elif r in PRIORITY:
                outbound.append(t)
                if PRIORITY[r] == "low": problems.append(f"t={s['t']}: hop to a {r} call (low) without going home")
        prev = s
    for t in outbound:
        n = len([x for x in outbound if t - WINDOW < x <= t])
        if n > LIMIT: problems.append(f"t={t:.1f}: {n} outbound trips in an hour")
    stops = [p for p, _ in seq]
    if stops != expect_stops: problems.append(f"stops {stops} want {expect_stops}")
    got_reasons = [r for r, *_ in reasons]
    if got_reasons != expect_reasons: problems.append(f"reasons {got_reasons} want {expect_reasons}")
    # visits: at least a minute (a goodbye leaves at once), at most three
    camps = [x for x in seq if x[0] != "home"]
    leaves = [r for r in reasons if r[2] != "home"]
    for (place, t0), (reason, t1, frm, to) in zip(camps, leaves):
        if reason != "ended" and t1 - t0 < MIN_STAY - TOL: problems.append(f"stay at {place} {t1 - t0:.1f} s < {MIN_STAY:.1f} s")
        if t1 - t0 > CAP_STAY + TOL: problems.append(f"stay at {place} {t1 - t0:.1f} s > {CAP_STAY:.1f} s")
    # time at home: the place, from step to step (a leaving beat from home counts as home)
    athome, ends = 0.0, [float(s["t"]) for s in steps[1:]] + [float(seconds)]
    for s, e in zip(steps, ends):
        if s["place"] == "home" or (s["phase"] == "leave" and s["place"] == "home"): athome += e - float(s["t"])
    share = athome / seconds
    if home_share is not None and share < home_share: problems.append(f"home {100 * share:.0f}% of the time, want {100 * home_share:.0f}%")
    if lead:
        t0, t1, tok = lead
        got = [s["acting"] for s in steps if t0 <= float(s["t"]) <= t1 and s["place"] == "home" and s["phase"] == "stay"]
        if not got or any(a != tok for a in got): problems.append(f"acting {got} between {t0} and {t1} s, want {tok}")
    st = None
    if os.path.exists(story_path):
        mode = os.stat(story_path).st_mode & 0o777
        st = json.load(open(story_path))
        if mode != 0o600: problems.append(f"story.json mode {oct(mode)}")
        if set(st) != {"d", "id", "step"}: problems.append(f"story.json keys {sorted(st)}")
        if expect_step is not None and st["step"] != expect_step: problems.append(f"story step {st['step']} want {expect_step}")
    elif expect_stops != ["home"]:
        problems.append("no story.json")
    print(f"{'PASS' if not problems else 'FAIL'} {name}: {len(steps)} steps, home {100 * share:.0f}%, stops {' > '.join(stops)}; reasons {','.join(got_reasons)}; story {st}")
    for pr in problems[:12]: print("   ", pr)
    return not problems, st

def day(story):
    A, B = "ax", "bx"
    script = [
        (0, {A: rec(**QUIET)}),
        (2, {B: rec(**BUSY)}),            # busy B: he acts it out at home, no trip
        (4, {A: rec(**EVENT)}),           # a happening at A: a medium call, after the 5 minute spell
        (13, {A: None}),                  # A's session ends while he is there: goodbye, home
        (50, {B: rec(**BUSY, **HANDS)}),  # hands start at B: a low call, after the long spell
        (82, {B: rec(**BUSY)}),           # the hands go home: so does he
    ]
    # the day's errand (a low call, at 14:00 with the long spell up) goes to B at about 44 s
    return run("day", 14, 90, script, story, ["home", "camp:ax", "home", "camp:bx", "home", "camp:bx", "home"],
               ["event", "ended", "errand", "homeward", "hands", "homeward"], expect_step=6, home_share=HOME_SHARE, lead=(1.9, 3.9, B))

def kinds(story):
    A, B = "ax", "bx"
    script = [
        (0, {A: rec(**BUSY), B: rec(**QUIET)}),
        (2, {B: rec(**SHIP)}),                # a ship: low call, the long spell is already up
        (8, {B: rec(**QUIET)}),
        (12, {A: rec(**BUSY, **RAIN)}),       # test weather at A
        (44, {A: rec(**BUSY)}),
    ]
    # A busy from the start: a long work stretch (30 minutes) calls him at about 60 s
    return run("kinds", 9, 85, script, story, ["home", "camp:bx", "home", "camp:ax", "home", "camp:ax", "home"],
               ["ship", "homeward", "weather", "homeward", "longWork", "homeward"], extra={"JEB_PLACE": "home", "JEB_PLACE_SINCE": "100"}, home_share=HOME_SHARE, away_ok=True)

def limit(story):
    toks = ["ax", "bx", "cx", "dx", "ex", "fx"]
    script = [(0, {t: rec(**QUIET, area=akey(t)) for t in toks})]
    # six new areas at once (high calls): the fifth trip of the hour is refused and the rest expire
    return run("limit", 14, 36, script, story, ["home", "camp:ax", "camp:bx", "camp:cx", "camp:dx", "home"],
               ["newArea", "newArea", "newArea", "newArea", "homeward"])

def evening(story):
    script = [(0, {"ax": rec(**BUSY, area=akey("ax"))})]
    return run("evening", 18, 16, script, story, ["home", "camp:ax", "home"], ["newArea", "homeward"], expect_step=90)

def again(story):
    k = akey("ax")
    def ago(n): return time.strftime("%Y-%m-%d", time.localtime(time.time() - n * 86400))
    # an area last worked 5 days ago; a session starts there, and the same write moves its `seen` to today (as the mod does)
    script = [(0, {"@aged": {k: (ago(10), ago(5))}}),
              (2, {"@aged": {k: (ago(10), ago(0))}, "ax": rec(**QUIET, area=k)})]
    return run("again", 14, 20, script, story, ["home", "camp:ax", "home"], ["areaAgain", "homeward"], extra={"JEB_PLACE": "home", "JEB_PLACE_SINCE": "100"})

def night(story):
    A = "ax"
    script = [(0, {A: rec(**QUIET)}), (3, {A: rec(**EVENT)}), (9, {A: rec(**BUSY)})]
    return run("night", 23, 16, script, story, ["home"], [], night=True, home_share=0.99)

def nighthigh(story):
    return run("night-high", 23, 12, [(0, {"ax": rec(**QUIET, area=akey("ax"))})], story, ["home", "camp:ax", "home"], ["newArea", "homeward"], night=True)

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    tmp = tempfile.mkdtemp(prefix="jebstory")
    sp = os.path.join(tmp, "story.json")
    ok = True
    if which in ("day", "all"):
        good, st1 = day(sp); ok &= good
    if which in ("kinds", "all"):
        good, _ = kinds(os.path.join(tmp, "kinds-story.json")); ok &= good
    if which in ("limit", "all"):
        good, _ = limit(os.path.join(tmp, "limit-story.json")); ok &= good
    if which in ("evening", "all"):
        before = json.load(open(sp)) if os.path.exists(sp) else None
        good, st2 = evening(sp); ok &= good
        if before and st2 and (st2["id"], st2["d"]) != (before["id"], before["d"]):
            print("FAIL evening: the thread changed across the restart", before, st2); ok = False
    if which in ("again", "all"):
        good, _ = again(os.path.join(tmp, "again-story.json")); ok &= good
    if which in ("night", "all"):
        good, _ = night(os.path.join(tmp, "night-story.json")); ok &= good
        good, _ = nighthigh(os.path.join(tmp, "night2-story.json")); ok &= good
    print("scripted day:", "all good" if ok else "FAILED")
    sys.exit(0 if ok else 1)
