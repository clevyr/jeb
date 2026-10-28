#!/usr/bin/python3 -I
"""status.py: writes parity-status.md from the rows below and the last fixture results."""
import json, os, re
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
R = json.load(open(os.path.join(HERE, "fixtures", "out", "results.json")))
verified = {}
for name, rows, verdict, notes in R:
    for row in rows.split():
        verified.setdefault(row, []).append((name, verdict))

D, P, N = "done", "partial", "n/a"
AREAS = [
 ("1 Sky, backdrop and calendar", [
  ("1.1", "Sun by day", D, "on the stage's sky arc (the desktop's own place, by design), by the same hours"),
  ("1.2", "Moon by night with phase", D, "same synodic formula and frame per phase, on the sky arc"),
  ("1.3", "Night stars", D, "scattered over the open sky, a few twinkling on the 10 Hz grid"),
  ("1.4", "Night fireflies (ambient)", D, "the band's four fixed spots in the homestead strip, under the farm as on the band"),
  ("1.5", "Two ridgelines", D, "far hills in the sky's haze and the near hillside, night colours"),
  ("1.6", "Season speckle on the near ridge", D, "season speckle and snowcaps on the hillside (lighter density for its size)"),
  ("1.7", "Morning fog in the hollows", D, "06:00-08:59 fog pixels along the homestead's grass"),
  ("1.8", "Dirt road and grass strip", D, "the road of the one place on screen (homestead, visited camp, or the road between): speckle, ruts, pebbles, tufts"),
  ("1.9", "Christmas week", D, "tree by the house; sky snow ported dot for dot as frame-driven layers"),
  ("1.10", "Pumpkin days", D, "pumpkin trees and the sign's pumpkin"),
  ("1.11", "Thanksgiving", D, "turkey by the still, two frames"),
  ("1.12", "Groundhog Day", D, "five frames in eight, under the still as on the band"),
  ("1.13", "Date greeting lines", D, "the visited session's line from its record, in the bubble at the place he is at"),
  ("1.14", "Almanac data", N, "text replies and hint crumbs in the terminal; nothing drawn"),
 ]),
 ("2 Farm and crops", [
  ("2.1", "Three plots", D, "the band's layoutOf at the same width: identical positions"),
  ("2.2", "Crop growth", D, "stages read from the farm on every store change"),
  ("2.3", "Harvest", D, "the reset stages come from the farm; the line shows in the bubble at the place he is at"),
  ("2.4", "Plot labels with counts", D, "same text, same abbreviations"),
  ("2.5", "+N extra-hands label", D, "yellow +N on the crop at the place he is at"),
  ("2.6", "Fenced fields", D, "fence every 8 px along each plot"),
  ("2.7", "Whistle-pig raid", D, "the corn stage comes from the farm; the groundhog is drawn from the record"),
  ("2.8", "Test-run rain over a plot", D, "cloud and drops over that crop (or all three) at the place he is at, from the visited record"),
  ("2.9", "Test-run dry spell", D, "soil_dry on that crop at the place he is at"),
  ("2.10", "Straw, lumber, stone, iron from work", D, "through the stack"),
 ]),
 ("3 Homestead, still and yard", [
  ("3.1", "House", D, "four variants by coat and night"),
  ("3.2", "Chimney smoke", D, "rising, growing, fading puffs on the calm grid (the desktop's ambience for the 3-frame sprite)"),
  ("3.3", "Mailbox", D, "with the upgrade"),
  ("3.4", "Still variants", D, "worm, keg, both; tarp while a session's revenuer is under 85%"),
  ("3.5", "Still fire and steam", D, "at the place he is at while the visited record's pose is still"),
  ("3.6", "Jars on the shelf and cash", D, "same icons, counts and fit rule"),
  ("3.7", "Batch progress (mash)", N, "not drawn in the pixel band"),
  ("3.8", "Second still", D, "half size right of the sign"),
  ("3.9", "Rocking chair", D, "at the place on screen while Jeb sits or is away"),
  ("3.10", "Hen", D, "wanders the homestead yard while he is home; chased at the place he is at when the visited record's idle act is chase"),
  ("3.11", "Pup", P, "follows the one Blue at the place he is at (home or a camp); no fixture yet checks it following Blue on his errand or chase"),
  ("3.12", "Upgrades by earnings", D, "drawn from the farm; the line in a bubble (the toast is terminal chrome)"),
  ("3.13", "Milestones", N, "terminal toasts only"),
  ("3.14", "Crafted builds", D, "still variants, smokehouse, fence"),
 ]),
 ("4 Jeb and Blue", [
  ("4.1", "Jeb sprite choice (priority order)", D, "jebSpriteFor ported rule for rule, for the one Jeb at the place on screen"),
  ("4.2", "Tool poses", D, "from the record's pose"),
  ("4.3", "Mood sticks with the last line", D, "from the record's mood"),
  ("4.4", "Idle rotation", D, "from the visited record's act (the mod decides it); at home, the record he last left until it goes quiet, then the calm idle"),
  ("4.5", "Sleep at night", D, "sleep, zz, Blue napping"),
  ("4.6", "Spooked sweat", D, "beside the head"),
  ("4.7", "Sip on /jeb sip", D, "sip fx, chair if built"),
  ("4.8", "Jeb away with the truck", D, "no Jeb at the place on screen, chair shown, the truck drawn at the place he is at"),
  ("4.9", "Blue's states", D, "wag, run, chase with the hen, bark, nap, riding in the truck"),
  ("4.10", "Blue's errand", D, "where the record puts him, running there over a tick between writes"),
  ("4.11", "Petting, wink and puff reactions", D, "heart, wink, truck warming up at the house"),
  ("4.12", "Prompt reaction lines", D, "the line from the record in the bubble"),
 ]),
 ("5 Hired hands and teammates", [
  ("5.1", "A hired hand in a plot", D, "in its crop at the place he is at, its look from the visited record"),
  ("5.2", "Workflow hands", D, "one in each crop and +N"),
  ("5.3", "Hand marker", N, "the terminal's transcript view; not in the live record"),
  ("5.4", "Hire line", D, "line in the bubble"),
  ("5.5", "Hand finishes", D, "hands go as the record drops them"),
  ("5.6", "Teammates at the sign", D, "at the camp's own sign spot while he visits it"),
 ]),
 ("6 Other sessions and lanterns", [
  ("6.1", "Heartbeat of each session", N, "the desktop never reads `sessions`; each live record is a session"),
  ("6.2", "A lantern for each live session", D, "on the homestead sign, a count of the other sessions, xN past four"),
  ("6.3", "Lantern greeting", D, "line in the bubble"),
  ("6.4", "Stitching a dead session", D, "stitch flash from the record, the square from the farm"),
 ]),
 ("7 Visitors and traffic", [
  ("7.1", "Truck delivery", D, "the visited session's truck at the place he is at, moved on from t at the band's pace; loads, icons, dog, dust, sputter"),
  ("7.2", "Sale at the end of the run", D, "the farm's numbers; the line in the bubble"),
  ("7.3", "Ambient visits", D, "on the visited camp's lane: same progress (visitAt) along a shorter lane, same stop short of Blue"),
  ("7.4", "Which visit", D, "the record's kind"),
  ("7.5", "Visit sale", D, "wave, bark, the line"),
  ("7.6", "Truck takes the road", D, "the mod ends the visit; the desktop draws what the record says"),
 ]),
 ("8 Happenings", [
  ("8.1", "Revenuer", D, "walks to the house, still tarped, Jeb salutes"),
  ("8.2", "Neighbour (Miss Opal)", D, "walks to Jeb, stands, walks back (same fractions of the run)"),
  ("8.3", "Bear", D, "in the orchard; bang over Blue only while the truck isn't away"),
  ("8.4", "Whistle pig", D, "in the corn at the place he is at, by the variant"),
  ("8.5", "Mothman", D, "over the orchard, hidden one sub-frame in eight"),
  ("8.6", "Lightning bugs", D, "five, scattered by the variant and t"),
  ("8.7", "Church bells", D, "bell and note by the house"),
  ("8.8", "Storm", D, "dark cloud and rain over the place he is at (by the house at home)"),
  ("8.9", "Fog", D, "mist over the homestead's sky rows (not covered by a fixture)"),
  ("8.10", "Wild turkeys", D, "two cross the road of the place he is at"),
  ("8.11", "Parachute day", D, "drifts down to the orchard"),
  ("8.12", "Blue's track", D, "bang over Blue for the first 70%, only while the truck isn't away"),
  ("8.13", "Hornworms", D, "Jeb spooked"),
  ("8.14", "Apple butter stirring", D, "Jeb stirring"),
 ]),
 ("9 Drops and surprises", [
  ("9.1", "Drop slots", N, "decided in the mod"),
  ("9.2", "Model budget", N, "decided in the mod"),
  ("9.3", "Happening (a drop kind)", D, "the record's event art, placed by the band's rule"),
  ("9.4", "Decor", D, "from the farm, by day and hour, at most eight"),
  ("9.5", "Structures", D, "from the farm"),
  ("9.6", "Sayings", D, "lines in the bubble"),
  ("9.7", "Almanac lines", N, "hint crumbs and text replies"),
  ("9.8", "Festival tint", D, "the land and roads a quarter toward the tint, sprites untouched"),
  ("9.9", "Placement rule", D, "zones, reserved boxes and the hashed first free spot, ported"),
  ("9.10", "Custom pictures", D, "legend to palette with the ink outline; strict shape and size checks"),
  ("9.11", "Multi-day arcs", D, "each step is decor, a structure or a happening, drawn as those"),
  ("9.12", "Announcement", D, "line in the bubble"),
  ("9.13", "Notice and tally", N, "text replies"),
 ]),
 ("10 Unlocks and looks", [
  ("10.1", "Daily plan", N, "decided in the mod"),
  ("10.2", "Unlocking", D, "the unlock comes in the farm; the hint line in the bubble"),
  ("10.3", "Looks on show", D, "looksOf ported: every look at its anchor, in order, kept out of Jeb's head"),
  ("10.4", "/jeb notice", N, "text reply"),
 ]),
 ("11 Bubble, talk dial and hush", [
  ("11.1", "Speech bubble", D, "8 s from saidAt, box and tail as the band, wrapped at the room it has (30 a line at a camp), at the place he is at"),
  ("11.2", "Dim bubble", D, "stone border, grey text"),
  ("11.3", "Talk dial", D, "decided in the mod; silent shows as the dim bubble"),
  ("11.4", "Hush after a failure", N, "decided in the mod (what gets said)"),
  ("11.5", "Cooldowns per line source", N, "decided in the mod"),
  ("11.6", "Live stream pose and line", D, "pose and line from each record write"),
  ("11.7", "Test-run lines", D, "line in the bubble"),
  ("11.8", "Lint lines", D, "line in the bubble, hoe pose"),
  ("11.9", "Compose building lines", D, "line in the bubble; the service's building at the place he is at"),
  ("11.10", "Deny lines", D, "line in the bubble; a gate in Jeb's hands"),
  ("11.11", "Session chores", D, "broom pose, lines"),
  ("11.12", "Greetings", D, "line in the bubble"),
  ("11.13", "Usage-limit line", D, "line in the bubble"),
  ("11.14", "Other lines", D, "line in the bubble"),
 ]),
 ("12 Economy readouts and the stack", [
  ("12.1", "Stack of stock", D, "five biggest columns, heights, 99+; the view's caps ported"),
  ("12.2", "Aging jars", D, "counted into whiskey when ready, by the clock"),
  ("12.3", "Smokehouse", D, "after the last column"),
  ("12.4", "Jars and cash", D, "see 3.6"),
  ("12.5", "Buyers and prices", N, "not drawn"),
  ("12.6", "Crafting and buying", D, "stack and still variants (keepsakes are not drawn on the band either)"),
  ("12.7", "/jeb tally, stack, craft", N, "text replies"),
 ]),
 ("13 Quilt and journal", [
  ("13.1", "Clothesline", D, "stitched squares on the rail, then one dim square per camp"),
  ("13.2", "Stitch flash", D, "the newest square flickers on the frame while a record's stitch is on"),
  ("13.3", "This session's square", D, "dim on the line, and on the camp's tent pole while he visits it"),
  ("13.4", "Stitching", D, "the farm's squares"),
  ("13.5", "/jeb quilt, journal", N, "text replies"),
  ("13.6", "Hint-line journal crumb", N, "terminal chrome"),
 ]),
 ("14 Animation, timing and still-life", [
  ("14.1", "The shared frame counter", D, "the scene follows the visited record's frame and at: every tick while moving, every 3 s calm, every second for the tractor"),
  ("14.2", "Redraw cadence", D, "frame changes as discrete keyframes at that cadence on the 10 Hz grid; no app work per frame"),
  ("14.3", "Still life", D, "a still record freezes the scene's frames"),
  ("14.4", "Activity that wakes it", D, "a new record wakes it"),
  ("14.5", "Short effects", D, "from the record's fx, gate, weather, stitch, star"),
  ("14.6", "Idle remark", D, "line in the bubble"),
  ("14.7", "Hidden band", D, "a hidden session is not drawn"),
 ]),
 ("15 Options, toggles and commands", [
  ("15.1", "Porch sounds", N, "audio, in the mod"),
  ("15.2", "Jeb's voice", N, "audio, in the mod"),
  ("15.3", "Do Not Disturb / Focus mute", N, "audio, in the mod"),
  ("15.4", "Flourishes", N, "terminal chrome"),
  ("15.5", "Pixel art option", N, "chooses the terminal band"),
  ("15.6", "Creativity toggle", N, "gates drops in the mod; the desktop draws what is stored"),
  ("15.7", "Hook reactions", D, "the gate, broom and lines from the record"),
  ("15.8", "Toasts", N, "terminal chrome"),
  ("15.9", "/jeb text commands", D, "pet and holler show as Blue's wag, sip as the sip; the rest are text"),
 ]),
 ("16 Terminal fallbacks", [
  ("16.1", "Compact quip", N, "terminal fallback"),
  ("16.2", "Emoji band", N, "terminal fallback (its gate and building glyphs are drawn as the gate and the building at the place he is at)"),
  ("16.3", "Pixel-band hiding", N, "terminal fallback"),
 ]),
 ("Story features (generic names)", [
  *[(f"A{i}", f"story feature {i}", D, "the happening's own Jeb pose at the place he is at") for i in range(1, 6)],
  *[(f"B{i}", f"story feature {i + 5}", D, "unlocks from the farm; shown through its looks") for i in range(1, 21)],
  *[(f"C{i}", f"story look {i}", D, "ported at its anchor and hours") for i in range(1, 25)],
 ]),
]

