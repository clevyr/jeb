#!/usr/bin/python3 -I
"""parity.py gen|compare: the desktop's parity fixtures.

gen: writes each fixture as a store file for the desktop (fixtures/<name>.store.json:
the farm and the live records, nothing else) and the band's side as a scratch test in
the mod COPY (modcopy/tests/zz-parity.test.tsx), which composes the band's own pixels
for the same state inside the engine's test sandbox and prints them.

compare <band-output>: renders each fixture on the desktop (offscreen, CARenderer),
finds the sprites and labels the checks name in both pictures (tools/detect) and
compares them: farm things against the homestead (same layout rules, same width, so
the same positions), home things (the one Jeb, Blue, chair, bang, hat, bubble: the record
acted out at the place on screen) relative to the one Jeb, camp things (what a session's camp
keeps: rigs, Opal, hands) relative to the camp's anchors, and counts. The scene is one place
at a time (the stage strip): a fixture starts at the place JEB_PLACE seeds (home, or a camp:
"place" below), farm fixtures at home, camp fixtures at the camp of fx00. Every fixture is
also checked for exactly one place root in the tree, the strips of that place only, and no
more than one Jeb and one Blue. A fixture with only desktop-only checks (home-has,
scene-count, mist, absent, story) needs no band output.
"""
import json, os, subprocess, sys, time, copy, re
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(HERE, "fixtures")
REPO = os.path.dirname(os.path.dirname(HERE))
ART = os.path.join(os.environ.get("JEB_MOD") or os.path.join(REPO, "mod"), "hooks", "pixel-art.ts")
COLS = 106  # the band at 424 px, the desktop's farm width on this screen

def ms(y, mo, d, h, mi=0):
    return int(time.mktime((y, mo, d, h, mi, 0, 0, 0, -1)) * 1000)

BASE = {
    "version": 10, "rev": 1,
    "crops": {"tobacco": [3, 2, 1, 0, 3, 2, 1, 0], "corn": [0, 1, 2, 3, 0, 1, 2, 3], "apples": [3, 2, 1, 0, 0, 0, 0, 0]},
    "progress": {"tobacco": 0, "corn": 0, "apples": 0},
    "barn": {"bales": 0, "corn": 9, "apples": 23, "sticks": 0},
    "still": {"steps": 0, "hasBatch": False},
    "shelf": {"lightning": 0, "appleCinnamon": 7},
    "lifetime": {"outputTokens": 0, "inputTokens": 0, "workMs": 0, "bales": 12, "balesTraded": 0},
    "ledger": {"cash": 1590, "total": 1620},
    "upgrades": [], "built": [],
    "materials": {"lumber": 10, "stone": 2, "straw": 43, "iron": 0, "sugar": 0, "copper": 0},
    "components": {"barrel": 0, "post": 0, "coil": 0},
    "goods": {"appleButter": 0, "twists": 0, "aged": [], "whiskey": 0},
    "quilt": [{"c": c, "d": "2026-10-01", "camp": ""} for c in "BGRPYNBG"],
    "unlocks": [], "unlockDay": {"d": "", "n": 0, "done": 0, "next": 0, "since": "", "coffee": ""},
    "surprises": [], "creative": {"total": 0, "arc": None, "structures": [], "art": [], "festival": {"d": "", "tint": ""}},
}

JEB = ["jeb-idle", "jeb-happy", "jeb-spooked", "jeb-wink", "jeb-think", "jeb-sleep", "jeb-banjo", "jeb-sip", "jeb-hoe", "jeb-broom",
       "jeb-book", "jeb-stir", "jeb-salute", "jeb-wave", "jeb-hold"]
BLUE = ["blue-wag", "blue-run", "blue-nap", "blue-bark"]
FARM_CORE = ["house", "house-coat", "house-night", "house-coat-night", "still", "still-keg", "still-worm", "still-tarp", "sign", "sign-coat",
             "sign-night", "embers", "icon-jar", "icon-cash"]

F = []  # (name, rows, now, farm-overrides, [records], checks)
def fx(name, rows, now, farm=None, live=None, checks=(), env=None, place="home", since=None, areas=None):
    F.append({"name": name, "rows": rows, "now": now, "farm": farm or {}, "live": live or [], "checks": list(checks), "env": env or {}, "place": place, "since": since,
              "areas": areas})

def rec(now, **k):
    r = {"v": 1, "at": now, "frame": 0}
    if "line" in k: r["saidAt"] = now - 1000
    r.update(k)
    return r

D = ms(2026, 10, 21, 14)      # a Wednesday afternoon in October
N = ms(2026, 7, 9, 23)        # a July night

# Area 2-3, 12-13: the farm itself.
fx("farm-day", "2.1 2.4 3.1 3.4 3.6 12.1 13.1", D, {}, [rec(D)], [("pixels", 0, 0, 250, 48),
    ("farm", ["tobacco-0", "tobacco-1", "tobacco-2", "tobacco-3", "corn-0", "corn-1", "corn-2", "corn-3", "apple-0", "apple-1", "apple-2", "apple-3"]),
    ("farm", FARM_CORE + ["icon-lumber", "icon-stone", "icon-straw", "quilt-B", "quilt-G", "quilt-R", "quilt-P", "quilt-Y", "quilt-N"]),
    ("farm", ["text:white:TOBACCO 12", "text:white:CORN 9", "text:white:APPLES 23", "text:white:x7", "text:white:$1.5k", "text:cloud:10", "text:cloud:43"]),
])
fx("farm-built", "2.6 3.3 3.4 3.8 3.10 3.11 3.14 12.1 12.3", D,
   {"upgrades": ["mailbox", "chair", "hen", "pup", "coat", "still2"], "built": ["fencedFields", "copperWorm", "thumpKeg", "smokehouse"],
    "materials": {"lumber": 120, "stone": 5, "straw": 2, "iron": 1, "sugar": 0, "copper": 3}, "goods": {"appleButter": 4, "twists": 0, "aged": [{"readyAt": 1}], "whiskey": 1}},
   [rec(D)], [
    ("pixels", 0, 0, 250, 48), ("farm", FARM_CORE + ["prop-fence", "prop-mailbox", "prop-keg", "prop-smokehouse", "icon-lumber", "icon-stone", "icon-copper", "icon-apple_butter", "icon-whiskey"]),
    ("farm", ["text:cloud:99+", "text:cloud:5", "text:cloud:3", "text:cloud:4", "text:cloud:2"]),
])
fx("farm-night", "1.2 1.3 1.4 3.1", N, {"upgrades": ["coat"]}, [rec(N, act="nap")], [
    ("farm", ["house-coat-night", "sign-coat", "firefly"]),
    ("home", ["jeb-sleep", "zz", "blue-nap"]),
])
fx("quilt-stitch", "13.1 13.2 13.3", D, {}, [rec(D, stitch=True, live="P", frame=0)], [
    ("farm", ["quilt-B", "quilt-G", "quilt-R", "quilt-P", "quilt-Y", "quilt-N"]),
])

# Area 1: the calendar.
fx("pumpkin", "1.10", ms(2026, 10, 27, 10), {"crops": {"tobacco": [0] * 8, "corn": [0] * 8, "apples": [3, 3, 3, 3, 0, 0, 0, 0]}}, [rec(ms(2026, 10, 27, 10))],
   [("farm", ["apple-pumpkin", "apple-3", "prop-pumpkin"])])
fx("christmas", "1.9", ms(2026, 12, 22, 10), {}, [rec(ms(2026, 12, 22, 10))], [("farm", ["prop-xmas"])])
fx("thanksgiving", "1.11", ms(2026, 11, 26, 10), {}, [rec(ms(2026, 11, 26, 10))], [("farm", ["turkey"])])
fx("groundhog", "1.12", ms(2027, 2, 2, 10), {}, [rec(ms(2027, 2, 2, 10))], [("farm", ["groundhog"])])

