#!/usr/bin/python3 -I
"""analyze.py <run dir>...: per Space change, the transition timings from watch's events.log.

For each ActiveSpaceDidChange note: where it came from and went (desktop = no full-screen
backdrop on screen; fs:<app> otherwise), how long the switch animation ran before the note
(the window list shows several Spaces' wallpapers at once), the time the real wallpaper was
visible (GAP), and when Jeb was first seen (SEE jeb) relative to the note.
"""
import re, sys

def load(path):
    ev = []
    for line in open(path):
        m = re.match(r"(\d+) (\S+) (.*)", line.rstrip())
        if m: ev.append((int(m.group(1)), m.group(2), m.group(3)))
    ev.sort(key=lambda e: e[0])
    return ev

def place(state):
    top = re.search(r"top=(\S+)", state).group(1)
    if len(re.findall(r"\bW\d+", state)) > 1: return "anim"
    if re.search(r"\bB\d+", state): return "fs:" + top
    return "desktop"

def summary(run):
    ev = load(run + "/events.log")
    wl = [(t, place(m[3:])) for t, _, m in ev if m.startswith("WL ")]
    gaps, start = [], None
    for t, _, m in ev:
        if m.startswith("GAP start"): start = t
        if m.startswith("GAP end"):
            mx = re.search(r"max wallpaper (\d+)%", m)
            gaps.append((start or t, t, int(mx.group(1)) if mx else 0)); start = None
    notes = [(t, s) for t, s, m in ev if "NOTE ActiveSpaceDidChange" in m]
    rows = []
    for i, (t, s) in enumerate(notes):
        before = [p for (u, p) in wl if u < t - 1 and p != "anim"]
        anim_starts = [u for (u, p) in wl if u <= t and p == "anim" and (not rows or u > rows[-1]["t"])]
        a0 = anim_starts[0] if anim_starts else None
        prev_fixed = [p for (u, p) in wl if p != "anim" and u < (a0 or t)]
        nxt = notes[i + 1][0] if i + 1 < len(notes) else 1e18
        after = [p for (u, p) in wl if t - 150 <= u < min(t + 600, nxt) and p != "anim"]
        dest = after[-1] if after else "?"
        lo = (a0 or t - 1500) - 200
        g = [x for x in gaps if lo <= x[0] <= t + 1500]
        gap = sum(x[1] - x[0] for x in g); mx = max([x[2] for x in g] or [0])
        jeb = next((u - t for u, _, m in ev if lo <= u <= t + 3000 and m.startswith("SEE jeb")), None)
        rows.append(dict(t=t, s=s, frm=prev_fixed[-1] if prev_fixed else "?", to=dest, anim=(t - a0) if a0 else None, gap=gap, mx=mx, jeb=jeb))
    return rows

for run in sys.argv[1:]:
    rows = summary(run)
    print(f"== {run}")
    print(f"{'time':12} {'from':>18} -> {'to':18} {'anim':>5} {'gap':>5} {'maxW%':>5} {'jeb@':>6}")
    for r in rows:
        print(f"{r['s']:12} {r['frm']:>18} -> {r['to']:18} {r['anim'] if r['anim'] is not None else '-':>5} {r['gap']:>5} {r['mx']:>5} {r['jeb'] if r['jeb'] is not None else '-':>6}")
    into = [r for r in rows if r["to"] == "desktop" and r["frm"] != "desktop"]
    bad = [r for r in into if r["gap"] > 0]
    if into:
        print(f"-- into desktop: {len(into)}, with wallpaper showing: {len(bad)}; gap ms: {sorted(r['gap'] for r in into)}")
