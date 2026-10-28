#!/usr/bin/python3 -I
"""fake.py <store> <sessions> [busy|idle] [seconds]: writes a scratch store the way the mod does
(temp file, then rename over), with a fixture farm and N made-up sessions' live records,
changing as a session's would: idle ones turn their idle act every 12 s; busy ones change
pose every ~2 s, say a line every ~8 s and send the truck out now and then (t every 500 ms).
Every write's wall time goes to <store>.writes (for the latency check)."""
import json, os, sys, time, random

store, n = sys.argv[1], int(sys.argv[2])
mode = sys.argv[3] if len(sys.argv) > 3 else "idle"
dur = float(sys.argv[4]) if len(sys.argv) > 4 else 1e9
here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
farm = json.load(open(os.path.join(here, "fixtures", "farm-day.store.json")))["farm"]
acts = ["banjo", "sip", "nap", "chase", "smoke"]
poses = ["none", "read", "edit", "still", "think", "draft", "hoe"]
lines = ["Fine day for it.", "Corn's comin' on.", "Still's a-bubblin'.", "Lord willin' and the creek don't rise.", "Hand's out in the tobacco."]
rnd = random.Random(7)
t0 = time.time()
log = open(store + ".writes", "a")
state = [{"tick": 0, "truck": None, "line": None, "said": 0} for _ in range(n)]

def record(i, now):
    s = state[i]
    r = {"v": 1, "at": int(now * 1000), "frame": s["tick"] % 5040}
    idle_act = acts[int((now - t0) / 12 + i) % 5]
    if idle_act != "banjo": r["act"] = idle_act
    if mode == "busy":
        r["busy"] = True; r["mood"] = "working"
        pose = poses[int((now - t0) / 2 + i) % len(poses)]
        if pose != "none": r["pose"] = pose
        if s["truck"] is not None:
            r["truck"] = {"t": s["truck"], "load": "jar", "sputter": 0, "dog": False}
        if now - s["said"] < 8 and s["line"]:
            r["line"] = s["line"]; r["saidAt"] = int(s["said"] * 1000)
        r["hands"] = [{"plot": "corn", "look": i % 6}]
    r["live"] = "BGRPYN"[i % 6]
    return r

last = None
while time.time() - t0 < dur:
    now = time.time()
    for i, s in enumerate(state):
        s["tick"] = int((now - t0) * 2)
        if mode == "busy":
            if s["truck"] is None and rnd.random() < 0.004: s["truck"] = 0
            elif s["truck"] is not None:
                s["truck"] = int((now - s.get("truckAt", now)) * 2) if "truckAt" in s else 0
                s.setdefault("truckAt", now)
                if s["truck"] >= 16: s["truck"] = None; s.pop("truckAt", None)
            if rnd.random() < 0.06 and now - s["said"] > 8: s["line"] = rnd.choice(lines); s["said"] = now
    body = {"farm": farm}
    for i in range(n):
        body[f"live:fake{i}"] = record(i, now)
    key = json.dumps({k: {kk: vv for kk, vv in v.items() if kk not in ("at", "frame")} for k, v in body.items() if k != "farm"})
    if key != last:
        last = key
        tmp = store + ".tmp"
        with open(tmp, "w") as f: json.dump(body, f)
        os.replace(tmp, store)
        log.write(f"{time.time() * 1000:.1f}\n"); log.flush()
    time.sleep(0.5)