# Area 4: Jeb's sprite by priority, Blue's states.
J = ms(2026, 10, 21, 15)
fx("jeb-gate", "4.1 15.7", J, {}, [rec(J, gated=True, fx=["sip"], pose="read")], [("home", JEB)])
fx("jeb-sip", "4.1 4.7 3.9", J, {"upgrades": ["chair"]}, [rec(J, fx=["sip"], pose="read")], [("home", JEB + ["prop-chair"])])
fx("jeb-pose-read", "4.2", J, {}, [rec(J, pose="read", mood="spooked")], [("home", JEB)])
fx("jeb-pose-still", "4.2 3.5", J, {}, [rec(J, pose="still", busy=True, mood="working")], [("home", JEB), ("count", "fire", 1), ("count", "steam", 1)])
fx("jeb-think", "4.2 11.6", J, {}, [rec(J, pose="think")], [("home", JEB)])
fx("jeb-hoe", "4.2 11.8", J, {}, [rec(J, pose="hoe")], [("home", JEB)])
fx("jeb-sweep", "4.2 11.11", J, {}, [rec(J, pose="sweep")], [("home", JEB)])
fx("jeb-spooked", "4.3 4.6", J, {}, [rec(J, mood="spooked")], [("home", JEB + ["sweat"])])
fx("jeb-pleased", "4.3", J, {}, [rec(J, mood="pleased", fx=["wink"])], [("home", JEB)])
fx("jeb-wink", "4.11", J, {}, [rec(J, fx=["wink", "wag"], frame=1)], [("home", JEB + BLUE + ["heart"])])
fx("jeb-working", "4.3", J, {}, [rec(J, mood="working", busy=True)], [("home", JEB)])
fx("jeb-banjo", "4.4", J, {}, [rec(J, act="banjo", frame=1)], [("home", JEB + ["note"])])
fx("jeb-nap", "4.4 4.9", J, {}, [rec(J, act="nap")], [("home", JEB + BLUE + ["zz"])])
fx("blue-chase", "4.4 4.9 3.10", J, {"upgrades": ["hen"]}, [rec(J, act="chase", frame=3)], [("home", BLUE + ["hen"])])
fx("blue-errand", "4.10", J, {}, [rec(J, dogRun=12, frame=5)], [("home", BLUE)])
fx("jeb-away", "4.8 7.1 3.9", J, {"upgrades": ["chair"]}, [rec(J, truck={"t": 3, "load": "bale", "sputter": 0, "dog": False})],
   [("home", JEB + BLUE + ["prop-chair", "bang"]), ("farm", ["truck-bales", "dust"])])
fx("truck-home", "7.1 7.2", J, {}, [rec(J, truck={"t": 12, "load": "jar", "sputter": 0, "dog": True})],
   [("farm", ["truck-empty", "icon-cash", "blue-wag", "dust"]), ("home", BLUE)])
fx("truck-butter", "7.1", J, {}, [rec(J, truck={"t": 2, "load": "butter", "sputter": 2, "dog": False})], [("farm", ["truck-crate", "icon-apple_butter", "dust"])])
fx("puff", "4.11", J, {}, [rec(J, fx=["puff"])], [("farm", ["truck-empty", "dust"])])

# Area 5-6: hands, teammates, lanterns.
fx("hands", "5.1 2.5", J, {}, [rec(J, hands=[{"plot": "tobacco", "look": 2}, {"plot": "corn", "look": 4}], more={"corn": 3})],
   [("count", "hand-work-2", 1), ("count", "hand-work-4", 1), ("text", "text:yellow:+3")])
fx("workflow", "5.2", J, {}, [rec(J, hands=[{"plot": "tobacco", "look": 1}, {"plot": "corn", "look": 1}, {"plot": "apples", "look": 1}], more={"tobacco": 4})],
   [("count", "hand-work-1", 3), ("text", "text:yellow:+4")])
fx("mates", "5.6", J, {}, [rec(J, mates=2)], [("count", "opal", 1), ("count", "hand-work", 1)])
fx("lanterns", "6.2", J, {}, [rec(J), rec(J), rec(J)], [("lanterns", 3)])

# Area 7: visits.
fx("visit-arrive", "7.3", J, {}, [rec(J, visit={"kind": "store", "x": 16, "facing": "in", "phase": "arrive"})], [("lane", "rig-store", 16, 32, 40, False)])
fx("visit-deal", "7.3 7.5 4.9", J, {}, [rec(J, visit={"kind": "mill", "x": 32, "facing": "in", "phase": "deal"})], [("home", JEB + BLUE + ["bang"]), ("camp", ["rig-mill"])])
fx("visit-opal", "7.3 7.4", J, {}, [rec(J, visit={"kind": "opal", "x": 10, "facing": "out", "phase": "leave"})], [("lane", "opal", 10, 20, 14, True)])
fx("visit-tractor", "7.3", J, {}, [rec(J, visit={"kind": "tractor", "x": 30, "facing": "in", "phase": "arrive"})], [("count", "rig-tractor", 1)])
fx("visit-mail", "7.4", J, {"upgrades": ["mailbox"]}, [rec(J, visit={"kind": "mail", "x": 32, "facing": "in", "phase": "deal"})], [("home", JEB), ("camp", ["rig-mail"])])

# Area 8: happenings.
def ev(id, t, dur, v=0): return {"id": id, "t": t, "dur": dur, "v": v}
fx("ev-revenuer", "8.1 3.4", J, {}, [rec(J, event=ev("revenuer", 40, 96), mood="spooked")], [("farm", ["revenuer", "still-tarp"]), ("home", JEB)])
fx("ev-neighbor", "8.2", J, {}, [rec(J, event=ev("neighbor", 60, 96))], [("home", JEB), ("camp", ["opal"])])
fx("ev-neighbor-walk", "8.2", J, {}, [rec(J, event=ev("neighbor", 20, 96))], [("walk", "opal", 20 / 96)])
fx("ev-bear", "8.3", J, {}, [rec(J, event=ev("bear", 30, 80), frame=0)], [("farm", ["bear"]), ("home", ["bang"] + BLUE)])
fx("ev-whistlepig", "8.4 2.7", J, {}, [rec(J, event=ev("whistlepig", 24, 72, 3))], [("farm", ["groundhog"])])
fx("ev-mothman", "8.5", N, {}, [rec(N, event=ev("mothman", 12, 60, 2), mood="spooked")], [("farm", ["mothman"])])
fx("ev-bugs", "8.6", ms(2026, 6, 20, 22), {}, [rec(ms(2026, 6, 20, 22), event=ev("bugs", 36, 96, 5))], [("farm", ["firefly"])])
fx("ev-bells", "8.7", ms(2026, 10, 25, 10), {}, [rec(ms(2026, 10, 25, 10), event=ev("bells", 12, 60))], [("farm", ["prop-bell", "note"])])
fx("ev-storm", "8.8", J, {}, [rec(J, event=ev("storm", 30, 96))], [("farm", ["cloud-dark"])])
fx("ev-turkeys", "8.10", J, {}, [rec(J, event=ev("turkeys", 40, 90))], [("farm", ["turkey"])])
fx("ev-parachute", "8.11", J, {}, [rec(J, event=ev("parachute", 50, 100))], [("farm", ["prop-parachute"])])
fx("ev-track", "8.12", ms(2026, 10, 21, 18), {}, [rec(ms(2026, 10, 21, 18), event=ev("track", 12, 60))], [("home", ["bang"] + BLUE)])
fx("ev-hornworm", "8.13", J, {}, [rec(J, event=ev("hornworm", 12, 60))], [("home", JEB + ["sweat"])])
fx("ev-applebutter", "8.14", J, {}, [rec(J, event=ev("applebutter", 12, 80))], [("home", JEB)])
for i, (id, sprite) in enumerate([("bees", "jeb-wave"), ("sorghum", "jeb-stir"), ("ramps", "jeb-hoe"), ("sang", "jeb-hoe"), ("quilting", "jeb-hold")]):
    fx(f"story-{i + 1}", f"A{i + 1}", J, {}, [rec(J, event=ev(id, 12, 70))], [("home", JEB)])