def ver(row):
    v = verified.get(row)
    if not v: return ""
    ok = all(x[1] == "pass" for x in v)
    return f" Verified ({', '.join(sorted(set(x[0] for x in v)))}): {'pass' if ok else 'FAIL'}."

out = ["# Desktop parity status (phase 3 and 5)", "",
       "Each row of the parity list, as the desktop draws it from the farm and the live records.",
       "Verified rows name the fixtures that check them (tools/parity.py: the band's own pixels from the mod copy's test sandbox",
       "against the desktop's CARenderer render of the same farm and live record).", ""]
summary = []
for area, rows in AREAS:
    out.append(f"## {area}")
    out.append("")
    out.append("| # | Feature | Status | Reason |")
    out.append("|---|---|---|---|")
    c = {D: 0, P: 0, N: 0}
    for num, name, st, why in rows:
        c[st] += 1
        out.append(f"| {num} | {name} | {st} | {why}.{ver(num)} |")
    out.append("")
    summary.append((area, c))
out.append("## Summary")
out.append("")
out.append("| Area | done | partial | n/a |")
out.append("|---|---|---|---|")
for area, c in summary:
    out.append(f"| {area} | {c[D]} | {c[P]} | {c[N]} |")
tot = {k: sum(c[k] for _, c in summary) for k in (D, P, N)}
out.append(f"| All | {tot[D]} | {tot[P]} | {tot[N]} |")
out.append("")
passed = sum(1 for r in R if r[2] == "pass")
out.append(f"Fixtures: {passed} of {len(R)} pass. Per fixture:")
out.append("")
for name, rows, verdict, notes in R:
    secret = any(r[0] in "ABC" and r[1:].isdigit() for r in rows.split())
    # The story rows' checks name what they draw: only their verdict here.
    out.append(f"- {name} [{rows if not secret else 'story rows'}]: {verdict}." + ("" if secret else f" {notes}"))