# Area 9: drops.
art = {"id": "lantern-fox", "w": 6, "h": 5, "frames": 1, "rows": ["..yy..", ".yyyy.", "yykkyy", ".yyyy.", "..yy.."]}
fx("drops", "9.3 9.4 9.5 9.9 9.10", J, {
    "surprises": [{"day": "2026-10-21", "slot": 9, "kind": "decor", "name": "x", "lines": [], "sprites": [{"sprite": "deer", "zone": "yard", "frames": 1}, {"sprite": "cardinal", "zone": "porch", "frames": 2}],
                   "window": None, "lasts": "today", "made": "local", "arc": "", "step": 0, "festival": ""}],
    "creative": {"total": 3, "arc": None, "structures": [{"name": "s", "day": "2026-10-20", "arc": "", "sprites": [{"sprite": "lantern-fox", "zone": "field", "frames": 1}]}],
                 "art": [art], "festival": {"d": "", "tint": ""}}},
   [rec(J, event={"id": "drop", "t": 10, "dur": 80, "v": 1, "art": {"sprites": [{"sprite": "bell", "zone": "sky", "frames": 1}], "custom": []}})],
   [("farm", ["deer", "cardinal", "prop-bell"]), ("pixels", 2, 0, 160, 40)])
fx("festival", "9.8", J, {"creative": {"total": 3, "arc": None, "structures": [], "art": [], "festival": {"d": "2026-10-21", "tint": "gold"}}}, [rec(J)], [("farm", FARM_CORE), ("tint", "dirt", (255, 200, 80))])

# Area 10 and the little things (list C): every look, at its hour.
ALL = ["birdhouse", "woodpile", "garden", "creek", "cardinal", "owl", "butterflies", "deer", "drift", "afterrain", "shootingstar", "mug", "lunch",
       "napchair", "porchlight", "sundayhat", "washday", "postcard", "anniversary", "midnightcoffee"]
L = {"unlocks": ALL, "upgrades": ["chair"], "materials": {"lumber": 25, "stone": 0, "straw": 0, "iron": 0, "sugar": 0, "copper": 0}}
mon9 = ms(2026, 6, 15, 9)
fx("looks-1", "C1 C3 C5 C6 C7 C8 C9 C17", mon9, L, [rec(mon9)],
   [("farm", ["creek", "laundry-shirt", "laundry-overalls", "woodpile-3", "axe-stump", "garden-2", "birdhouse", "bluebird", "cardinal", "mug"])])
sat14 = ms(2026, 6, 13, 14)
fx("looks-2", "C2 C11 C20", sat14, L, [rec(sat14)], [("farm", ["creek", "fisher", "butterfly"]), ("home", JEB + ["prop-chair", "zz"])])
sun12 = ms(2026, 6, 14, 12, 30)
fx("looks-3", "C19 C22", sun12, L, [rec(sun12)], [("farm", ["lunch"]), ("home", ["hat-feather"] + JEB)])
wed18 = ms(2026, 10, 21, 18)
fx("looks-4", "C4 C12 C21", wed18, L, [rec(wed18)], [("farm", ["deer", "porch-light", "drift-leaf-0", "drift-leaf-1", "drift-leaf-2"])])
wed15 = ms(2026, 10, 21, 15)
fx("looks-5", "C23", wed15, L, [rec(wed15)], [("farm", ["postcard"])])
n23 = ms(2026, 7, 9, 23)
fx("looks-6", "C10 C14 C15 C16", n23, L, [rec(n23, rainbow=True, wet=True, star=6)], [("farm", ["owl", "rainbow", "puddle", "star-streak"])])
c2 = ms(2026, 1, 7, 2)
fx("looks-7", "C18", c2, dict(L, unlockDay={"d": "", "n": 0, "done": 0, "next": 0, "since": "", "coffee": "2026-01-07"}), [rec(c2)], [("farm", ["mug"])])
an = ms(2026, 3, 4, 10)
fx("looks-8", "C24", an, dict(L, unlockDay={"d": "", "n": 0, "done": 0, "next": 0, "since": "2025-03-04", "coffee": ""}), [rec(an)], [("farm", ["cake"])])
snow = ms(2026, 1, 15, 11)
fx("looks-9", "C13", snow, L, [rec(snow)], [("farm", ["drift-flake"])])

# Area 11: the bubble.
fx("bubble", "11.1", J, {}, [rec(J, line="Picked every last one. Lord willin', they'll keep.", mood="pleased")], [("bubble", False)])
fx("bubble-dim", "11.2", J, {}, [rec(J, line="Quiet day on the ridge.", dim=True)], [("bubble", True)])
fx("cows", "11.1 appendix-b", J, {}, [rec(J, cows=[42, 7], moreCows=2)], [("count", "cow", None), ("text", "text:white:#42")])

# Area 2: test weather at a camp.
fx("rain", "2.8", J, {}, [rec(J, weather={"kind": "rain", "plot": "corn"})], [("count", "cloud-dark", 1)])
fx("rain-all", "2.8", J, {}, [rec(J, weather={"kind": "rain", "plot": "all"})], [("count", "cloud-dark", 3)])
fx("dry", "2.9", J, {}, [rec(J, weather={"kind": "dry", "plot": "tobacco"})], [("dry", "tobacco")])

# One Jeb and one Blue, whatever the number of sessions, at the one place on screen. These check the desktop's own rules
# (the band draws the first record only), so they need no band output.
# lead-two: at home he acts out the busy session (reading), not the newer idle one (the idle Jeb would play the banjo).
fx("lead-two", "4.2 11.1", J, {}, [rec(J), rec(J - 30000, pose="read", busy=True, mood="working")],
   [("home-has", ["jeb-book"], ["jeb-banjo", "jeb-hold"]), ("scene-count", JEB, 1), ("scene-count", BLUE, 1),
    ("story", {"place": "home", "phase": "stay", "acting": "fx01", "queue": ""})], since=800)
# lead-hold: at home, fx00 (idle, its line fresh) holds the lead against the newer idle fx01 while its line is up.
fx("lead-hold", "4.12 11.1", J, {}, [rec(J - 5000, mood="pleased", line="Holding steady now"), rec(J)],
   [("home-has", ["jeb-happy", "text:ink:Holding steady now"], ["jeb-banjo"]), ("scene-count", JEB, 1),
    ("story", {"place": "home", "phase": "stay", "acting": "fx00", "queue": ""})], since=800)
# one-jeb: four sessions, one Jeb and one Blue in the whole scene.
fx("one-jeb", "3.9 4.x", J, {}, [rec(J - 1000, pose="read", busy=True), rec(J), rec(J - 2000, pose="edit", busy=True), rec(J - 3000, mood="pleased")],
   [("scene-count", JEB, 1), ("scene-count", BLUE, 1), ("home-has", ["jeb-book"], [])], since=0)
# place-one: four sessions with something each (hands, cows, rain; a visitor; a truck and a happening), one place drawn: the homestead,
# acting out fx00; nothing of the others is drawn, 1 Jeb and 1 Blue, one place root and one farm strip. Their calls wait out the home spell.
fx("place-one", "one place", J, {}, [
    rec(J - 1000, pose="read", busy=True),
    rec(J - 2000, hands=[{"plot": "tobacco", "look": 2}, {"plot": "corn", "look": 4}], cows=[42, 7], weather={"kind": "rain", "plot": "corn"}, building="app"),
    rec(J - 3000, visit={"kind": "store", "x": 16, "facing": "in", "phase": "arrive"}),
    rec(J - 4000, truck={"t": 3, "load": "bale", "sputter": 0, "dog": False}, event=ev("revenuer", 40, 96))],
   [("scene-count", JEB, 1), ("scene-count", BLUE, 1), ("home-has", ["jeb-book"], []),
    ("absent", ["hand-work-2", "hand-work-4", "cow", "cloud-dark", "rig-store", "truck-bales", "revenuer"]),
    ("story", {"place": "home", "phase": "stay", "acting": "fx00", "queue": "hands@fx01,weather@fx01,event@fx03,ship@fx03"}), ("places", "home")], since=5)
# queue-order: at home past the medium spell, four calls wait (low, low, medium, low): the medium one goes first, and the lows keep their order.
HANDS = [{"plot": "tobacco", "look": 2}]
fx("queue-order", "queue", J, {}, [rec(J - 1000, hands=HANDS), rec(J - 2000, weather={"kind": "rain", "plot": "corn"}), rec(J - 3000, event=ev("bells", 12, 60)),
                                  rec(J - 4000, truck={"t": 3, "load": "bale", "sputter": 0, "dog": False})],
   [("story", {"place": "home", "phase": "leave", "to": "fx02", "queue": "hands@fx00,weather@fx01,ship@fx03", "reason": "event"}), ("scene-count", JEB, 1), ("scene-count", BLUE, 1)],
   since=400)
# visit-hold: 30 s into a visit he stays at least a minute, though the session is quiet and a medium call waits.
fx("visit-hold", "visit", J, {}, [rec(J - 60000), rec(J - 1000, event=ev("bells", 12, 60))],
   [("story", {"place": "camp:fx00", "phase": "stay", "queue": "event@fx01"}), ("scene-count", JEB, 1), ("places", "camp")], place="fx00", since=30)
# quiet-home: nobody waits and the visit has run its 90 s: he sets out for home, not on to another camp.
fx("quiet-home", "visit", J, {}, [rec(J - 40000)], [("story", {"place": "camp:fx00", "phase": "leave", "to": "home", "reason": "homeward", "queue": ""})],
   place="fx00", since=100)
# home-quiet: at home with no current record: the calm idle, not a record's nap.
fx("home-quiet", "home", J, {}, [rec(J - 700000, act="nap")],
   [("home-has", ["jeb-idle"], ["jeb-sleep"]), ("story", {"place": "home", "phase": "stay", "acting": "-"}), ("places", "home")], since=0)
# goodbye: the visited session's record is gone (stale): he waves it off, then moves on (home, nobody waits).
fx("goodbye", "goodbye", J, {}, [rec(J - 700000)],
   [("home-has", ["jeb-wave"], ["jeb-banjo"]), ("story", {"place": "camp:fx00", "phase": "leave", "to": "home", "reason": "ended"}), ("places", "camp")],
   place="fx00", since=300)
# home-default: busy sessions and no call: he stays home acting out the busiest (fx02, reading), though the first is the idle fx00.
fx("home-default", "home", J, {}, [rec(J - 8000), rec(J - 4000, pose="edit", busy=True, mood="working"), rec(J - 2000, pose="read", busy=True, mood="working")],
   [("home-has", ["jeb-book"], ["jeb-banjo"]), ("scene-count", JEB, 1), ("scene-count", BLUE, 1),
    ("story", {"place": "home", "phase": "stay", "acting": "fx02", "queue": ""}), ("places", "home")], since=800)
# call-event: a happening at fx00 calls him out once the 5 minute home spell is up.
fx("call-event", "call", J, {}, [rec(J - 1000, event=ev("bells", 12, 60))],
   [("story", {"place": "home", "phase": "leave", "to": "fx00", "reason": "event", "queue": ""}), ("scene-count", JEB, 1), ("scene-count", BLUE, 1)], since=400)
# call-spell: a low call (hands) waits out the 15 minute home spell: at 5 minutes he is home with it queued; at 20 he goes.
fx("call-spell", "call", J, {}, [rec(J - 1000, hands=HANDS)],
   [("story", {"place": "home", "phase": "stay", "queue": "hands@fx00", "to": "-"}), ("places", "home")], since=300)
fx("call-spell-go", "call", J, {}, [rec(J - 1000, hands=HANDS)],
   [("story", {"place": "home", "phase": "leave", "to": "fx00", "reason": "hands", "queue": ""})], since=1200)