open(os.path.join(HERE, "parity-status.md"), "w").write("\n".join(out) + "\n")
for area, c in summary: print(area, c)
print("total", tot, f"fixtures {passed}/{len(R)}")

steps = """
## Summary of this build

One place at a time. The scene is the homestead, the camp of the session Jeb is visiting, or the road between during a trip; the whole scene changes with him and the old place's layers are removed (no shelves, slots or stacking). One Jeb and one Blue, at the place on screen. Everything the visited session's record brings plays at the place he is at; farm-wide things belong to the homestead. Sessions he is not at are not drawn and only join a FIFO queue (Story.swift: visit rules, trips with generated lines, a day's thread kept in story.json). Lanterns on the homestead sign still count the other sessions. Camp stand-ins and lead selection are gone; fixtures seed JEB_PLACE. All fixtures pass against a freshly regenerated band output, and the scripted-day bench passes. Other sessions visible while he is elsewhere is a recorded future enhancement, not built.

Phase 6 (2026-10-27): installed as ~/Applications/JebDesktop.app with three LaunchAgents (desktop with KeepAlive on a crash, watchdog every 30 s, updater on src changes). Every source change ships through the updater's four gates (smoke, parity, scripted day, 20 s headless start), then a heartbeat watch with rollback. Verified on the install: a killed app is back at once (launchd), a hung one in about 50 s (watchdog), Quit stays quit, a source change ships and is marked healthy, and a planted bad change in a scratch copy is rejected at parity.

Backdrop (2026-10-27): the near hillside sits just behind the stage, under the far ridge's lowest crest, so the ridges are no longer covered. The "ridges" check (8 desk-only fixtures: home by season and at night, camps on each land variant) requires the band 14 to 24 rows above the strip to be one flat ridge colour; the old hillside fails it at 87 to 94 percent.

Fixture determinism (2026-10-27): with JEB_BENCH_FREEZE the scene's world time stands still from its creation, so a flipbook's frame no longer depends on how long the build took. Before, truck-butter failed about 1 run in 10 under CPU load (a good build was rejected once at parity); after, 94 of 94 twice under full load.

## Next steps

- Track C (areas), mod side: done. Approved by the owner and synced into the live mod 2026-10-27 11:05 (7 files); 'hooks/areas.ts' is in the creative runner's PINNED_FILES.
- Track C, desktop side: done. The store reader takes the `areas` key (strictly read), a record's `area` names it, and a camp with a read area is drawn from it (land, hillside, sprites, the visit's lines); fixtures area-camp, area-bad and area-trip added. Shipped healthy as 20261028-095036-05e021d0 (the bundle carries `JebMod` in Info.plist).
- Performance re-measure: done 2026-10-27 on the installed build 20261027-143747-a0cc887e (meas/p3.txt): app CPU 0.02 to 0.25%, RSS 41 to 54 MB, footprint 12 to 20 MB, in line with the earlier baseline (0.07 to 0.28%, 40 to 61 MB, 15 to 18 MB); WindowServer tracks the paired no-Jeb runs. Since then the watchdog samples the app every 30 s (telemetry/YYYY-MM-DD.csv, heartbeat counters tRun/tPass/tCov/tPause classify each interval); `jebctl perf` summarizes by build and class against the targets, so perf.sh is kept for renderer changes.
- Long Space-gap run (runs/p3-live, 07:55 to 09:25 on 2026-10-27, the one-place build; watch stopped itself at 09:25:46): 32 switches into the desktop, 29 at 0 ms, 3 with a gap: 08:09:17 284 ms, 08:11:27 300 ms, 08:25:58 3300 ms (all three from iTerm, wallpaper showing). The 3.3 s one is unexplained; re-run `watch` on the installed app and compare.
- Phase 7 cut-over: done 2026-10-27. Jeb's in-terminal interface is gone; the mod only gathers and hands data to the desktop. Parity keeps comparing against the frozen fixtures/band-out.txt (never regenerate it).
- Repo (2026-10-27): all code lives in one repo (mod/, desktop/, creative/); ./install and ./uninstall at the root; dev mode for the owner, release mode follows signed v* tags (pinned signers, on the default branch, verified by SHA). Creative builder off. No commits or push yet.
- Transport latency was measured in-app (store mtime to commit) on live writes; an external window-capture check (tools/latency, scratch store) was not run.
- 3.11: the pup could follow Blue to a camp instead of staying at the homestead.
"""
open(os.path.join(HERE, "parity-status.md"), "a").write(steps)