# fog (8.9): mist over the homestead's sky rows, the band's own pattern (a gap every third pixel, half and half elsewhere).
fx("fog", "8.9", J, {}, [rec(J, event=ev("fog", 40, 96))], [("mist", 40 // 8, 0, 250)])

# The backdrop: the ridges stand whole above the hillside, at home and at each camp's land, by season and at night.
JAN, JUL = ms(2027, 1, 13, 12), ms(2026, 7, 8, 12)
for nm, now, pl in (("ridges-home", D, "home"), ("ridges-jul", JUL, "home"), ("ridges-jan", JAN, "home"), ("ridges-night", N, "home"),
                    ("ridges-camp0", D, "fx00"), ("ridges-camp1", D, "fx01"), ("ridges-camp2", JAN, "fx02"), ("ridges-camp3", N, "fx03")):
    fx(nm, "backdrop", now, {}, [rec(now) for _ in range(4)], [("ridges",)], env={"JEB_ANIMS": "band"}, place=pl, since=800 if pl != "home" else None)

# Areas (the store's `areas` key): a record's `area` names one by its 8-hex key. Generic fixture text throughout.
AK = "a1b2c3d4"
def area(**k):
    a = {"v": 1, "made": "offline", "day": "2026-10-20", "seen": "2026-10-21", "name": "Test Area", "terrain": "creek", "palette": "moss", "weather": "fog",
         "mood": "gold", "motif": "bird", "props": ["lantern", "birdhouse", "puddle"], "lore": ["Plain test lore one.", "Plain test lore two."],
         "beats": [{"line": "Test beat one.", "prop": "lantern", "zone": "yard"}, {"line": "Test beat two.", "prop": None, "zone": "porch"},
                   {"line": "Test beat three.", "prop": "cloud", "zone": "sky"}]}
    a.update(k)
    return a
# area-camp: at a camp whose record names a read area, the land and the strip are the area's (the plain twin render differs in both).
fx("area-camp", "area", J, {}, [rec(J - 1000, area=AK)], [("area-theme",)], areas={AK: area()}, place="fx00", since=800)
# area-bad: every off-schema area is ignored whole (no theme, a picture identical to the plain twin's).
BAD = {"a1b2c3d4": area(terrain="swamp"), "a1b2c3d5": area(lore=["x" * 65, "ok line"]), "a1b2c3d6": area(lore=["see http://example.com/x", "ok line"]),
       "a1b2c3d7": area(props=["nosuchsprite", "lantern", "birdhouse"]), "A1B2C3D8": area(), "a1b2c3d": area(), "a1b2c3d9": area(extra="x"),
       "a1b2c3da": area(props=["lantern", "birdhouse", "puddle", "cloud", "cow"], beats=[{"line": "Beat a.", "prop": p, "zone": "yard"} for p in ("hen", "pup", "bell", "star")])}
fx("area-bad", "area", J, {}, [rec(J - 1000, area="a1b2c3d4")], [("area-plain",)], areas=BAD, place="fx00", since=800)
# area-trip: a call from a camp with a read area sends him there, the area named, its own lines used.
fx("area-trip", "area", J, {}, [rec(J - 1000, area=AK, event=ev("bells", 12, 60))], [("story", {"place": "home", "phase": "leave", "to": "fx00", "reason": "event", "area": AK, "arealines": "1"})],
   areas={AK: area()}, since=400)

CAMP_FIXTURES = {"hands", "workflow", "mates", "visit-arrive", "visit-deal", "visit-opal", "visit-tractor", "visit-mail", "ev-neighbor", "ev-neighbor-walk",
                 "cows", "rain", "rain-all", "dry"}
for f in F:
    if f["name"] in CAMP_FIXTURES: f["place"] = "fx00"


def store_of(f):
    """The store a fixture draws from (and its farm)."""
    farm = copy.deepcopy(BASE)
    farm.update(copy.deepcopy(f["farm"]))
    store = {"farm": farm}
    for i, r in enumerate(f["live"]):
        store[f"live:fx{i:02d}"] = r
    if f.get("areas") is not None: store["areas"] = f["areas"]
    return store, farm


def gen():
    os.makedirs(FIX, exist_ok=True)
    out = []
    for f in F:
        store, farm = store_of(f)
        json.dump(store, open(os.path.join(FIX, f["name"] + ".store.json"), "w"))
        out.append({"name": f["name"], "now": f["now"], "farm": farm, "live": f["live"]})
    test = os.path.join(HERE, "modcopy", "tests", "zz-parity.test.tsx")
    if not os.path.isdir(os.path.dirname(test)):
        print(f"{len(F)} fixtures; stores written, no {os.path.dirname(test)} (make a modcopy to write the band's test)")
        return
    with open(test, "w") as t:
        t.write(TEST.replace("__FIXTURES__", json.dumps(out)).replace("__COLS__", str(COLS)))
    print(f"{len(F)} fixtures; test at {test}")


TEST = r"""// Scratch parity test (in a COPY of the mod): the band's own pixels for each desktop fixture.
import { test } from 'claude-code/testing'
import type { Anim } from '../types'
import { viewOf } from '../hooks/scene'
import { composeScene, hashOf, HAND_LOOKS } from '../hooks/pixel-scene'
import { isNightHour } from '../hooks/almanac'
import { BUILDINGS } from '../hooks/workday'

const FIXTURES: any[] = __FIXTURES__

const idFor = (look: number) => {
  for (let i = 0; ; i += 1) {
    const id = `agent-${i}`
    if (hashOf(id) % HAND_LOOKS === look) return id
  }
}

const animOf = (r: any, now: Date, lanterns: number): Anim => ({
  frame: r.frame, idleAct: r.act ?? 'banjo', pose: r.pose ?? 'none', truck: r.truck ?? null, visit: r.visit ?? null,
  dogRun: r.dogRun ?? 0, isNight: isNightHour(now.getHours()), isDim: r.dim === true, isTalking: typeof r.line === 'string',
  event: r.event ?? null, wag: (r.fx ?? []).includes('wag'), wink: (r.fx ?? []).includes('wink'), puff: (r.fx ?? []).includes('puff'),
  sip: (r.fx ?? []).includes('sip'), hands: (r.hands ?? []).map((h: any) => ({ plot: h.plot, id: idFor(h.look) })), more: r.more ?? {},
  mates: r.mates ?? 0, lanterns, isGated: r.gated === true, prop: '', weather: r.weather ?? { kind: 'none', plot: 'all' },
  building: r.building ? BUILDINGS[r.building] : '', cows: (r.cows ?? []).map((n: number) => `#${n}`), moreCows: r.moreCows ?? 0,
  stitch: r.stitch === true, live: r.live ?? 'N', rainbow: r.rainbow === true, wet: r.wet === true, star: r.star ?? 0,
} as Anim)

test('band pixels for the desktop parity fixtures', () => {
  for (const f of FIXTURES) {
    const now = new Date(f.now)
    const r = f.live[0] ?? { v: 1, at: f.now, frame: 0 }
    const anim = animOf(r, now, Math.max(0, f.live.length - 1))
    const { rgba, width, height } = composeScene({ farm: viewOf(f.farm), anim, mood: r.mood ?? 'idle', now, line: r.line ?? '', isDim: r.dim === true }, __COLS__)
    console.log(`FIX ${f.name} ${width} ${height} ${rgba.toBase64()}`)
  }
})
"""


def detect(image, queries, need=0.9):
    env = dict(os.environ, DETECT_NEED=str(need))
    res = subprocess.run([os.path.join(HERE, "tools", "detect"), ART, image] + queries, capture_output=True, text=True, env=env)
    out = []
    for line in res.stdout.splitlines():
        parts = line.rsplit(" ", 5)
        out.append((parts[0], int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]), float(parts[5])))
    return out


def best(matches, family):
    """Among overlapping matches of one family (Jeb's sprites, Blue's), the best name only."""
    keep = []
    for m in sorted(matches, key=lambda m: -m[5]):
        if m[0] in family and any(k[0] in family and abs(k[3] - m[3]) < 6 and abs(k[4] - m[4]) < 6 for k in keep):
            continue
        keep.append(m)
    return keep


def compare(band_out):
    band = {}
    for line in open(band_out):
        m = re.search(r"FIX (\S+) (\d+) (\d+) (\S+)", line)
        if m:
            band[m.group(1)] = (int(m.group(2)), int(m.group(3)), m.group(4))
    os.makedirs(os.path.join(FIX, "out"), exist_ok=True)
    def one(f):
        name = f["name"]
        needs_band = any(c[0] not in DESK_ONLY for c in f["checks"])
        if name not in band and needs_band:
            return (name, f["rows"], "n/a", "no band render")
        braw = os.path.join(FIX, "out", name + ".band.raw")
        w = 0
        if name in band:
            w, h, b64 = band[name]
            open(braw, "w").write(f"{w} {h} {b64}")
        png = os.path.join(FIX, "out", name + ".desk.png")
        env = dict(os.environ, JEB_BENCH="0.01", JEB_BENCH_FREEZE="1", JEB_BENCH_SCALE="1", JEB_BENCH_PNG=png, JEB_BENCH_STORY="1", JEB_STORE_PATH=os.path.join(FIX, name + ".store.json"),
                   JEB_NOW=str(f["now"]), JEB_PLACE=f["place"], **f["env"])
        if f["since"] is not None: env["JEB_PLACE_SINCE"] = str(f["since"])
        geo = subprocess.run([os.path.join(HERE, os.environ.get("JEB_BIN", "JebDesktop"))], capture_output=True, text=True, env=env).stdout
        g = re.search(r"geometry scene (\d+) (\d+) farm (\d+) (\d+) (\d+) place (\S+) roots (\d+) farm (\d+) camp (\d+) road (\d+)", geo)
        SW, SH, fxo, road, fw = map(int, g.groups()[:5])
        kind = g.group(6)
        roots, nfarm, ncamp, nroad = map(int, g.groups()[6:10])
        st = re.search(r"step t=\S+ start cast=(\d+)/(\d+) tree=(\d+)/(\d+) .*? place=(\S+) phase=(\S+) queue=(\S*) to=(\S+) reason=(\S+) acting=(\S+)", geo)
        story = dict(zip(("jeb", "blue", "jebAll", "blueAll", "place", "phase", "queue", "to", "reason", "acting"), st.groups())) if st else {}
        ar = re.search(r" area=(\S+) arealines=(\d) ", geo)
        if ar: story.update(area=ar.group(1), arealines=ar.group(2))
        at = re.search(r"area theme (\d) placed (\d+)", geo)
        # Every fixture: one place root, only that place's strip, at most one Jeb and one Blue (in the tree too).
        wantStrips = {"home": (1, 0, 0), "camp": (0, 1, 0), "road": (0, 0, 1)}[kind]
        notes0 = []
        if roots != 1 or (nfarm, ncamp, nroad) != wantStrips or not story or int(story["jeb"]) > 1 or int(story["blue"]) > 1 or int(story["jebAll"]) > 1 or int(story["blueAll"]) > 1:
            ok0 = False
        else:
            ok0 = True
        notes0.append(f"place {kind}: {roots} root, strips farm {nfarm} camp {ncamp} road {nroad}, cast {story.get('jeb')}/{story.get('blue')} (tree {story.get('jebAll')}/{story.get('blueAll')})")
        # Regions in the desktop picture (top-down): the stage strip; at a camp the camp's patch and Jeb stand where the farm's do.
        farm_top = SH - road - 48
        camp_x, camp_top, cw = fxo, farm_top, fw
        band_jeb = (w - 51 - 40 - 22, 0)
        home_jeb = (fxo + fw - 113, farm_top)  # the one Jeb of the scene, at either place
        camp_jeb = home_jeb
        blue_x = band_jeb[0] - 20
        sun = (max(4, min(w - 12, blue_x - 44)), 2)
        # The band's own Jeb-and-Blue corner (they live at the camps here), and its sun or moon (in the sky here).
        def band_farm_ok(m):
            q, fr, x, y = m
            sw, sh = SIZES.get(q, (8, 8))
            if x < 0 or x + sw > w: return False
            if blue_x - 16 <= x + sw and x < band_jeb[0] + 22 and q not in ("truck-empty", "truck-bales", "truck-crate", "truck-jars", "truck-apples", "truck-corn", "dust", "icon-cash", "icon-apple_butter", "icon-twist", "icon-whiskey", "revenuer", "turkey", "blue-wag"): return False
            if sun[0] - 2 <= x <= sun[0] + 9 and y <= 11 and sw <= 9: return False
            return True
        notes, ok = notes0, ok0
        kind0 = kind
        for check in f["checks"]:
            kind = check[0]
            if kind in ("farm", "camp", "home"):
                qs = check[1]
                need = 0.9 if kind == "farm" else 0.97
                bm, dm = detect(braw, qs, need), detect(png, qs, need)
                bm, dm = best(bm, JEB), best(dm, JEB)
                bm, dm = best(bm, BLUE), best(dm, BLUE)
                if kind == "farm":
                    bs = {(q, fr, x, y) for q, fr, fl, x, y, s in bm}
                    ds = {(q, fr, x - fxo, y - farm_top) for q, fr, fl, x, y, s in dm if fxo - 20 <= x < fxo + fw + 20 and farm_top - 2 <= y < farm_top + 48}
                    bs = {m for m in bs if band_farm_ok(m)}
                    ds = {m for m in ds if band_farm_ok(m)}
                elif kind == "home":
                    reach = check[2] if len(check) > 2 else 70
                    bs = {(q, fr, x - band_jeb[0], y - band_jeb[1]) for q, fr, fl, x, y, s in bm if band_jeb[0] - reach <= x < band_jeb[0] + 40}
                    ds = {(q, fr, x - home_jeb[0], y - home_jeb[1]) for q, fr, fl, x, y, s in dm if home_jeb[0] - reach <= x < fxo + fw and farm_top - 2 <= y < farm_top + 48}
                else:
                    reach = check[2] if len(check) > 2 else 70
                    bs = {(q, fr, x - band_jeb[0], y - band_jeb[1]) for q, fr, fl, x, y, s in bm if band_jeb[0] - reach <= x < band_jeb[0] + 40}
                    ds = {(q, fr, x - camp_jeb[0], y - camp_jeb[1]) for q, fr, fl, x, y, s in dm if camp_jeb[0] - reach <= x < camp_x + cw and camp_top - 2 <= y < camp_top + 48}
                if bs != ds:
                    ok = False
                    notes.append(f"{kind}: band-only {sorted(bs - ds)} desktop-only {sorted(ds - bs)}")
                else:
                    notes.append(f"{kind}: {len(bs)} match")
            elif kind == "home-has":
                # Desktop only: what the homestead's Jeb shows (these sprites and text there, those not).
                want, not_want = check[1], check[2]
                dm = best(best(detect(png, want + not_want, 0.97), JEB), BLUE)
                got = {m[0] for m in dm if home_jeb[0] - 200 <= m[3] < fxo + fw and farm_top - 2 <= m[4] < farm_top + 48}
                missing, extra = [q for q in want if q not in got], [q for q in not_want if q in got]
                if missing or extra: ok = False
                notes.append("home-has: " + ("ok" if not (missing or extra) else f"missing {missing} unwanted {extra}"))
            elif kind == "scene-count":
                # Desktop only: how many of a family (Jeb's sprites, Blue's) the whole scene draws.
                fam = check[1]
                n = len(best(detect(png, fam, 0.97), fam))
                if n != check[2]: ok = False
                notes.append(f"scene-count {fam[0].split('-')[0]}: {n} (want {check[2]})")
            elif kind == "absent":
                # Desktop only: none of these anywhere in the scene (what the other sessions bring is not drawn).
                found = [m[0] for m in detect(png, check[1], 0.9)]
                if found: ok = False
                notes.append("absent: " + ("ok" if not found else f"found {sorted(set(found))}"))
            elif kind == "story":
                # Desktop only: the story's state as the bench reports it (place, phase, queue, destination, reason).
                bad = {k: (story.get(k), v) for k, v in check[1].items() if story.get(k, "") != v}
                if bad: ok = False
                notes.append("story: " + ("ok" if not bad else f"got/want {bad}"))
            elif kind in ("area-theme", "area-plain"):
                # Desktop only: a camp with a read area draws it (theme on, sprites placed, land and strip unlike the plain twin's);
                # one whose area does not read is drawn plain (theme off, the same picture as the twin's, and the same again on a re-render).
                themed, placed = (int(at.group(1)), int(at.group(2))) if at else (-1, -1)
                twin = os.path.join(FIX, "out", name + ".plain.store.json")
                st0 = json.load(open(os.path.join(FIX, name + ".store.json")))
                st0.pop("areas", None)
                for k0, v0 in st0.items():
                    if k0.startswith("live:"): v0.pop("area", None)
                json.dump(st0, open(twin, "w"))
                png2, png3 = png[:-4] + ".plain.png", png[:-4] + ".again.png"
                for store_path, out_png in ((twin, png2), (os.path.join(FIX, name + ".store.json"), png3)):
                    subprocess.run([os.path.join(HERE, os.environ.get("JEB_BIN", "JebDesktop"))], capture_output=True, text=True, env=dict(env, JEB_STORE_PATH=store_path, JEB_BENCH_PNG=out_png))
                same_again = open(png, "rb").read() == open(png3, "rb").read()
                a, b = png_words(png), png_words(png2)
                land = sum(a[y * SW + x] != b[y * SW + x] for y in range(farm_top - 10, farm_top) for x in range(SW))
                strip = sum(a[y * SW + x] != b[y * SW + x] for y in range(farm_top, farm_top + 48) for x in range(fxo, fxo + fw))
                if kind == "area-theme":
                    good = themed == 1 and placed > 0 and land > 0 and strip > 0 and same_again
                else:
                    good = themed == 0 and placed == 0 and land == 0 and strip == 0 and open(png, "rb").read() == open(png2, "rb").read() and same_again
                if not good: ok = False
                notes.append(f"{kind}: theme {themed} placed {placed}, land rows differ {land}, strip differs {strip}, same again {same_again}")
            elif kind == "places":
                if kind0 != check[1]: ok = False
                notes.append(f"places: {kind0} (want {check[1]})")
            elif kind == "ridges":
                # The far ridge's flat colour fills a band of rows (14..24 above the stage strip) across the
                # whole picture: no hillside, speckle or pine tips reach up over the ridges.
                px = png_words(png)
                rows = range(SH - (road + 48 + 24), SH - (road + 48 + 14) + 1)
                band_px = [px[y * SW + x] for y in rows for x in range(SW)]
                top_colour = max(set(band_px), key=band_px.count)
                frac = band_px.count(top_colour) / len(band_px)
                if frac < 0.97: ok = False
                notes.append(f"ridges: {100 * frac:.1f}% of the ridge band one flat colour")
            elif kind == "mist":
                # The fog's pattern over the homestead's sky rows (and the band's own, when its render is there).
                _, t8, x0, x1 = check
                good = []
                good.append(("desktop", mist_ok(png_words(png), SW, fxo, farm_top, t8, x0, x1)))
                if w: good.append(("band", mist_ok(pixel_words(braw), w, 0, 0, t8, x0, x1)))
                for who, frac in good:
                    if frac < 0.9: ok = False
                notes.append("mist: " + ", ".join(f"{who} {100 * frac:.0f}%" for who, frac in good))
            elif kind == "count":
                q, n = check[1], check[2]
                bm, dm = detect(braw, [q], 0.9), detect(png, [q], 0.9)
                dcamp = [m for m in dm if camp_x - 10 <= m[3] < camp_x + cw and camp_top - 10 <= m[4] < camp_top + 48]
                dfarm = [m for m in dm if fxo - 20 <= m[3] < fxo + fw and farm_top - 20 <= m[4] < farm_top + 48]
                dn = max(len(dcamp), len(dfarm))
                if n is None:  # as many as fit: at least one in each
                    if len(bm) == 0 or dn == 0: ok = False
                elif len(bm) != n or dn != n:
                    ok = False
                notes.append(f"count {q}: band {len(bm)} desktop {dn}" + (f" (want {n})" if n is not None else " (as fit)"))
            elif kind == "text":
                q = check[1]
                bn, dn = len(detect(braw, [q], 1.0)), len(detect(png, [q], 1.0))
                if bn == 0 or dn == 0: ok = False
                notes.append(f"text {q}: band {bn} desktop {dn}")
            elif kind == "lanterns":
                bn = len(detect(braw, ["lantern"], 0.9))
                dm = detect(png, ["lantern"], 0.9)
                dn = len([m for m in dm if fxo <= m[3] < fxo + fw and farm_top <= m[4] < farm_top + 48])
                # The band lights one for each OTHER session; the homestead one for each session but the one acted out here.
                if dn != bn: ok = False
                notes.append(f"lanterns: band {bn} (others) desktop {dn}")
            elif kind == "bubble":
                # The bubble: the band's own wrap at the room each has (the band's is cut short by the
                # sign; the homestead's, with the one Jeb, has the full 30), its box's right edge at Jeb - 1, text 3 in, 3 down.
                line = f["live"][0]["line"]
                ink = "grey" if check[1] else "ink"
                verdict = []
                for img, jx, top, chars in ((braw, band_jeb[0], 0, None), (png, home_jeb[0], farm_top, 30)):
                    tries = [chars] if chars else list(range(30, 7, -1))
                    good = False
                    for c in tries:
                        lines = bubble_lines(line, c)
                        tw = max(len(l) * 4 - 1 for l in lines)
                        want_x = jx - 1 - (tw + 6) + 3
                        hits = [detect(img, [f"text:{ink}:{l}"], 1.0) for l in lines]
                        if all(any(m[3] == want_x and m[4] == top + 4 + i * 6 for m in hs) for i, hs in enumerate(hits)):
                            good = True; verdict.append(f"{c} chars {lines}"); break
                    ok = ok and good
                    if not good: verdict.append("not found")
                notes.append("bubble: band " + verdict[0] + "; desktop " + (verdict[1] if len(verdict) > 1 else "-"))
            elif kind == "pixels":
                # The farm's pixels themselves: every opaque band pixel in the box the same on the homestead.
                x0, y0, x1, y1 = check[1:]
                bpx = pixel_words(braw)
                dpx = png_words(png)
                back = band_backdrop(w, f["now"], f["farm"])
                same = total = 0
                for y in range(y0, y1):
                    for x in range(x0, x1):
                        b = bpx[y * w + x]
                        if b < 0 or b == back[y * w + x]: continue
                        total += 1
                        same += dpx[(farm_top + y) * SW + fxo + x] == b
                frac = same / max(1, total)
                ok = ok and frac >= 0.97
                notes.append(f"pixels {x0},{y0}-{x1},{y1}: {100 * frac:.1f}% of {total} the same")
            elif kind == "tint":
                name, rgb = check[1], check[2]
                c = art_colour(name)
                t = ((c & 255) * 3 + rgb[0]) >> 2 | (((c >> 8 & 255) * 3 + rgb[1]) >> 2) << 8 | (((c >> 16 & 255) * 3 + rgb[2]) >> 2) << 16
                bn = sum(1 for v in pixel_words(braw) if v == t)
                dn = sum(1 for v in png_words(png) if v == t)
                ok = ok and bn > 0 and dn > 0
                notes.append(f"tinted {name}: band {bn} px, desktop {dn} px")
            elif kind in ("lane", "walk"):
                # Along the way: the same progress along each one's own lane (the camp lane is shorter).
                q = check[1]
                dm = [m for m in detect(png, [q], 0.9) if camp_x - 60 <= m[3] < camp_x + cw and camp_top - 2 <= m[4] < camp_top + 48]
                bm = detect(braw, [q], 0.9)
                if kind == "lane":
                    _, _, x, reach, sw, flip = check
                    bstop, dstop = band_jeb[0] - 20 - (sw if sw == 14 else 40) - 6, (fw - 113 - 20) - (sw if sw == 14 else 40) - 6
                    bx = round(-sw + (bstop + sw) * x / reach); dx = round(-sw + (dstop + sw) * x / reach) + camp_x
                else:
                    p = check[2]
                    bx = round(p / 0.5 * (band_jeb[0] - 18)); dx = round(p / 0.5 * (fw - 113 - 18)) + camp_x
                bh = [m for m in bm if abs(m[3] - bx) <= 1]; dh = [m for m in dm if abs(m[3] - dx) <= 2]
                ok = ok and len(bh) >= 1 and len(dh) >= 1 and bh[0][2] == dh[0][2]
                notes.append(f"{q} along the way: band at {bx} {'found' if bh else 'missing'}, desktop at {dx - camp_x} {'found' if dh else 'missing'}")
            elif kind == "dry":
                bpx = pixel_words(braw)
                dry = art_colour("soil_dry")
                bn = sum(1 for y in range(37, 40) for x in range(w) if bpx[y * w + x] == dry)
                dpx = png_words(png)
                dn = sum(1 for y in range(camp_top + 37, camp_top + 40) for x in range(camp_x + 4, camp_x + 24) if dpx[y * SW + x] == dry)
                ok = ok and bn > 0 and dn > 0
                notes.append(f"band soil_dry pixels {bn}, camp tobacco soil_dry pixels {dn}")
        return (name, f["rows"], "pass" if ok else "FAIL", "; ".join(notes))
    with ThreadPoolExecutor(min(8, os.cpu_count() or 4)) as pool: results = list(pool.map(one, F))
    for r in results:
        print(f"{r[2]:5} {r[0]:18} [{r[1]}] {r[3]}")
    print(f"-- {sum(1 for r in results if r[2] == 'pass')} of {len(results)} fixtures pass")
    json.dump(results, open(os.path.join(FIX, "out", "results.json"), "w"), indent=1)


def bubble_lines(line, chars=30):
    q = line.split()
    cut = lambda w: w[: max(0, chars - 2)] + ".."
    lines = [""]
    while q:
        w = q.pop(0); cur = lines[-1]
        if len(lines) == 1 and cur == "" and len(w) > chars:
            lines[0] = w[:chars]; q.insert(0, w[chars:]); lines.append(""); continue
        nxt = f"{cur} {w}" if cur else w
        if len(nxt) <= chars: lines[-1] = nxt
        elif len(lines) < 2:
            lines.append(cut(w) if len(w) > chars else w)
            if len(w) > chars: break
        elif cur == "": lines[1] = cut(w); break
        else:
            lines[1] = (cur if len(cur) + 2 <= chars else cur[: chars - 2]).rstrip() + ".."; break
    return [l for l in lines if l]


def band_backdrop(w, now_ms, farm):
    """The band's ridges and road (pixel-scene.ts paintBackdrop, paintRoad), to tell its sprites from its backdrop."""
    import math
    t = time.localtime(now_ms / 1000)
    m, hour = t.tm_mon - 1, t.tm_hour
    night = hour >= 21 or hour < 6
    season = "winter" if m <= 1 or m == 11 else "spring" if m <= 4 else "summer" if m <= 7 else "fall"
    peak = season == "fall" and m == 9
    morning = not night and 6 <= hour < 9
    col = art_colour
    H = 48; G = H - 9
    px = [-1] * (w * H)
    sp = lambda x, y: (((x * 73856093) ^ (y * 19349663)) & 0xffffffff) % 100
    far_r = lambda x: round(15 + 4 * math.sin(x / 37) + 3 * math.sin(x / 13 + 1.3) + 2 * math.sin(x / 71 + 0.4))
    mid_r = lambda x: round(28 + 2 * math.sin(x / 23 + 2) + 1 * math.sin(x / 9) + 1.5 * math.sin(x / 51 + 1))
    FOL = [col("foliage_orange"), col("foliage_red"), col("foliage_gold")]
    for x in range(w):
        far = max(6, min(G - 6, far_r(x))); mid = max(far + 4, min(G - 2, mid_r(x)))
        for y in range(far, G): px[y * w + x] = col("ridge_far_night" if night else "ridge_far")
        if season == "winter" and far <= 13:
            px[far * w + x] = col("snowcap")
            if far <= 10: px[(far + 1) * w + x] = col("snowcap")
        for y in range(mid, G):
            word = col("ridge_mid_night" if night else "ridge_mid"); roll = sp(x, y)
            if not night:
                if season == "fall" and roll < (20 if peak else 10): word = FOL[roll % 3]
                elif season == "spring" and roll < 12: word = col("leaf")
                elif season == "summer" and roll < 15: word = col("pine")
            px[y * w + x] = word
        if sp(x, 7) < 18 and mid - 2 > far:
            tip = col("ridge_mid_night") if night else col("snowcap") if season == "winter" else col("pine")
            px[(mid - 1) * w + x] = tip
            if sp(x, 11) < 50: px[(mid - 2) * w + x] = tip
        if season == "winter" and not night and sp(x, 3) < 30: px[mid * w + x] = col("snowcap")
        if morning and (x + x // 9) % 3 != 0: px[(G - 2) * w + x] = col("fog")
    rut = lambda x, k: max(-1, min(1, round(math.sin(x / 7 + k * 2.1) + 0.6 * math.sin(x / 3.3 + k))))
    for x in range(w):
        px[G * w + x] = col("grass")
        for y in range(G + 1, H):
            roll = sp(x, y + 200)
            px[y * w + x] = col("dirt_light") if roll < 9 else col("dirt_dark") if roll < 15 else col("dirt")
        px[(42 + rut(x, 0)) * w + x] = col("dirt_dark")
        px[(46 + rut(x, 1)) * w + x] = col("dirt_dark")
        if sp(x, 77) < 3:
            y = G + 1 + sp(x, 78) % 8
            px[y * w + x] = col("pebble")
            if sp(x, 79) < 45 and x + 1 < w: px[y * w + x + 1] = col("pebble")
        if sp(x, 5) < 8:
            px[(G - 1) * w + x] = col("grass")
            if sp(x, 6) < 50: px[(G - 2) * w + x] = col("leaf")
    return px


DESK_ONLY = ("home-has", "scene-count", "mist", "absent", "story", "places", "ridges", "area-theme", "area-plain")


def mist_ok(px, W, ox, oy, t8, x0, x1):
    """Share of fogged pixels (rows 2..17, the open sky above the crops; columns x0..x1 of a strip at (ox, oy) in a picture
    W wide) that are the half-and-half mix of the mist colour over one of the gap pixels (where the pattern leaves
    a gap) within eight columns of it in the same row: the ground behind is speckled, so a near one, not the next."""
    mist = (215, 222, 232)
    rgb = lambda a: (a & 255, a >> 8 & 255, a >> 16 & 255)
    good = total = 0
    for y in range(2, 18):
        for x in range(x0 + 8, x1 - 8):
            if (x + y + t8) % 3 == 0: continue
            a = px[(oy + y) * W + ox + x]
            if a < 0: continue
            total += 1
            wants = [tuple((u + m) // 2 for u, m in zip(rgb(px[(oy + y) * W + ox + k]), mist)) for k in range(x - 8, x + 9)
                     if (k + y + t8) % 3 == 0 and px[(oy + y) * W + ox + k] >= 0]
            good += any(all(abs(c - d) <= 3 for c, d in zip(w, rgb(a))) for w in wants)
    return good / max(1, total)


def png_words(path):
    # The desktop render as colour words (via the detector's own PNG reader would need Swift; sips to raw).
    out = path + ".rgba"
    if not os.path.exists(out) or os.path.getmtime(out) < os.path.getmtime(path):
        subprocess.run([os.path.join(HERE, "tools", "png2raw"), path, out], check=True)
    data = open(out, "rb").read()
    return [(data[i] | data[i + 1] << 8 | data[i + 2] << 16) if data[i + 3] else -1 for i in range(0, len(data), 4)]


def sizes():
    text = open(ART).read()
    return {m.group(1): (int(m.group(2)), int(m.group(3))) for m in re.finditer(r"^  '([^']+)': \{ w: (\d+), h: (\d+)", text, re.M)}
SIZES = sizes()


def pixel_words(raw):
    import base64
    w, h, b = open(raw).read().split(" ")
    data = base64.b64decode(b)
    return [(data[i * 4] | data[i * 4 + 1] << 8 | data[i * 4 + 2] << 16) if data[i * 4 + 3] else -1 for i in range(int(w) * int(h))]


def art_colour(name):
    text = open(ART).read()
    pal = json.loads(re.search(r"PIXEL_PALETTE: readonly number\[\] = (.*)", text).group(1))
    cols = json.loads(re.search(r"PIXEL_COLOUR: Readonly<Record<string, number>> = (.*)", text).group(1))
    rgb = pal[cols[name]]
    return (rgb >> 16 & 255) | (rgb >> 8 & 255) << 8 | (rgb & 255) << 16


if __name__ == "__main__":
    if sys.argv[1] == "gen": gen()
    else: compare(sys.argv[2])
