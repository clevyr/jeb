// Parity: the desktop's parity fixtures.
//
// gen: writes each fixture as a store file for the desktop (fixtures/<name>.store.json: the farm and the live records,
// nothing else) and the band's side as a scratch test in the mod COPY (modcopy/tests/zz-parity.test.tsx), which composes
// the band's own pixels for the same state inside the engine's test sandbox and prints them.
//
// compare <band-output>: renders each fixture on the desktop (offscreen, CARenderer), finds the sprites and labels the
// checks name in both pictures (tools/detect) and compares them: farm things against the homestead (same layout rules,
// same width, so the same positions), home things (the one Jeb, Blue, chair, bang, hat, bubble: the record acted out at
// the place on screen) relative to the one Jeb, camp things (what a session's camp keeps: rigs, Opal, hands) relative to
// the camp's anchors, and counts. The scene is one place at a time (the stage strip): a fixture starts at the place
// JEB_PLACE seeds (home, or a camp: `place` below), farm fixtures at home, camp fixtures at the camp of fx00. Every
// fixture is also checked for exactly one place root in the tree, the strips of that place only, and no more than one Jeb
// and one Blue. A fixture with only desktop-only checks (home-has, scene-count, mist, absent, story) needs no band output.
//
// The store files must stay byte-identical to the tracked ones: Json keeps key order and writes json.dump's default
// `, ` / `: ` shape, and ms() goes through mktime, so TZ decides the instants (the tracked fixtures: America/New_York).
import Foundation

let COLS = 106  // the band at 424 px, the desktop's farm width on this screen

// ---- the fixtures table ----

/// One check of a fixture (the Python's tuples; `kind` is the tuple's first item).
enum Check {
    case sprites(String, [String])              // "farm" | "camp" | "home", the sprites and labels to find in both pictures
    case pixels(Int, Int, Int, Int)
    case count(String, Int?)                    // nil: as many as fit, at least one in each
    case text(String)
    case lanterns(Int)
    case lane(String, Int, Int, Int, Bool)      // sprite, x, reach, sprite width, flipped
    case walk(String, Double)
    case bubble(Bool)                           // dim
    case tint(String, (Int, Int, Int))
    case dry(String)
    case homeHas([String], [String])
    case sceneCount([String], Int)
    case absent([String])
    case story([(String, String)])
    case places(String)
    case ridges
    case mist(Int, Int, Int)
    case areaTheme
    case areaPlain

    var kind: String {
        switch self {
        case let .sprites(k, _): return k
        case .pixels: return "pixels"
        case .count: return "count"
        case .text: return "text"
        case .lanterns: return "lanterns"
        case .lane: return "lane"
        case .walk: return "walk"
        case .bubble: return "bubble"
        case .tint: return "tint"
        case .dry: return "dry"
        case .homeHas: return "home-has"
        case .sceneCount: return "scene-count"
        case .absent: return "absent"
        case .story: return "story"
        case .places: return "places"
        case .ridges: return "ridges"
        case .mist: return "mist"
        case .areaTheme: return "area-theme"
        case .areaPlain: return "area-plain"
        }
    }
}

let DESK_ONLY = ["home-has", "scene-count", "mist", "absent", "story", "places", "ridges", "area-theme", "area-plain"]

struct Fixture {
    var name: String
    var rows: String
    var now: Int
    var farm: Json
    var live: [Json]
    var checks: [Check]
    var env: [String: String]
    var place: String
    var since: Int?
    var areas: Json?
}

let BASE: Json = [
    "version": 10, "rev": 1,
    "crops": ["tobacco": [3, 2, 1, 0, 3, 2, 1, 0], "corn": [0, 1, 2, 3, 0, 1, 2, 3], "apples": [3, 2, 1, 0, 0, 0, 0, 0]],
    "progress": ["tobacco": 0, "corn": 0, "apples": 0],
    "barn": ["bales": 0, "corn": 9, "apples": 23, "sticks": 0],
    "still": ["steps": 0, "hasBatch": false],
    "shelf": ["lightning": 0, "appleCinnamon": 7],
    "lifetime": ["outputTokens": 0, "inputTokens": 0, "workMs": 0, "bales": 12, "balesTraded": 0],
    "ledger": ["cash": 1590, "total": 1620],
    "upgrades": [], "built": [],
    "materials": ["lumber": 10, "stone": 2, "straw": 43, "iron": 0, "sugar": 0, "copper": 0],
    "components": ["barrel": 0, "post": 0, "coil": 0],
    "goods": ["appleButter": 0, "twists": 0, "aged": [], "whiskey": 0],
    "quilt": .array("BGRPYNBG".map { ["c": .string(String($0)), "d": "2026-10-01", "camp": ""] }),
    "unlocks": [], "unlockDay": ["d": "", "n": 0, "done": 0, "next": 0, "since": "", "coffee": ""],
    "surprises": [], "creative": ["total": 0, "arc": nil, "structures": [], "art": [], "festival": ["d": "", "tint": ""]],
]

let JEB = ["jeb-idle", "jeb-happy", "jeb-spooked", "jeb-wink", "jeb-think", "jeb-sleep", "jeb-banjo", "jeb-sip", "jeb-hoe", "jeb-broom",
           "jeb-book", "jeb-stir", "jeb-salute", "jeb-wave", "jeb-hold"]
let BLUE = ["blue-wag", "blue-run", "blue-nap", "blue-bark"]
let FARM_CORE = ["house", "house-coat", "house-night", "house-coat-night", "still", "still-keg", "still-worm", "still-tarp", "sign", "sign-coat",
                 "sign-night", "embers", "icon-jar", "icon-cash"]

/// A live record: {"v": 1, "at": now, "frame": 0}, saidAt a second earlier when it says a line, then the given keys.
func rec(_ now: Int, _ k: Json = [:]) -> Json {
    var r: Json = ["v": 1, "at": .int(now), "frame": 0]
    if k["line"] != nil { r.set("saidAt", .int(now - 1000)) }
    return r.updated(k)
}

func ev(_ id: String, _ t: Int, _ dur: Int, _ v: Int = 0) -> Json { ["id": .string(id), "t": .int(t), "dur": .int(dur), "v": .int(v)] }

/// The fixtures, in the Python's order.
let F: [Fixture] = makeFixtures()

private func makeFixtures() -> [Fixture] {
    var F: [Fixture] = []
    func fx(_ name: String, _ rows: String, _ now: Int, _ farm: Json = [:], _ live: [Json] = [], _ checks: [Check] = [], env: [String: String] = [:],
            place: String = "home", since: Int? = nil, areas: Json? = nil) {
        F.append(Fixture(name: name, rows: rows, now: now, farm: farm, live: live, checks: checks, env: env, place: place, since: since, areas: areas))
    }
    func farm(_ qs: [String]) -> Check { .sprites("farm", qs) }
    func home(_ qs: [String]) -> Check { .sprites("home", qs) }
    func camp(_ qs: [String]) -> Check { .sprites("camp", qs) }

    let D = ms(2026, 10, 21, 14)      // a Wednesday afternoon in October
    let N = ms(2026, 7, 9, 23)        // a July night

    // Area 2-3, 12-13: the farm itself.
    fx("farm-day", "2.1 2.4 3.1 3.4 3.6 12.1 13.1", D, [:], [rec(D)], [.pixels(0, 0, 250, 48),
        farm(["tobacco-0", "tobacco-1", "tobacco-2", "tobacco-3", "corn-0", "corn-1", "corn-2", "corn-3", "apple-0", "apple-1", "apple-2", "apple-3"]),
        farm(FARM_CORE + ["icon-lumber", "icon-stone", "icon-straw", "quilt-B", "quilt-G", "quilt-R", "quilt-P", "quilt-Y", "quilt-N"]),
        farm(["text:white:TOBACCO 12", "text:white:CORN 9", "text:white:APPLES 23", "text:white:x7", "text:white:$1.5k", "text:cloud:10", "text:cloud:43"]),
    ])
    let builtFarm: Json = [
        "upgrades": ["mailbox", "chair", "hen", "pup", "coat", "still2"], "built": ["fencedFields", "copperWorm", "thumpKeg", "smokehouse"],
        "materials": ["lumber": 120, "stone": 5, "straw": 2, "iron": 1, "sugar": 0, "copper": 3],
        "goods": ["appleButter": 4, "twists": 0, "aged": [["readyAt": 1]], "whiskey": 1]]
    fx("farm-built", "2.6 3.3 3.4 3.8 3.10 3.11 3.14 12.1 12.3", D, builtFarm, [rec(D)], [
        .pixels(0, 0, 250, 48),
        farm(FARM_CORE + ["prop-fence", "prop-mailbox", "prop-keg", "prop-smokehouse", "icon-lumber", "icon-stone", "icon-copper", "icon-apple_butter", "icon-whiskey"]),
        farm(["text:cloud:99+", "text:cloud:5", "text:cloud:3", "text:cloud:4", "text:cloud:2"]),
    ])
    fx("farm-night", "1.2 1.3 1.4 3.1", N, ["upgrades": ["coat"]], [rec(N, ["act": "nap"])], [
        farm(["house-coat-night", "sign-coat", "firefly"]),
        home(["jeb-sleep", "zz", "blue-nap"]),
    ])
    fx("quilt-stitch", "13.1 13.2 13.3", D, [:], [rec(D, ["stitch": true, "live": "P", "frame": 0])], [
        farm(["quilt-B", "quilt-G", "quilt-R", "quilt-P", "quilt-Y", "quilt-N"]),
    ])

    // Area 1: the calendar.
    let zeros: Json = [0, 0, 0, 0, 0, 0, 0, 0]
    fx("pumpkin", "1.10", ms(2026, 10, 27, 10), ["crops": ["tobacco": zeros, "corn": zeros, "apples": [3, 3, 3, 3, 0, 0, 0, 0]]], [rec(ms(2026, 10, 27, 10))],
       [farm(["apple-pumpkin", "apple-3", "prop-pumpkin"])])
    fx("christmas", "1.9", ms(2026, 12, 22, 10), [:], [rec(ms(2026, 12, 22, 10))], [farm(["prop-xmas"])])
    fx("thanksgiving", "1.11", ms(2026, 11, 26, 10), [:], [rec(ms(2026, 11, 26, 10))], [farm(["turkey"])])
    fx("groundhog", "1.12", ms(2027, 2, 2, 10), [:], [rec(ms(2027, 2, 2, 10))], [farm(["groundhog"])])

    // Area 4: Jeb's sprite by priority, Blue's states.
    let J = ms(2026, 10, 21, 15)
    fx("jeb-gate", "4.1 15.7", J, [:], [rec(J, ["gated": true, "fx": ["sip"], "pose": "read"])], [home(JEB)])
    fx("jeb-sip", "4.1 4.7 3.9", J, ["upgrades": ["chair"]], [rec(J, ["fx": ["sip"], "pose": "read"])], [home(JEB + ["prop-chair"])])
    fx("jeb-pose-read", "4.2", J, [:], [rec(J, ["pose": "read", "mood": "spooked"])], [home(JEB)])
    fx("jeb-pose-still", "4.2 3.5", J, [:], [rec(J, ["pose": "still", "busy": true, "mood": "working"])], [home(JEB), .count("fire", 1), .count("steam", 1)])
    fx("jeb-think", "4.2 11.6", J, [:], [rec(J, ["pose": "think"])], [home(JEB)])
    fx("jeb-hoe", "4.2 11.8", J, [:], [rec(J, ["pose": "hoe"])], [home(JEB)])
    fx("jeb-sweep", "4.2 11.11", J, [:], [rec(J, ["pose": "sweep"])], [home(JEB)])
    fx("jeb-spooked", "4.3 4.6", J, [:], [rec(J, ["mood": "spooked"])], [home(JEB + ["sweat"])])
    fx("jeb-pleased", "4.3", J, [:], [rec(J, ["mood": "pleased", "fx": ["wink"]])], [home(JEB)])
    fx("jeb-wink", "4.11", J, [:], [rec(J, ["fx": ["wink", "wag"], "frame": 1])], [home(JEB + BLUE + ["heart"])])
    fx("jeb-working", "4.3", J, [:], [rec(J, ["mood": "working", "busy": true])], [home(JEB)])
    fx("jeb-banjo", "4.4", J, [:], [rec(J, ["act": "banjo", "frame": 1])], [home(JEB + ["note"])])
    fx("jeb-nap", "4.4 4.9", J, [:], [rec(J, ["act": "nap"])], [home(JEB + BLUE + ["zz"])])
    fx("blue-chase", "4.4 4.9 3.10", J, ["upgrades": ["hen"]], [rec(J, ["act": "chase", "frame": 3])], [home(BLUE + ["hen"])])
    fx("blue-errand", "4.10", J, [:], [rec(J, ["dogRun": 12, "frame": 5])], [home(BLUE)])
    fx("jeb-away", "4.8 7.1 3.9", J, ["upgrades": ["chair"]], [rec(J, ["truck": ["t": 3, "load": "bale", "sputter": 0, "dog": false]])],
       [home(JEB + BLUE + ["prop-chair", "bang"]), farm(["truck-bales", "dust"])])
    fx("truck-home", "7.1 7.2", J, [:], [rec(J, ["truck": ["t": 12, "load": "jar", "sputter": 0, "dog": true]])],
       [farm(["truck-empty", "icon-cash", "blue-wag", "dust"]), home(BLUE)])
    fx("truck-butter", "7.1", J, [:], [rec(J, ["truck": ["t": 2, "load": "butter", "sputter": 2, "dog": false]])], [farm(["truck-crate", "icon-apple_butter", "dust"])])
    fx("puff", "4.11", J, [:], [rec(J, ["fx": ["puff"]])], [farm(["truck-empty", "dust"])])

    // Area 5-6: hands, teammates, lanterns.
    fx("hands", "5.1 2.5", J, [:], [rec(J, ["hands": [["plot": "tobacco", "look": 2], ["plot": "corn", "look": 4]], "more": ["corn": 3]])],
       [.count("hand-work-2", 1), .count("hand-work-4", 1), .text("text:yellow:+3")])
    fx("workflow", "5.2", J, [:], [rec(J, ["hands": [["plot": "tobacco", "look": 1], ["plot": "corn", "look": 1], ["plot": "apples", "look": 1]], "more": ["tobacco": 4]])],
       [.count("hand-work-1", 3), .text("text:yellow:+4")])
    fx("mates", "5.6", J, [:], [rec(J, ["mates": 2])], [.count("opal", 1), .count("hand-work", 1)])
    fx("lanterns", "6.2", J, [:], [rec(J), rec(J), rec(J)], [.lanterns(3)])

    // Area 7: visits.
    fx("visit-arrive", "7.3", J, [:], [rec(J, ["visit": ["kind": "store", "x": 16, "facing": "in", "phase": "arrive"]])], [.lane("rig-store", 16, 32, 40, false)])
    fx("visit-deal", "7.3 7.5 4.9", J, [:], [rec(J, ["visit": ["kind": "mill", "x": 32, "facing": "in", "phase": "deal"]])], [home(JEB + BLUE + ["bang"]), camp(["rig-mill"])])
    fx("visit-opal", "7.3 7.4", J, [:], [rec(J, ["visit": ["kind": "opal", "x": 10, "facing": "out", "phase": "leave"]])], [.lane("opal", 10, 20, 14, true)])
    fx("visit-tractor", "7.3", J, [:], [rec(J, ["visit": ["kind": "tractor", "x": 30, "facing": "in", "phase": "arrive"]])], [.count("rig-tractor", 1)])
    fx("visit-mail", "7.4", J, ["upgrades": ["mailbox"]], [rec(J, ["visit": ["kind": "mail", "x": 32, "facing": "in", "phase": "deal"]])], [home(JEB), camp(["rig-mail"])])

    // Area 8: happenings.
    fx("ev-revenuer", "8.1 3.4", J, [:], [rec(J, ["event": ev("revenuer", 40, 96), "mood": "spooked"])], [farm(["revenuer", "still-tarp"]), home(JEB)])
    fx("ev-neighbor", "8.2", J, [:], [rec(J, ["event": ev("neighbor", 60, 96)])], [home(JEB), camp(["opal"])])
    fx("ev-neighbor-walk", "8.2", J, [:], [rec(J, ["event": ev("neighbor", 20, 96)])], [.walk("opal", 20.0 / 96.0)])
    fx("ev-bear", "8.3", J, [:], [rec(J, ["event": ev("bear", 30, 80), "frame": 0])], [farm(["bear"]), home(["bang"] + BLUE)])
    fx("ev-whistlepig", "8.4 2.7", J, [:], [rec(J, ["event": ev("whistlepig", 24, 72, 3)])], [farm(["groundhog"])])
    fx("ev-mothman", "8.5", N, [:], [rec(N, ["event": ev("mothman", 12, 60, 2), "mood": "spooked"])], [farm(["mothman"])])
    fx("ev-bugs", "8.6", ms(2026, 6, 20, 22), [:], [rec(ms(2026, 6, 20, 22), ["event": ev("bugs", 36, 96, 5)])], [farm(["firefly"])])
    fx("ev-bells", "8.7", ms(2026, 10, 25, 10), [:], [rec(ms(2026, 10, 25, 10), ["event": ev("bells", 12, 60)])], [farm(["prop-bell", "note"])])
    fx("ev-storm", "8.8", J, [:], [rec(J, ["event": ev("storm", 30, 96)])], [farm(["cloud-dark"])])
    fx("ev-turkeys", "8.10", J, [:], [rec(J, ["event": ev("turkeys", 40, 90)])], [farm(["turkey"])])
    fx("ev-parachute", "8.11", J, [:], [rec(J, ["event": ev("parachute", 50, 100)])], [farm(["prop-parachute"])])
    fx("ev-track", "8.12", ms(2026, 10, 21, 18), [:], [rec(ms(2026, 10, 21, 18), ["event": ev("track", 12, 60)])], [home(["bang"] + BLUE)])
    fx("ev-hornworm", "8.13", J, [:], [rec(J, ["event": ev("hornworm", 12, 60)])], [home(JEB + ["sweat"])])
    fx("ev-applebutter", "8.14", J, [:], [rec(J, ["event": ev("applebutter", 12, 80)])], [home(JEB)])
    for (i, id) in ["bees", "sorghum", "ramps", "sang", "quilting"].enumerated() {
        fx("story-\(i + 1)", "A\(i + 1)", J, [:], [rec(J, ["event": ev(id, 12, 70)])], [home(JEB)])
    }

    // Area 9: drops.
    let art: Json = ["id": "lantern-fox", "w": 6, "h": 5, "frames": 1, "rows": ["..yy..", ".yyyy.", "yykkyy", ".yyyy.", "..yy.."]]
    let surprise: Json = [
        "day": "2026-10-21", "slot": 9, "kind": "decor", "name": "x", "lines": [],
        "sprites": [["sprite": "deer", "zone": "yard", "frames": 1], ["sprite": "cardinal", "zone": "porch", "frames": 2]],
        "window": nil, "lasts": "today", "made": "local", "arc": "", "step": 0, "festival": ""]
    let structure: Json = ["name": "s", "day": "2026-10-20", "arc": "", "sprites": [["sprite": "lantern-fox", "zone": "field", "frames": 1]]]
    let dropsFarm: Json = [
        "surprises": [surprise],
        "creative": ["total": 3, "arc": nil, "structures": [structure], "art": [art], "festival": ["d": "", "tint": ""]]]
    let dropEvent: Json = ["id": "drop", "t": 10, "dur": 80, "v": 1, "art": ["sprites": [["sprite": "bell", "zone": "sky", "frames": 1]], "custom": []]]
    fx("drops", "9.3 9.4 9.5 9.9 9.10", J, dropsFarm, [rec(J, ["event": dropEvent])], [farm(["deer", "cardinal", "prop-bell"]), .pixels(2, 0, 160, 40)])
    fx("festival", "9.8", J, ["creative": ["total": 3, "arc": nil, "structures": [], "art": [], "festival": ["d": "2026-10-21", "tint": "gold"]]], [rec(J)],
       [farm(FARM_CORE), .tint("dirt", (255, 200, 80))])

    // Area 10 and the little things (list C): every look, at its hour.
    let ALL = ["birdhouse", "woodpile", "garden", "creek", "cardinal", "owl", "butterflies", "deer", "drift", "afterrain", "shootingstar", "mug", "lunch",
               "napchair", "porchlight", "sundayhat", "washday", "postcard", "anniversary", "midnightcoffee"]
    let L: Json = ["unlocks": strings(ALL), "upgrades": ["chair"], "materials": ["lumber": 25, "stone": 0, "straw": 0, "iron": 0, "sugar": 0, "copper": 0]]
    let mon9 = ms(2026, 6, 15, 9)
    fx("looks-1", "C1 C3 C5 C6 C7 C8 C9 C17", mon9, L, [rec(mon9)],
       [farm(["creek", "laundry-shirt", "laundry-overalls", "woodpile-3", "axe-stump", "garden-2", "birdhouse", "bluebird", "cardinal", "mug"])])
    let sat14 = ms(2026, 6, 13, 14)
    fx("looks-2", "C2 C11 C20", sat14, L, [rec(sat14)], [farm(["creek", "fisher", "butterfly"]), home(JEB + ["prop-chair", "zz"])])
    let sun12 = ms(2026, 6, 14, 12, 30)
    fx("looks-3", "C19 C22", sun12, L, [rec(sun12)], [farm(["lunch"]), home(["hat-feather"] + JEB)])
    let wed18 = ms(2026, 10, 21, 18)
    fx("looks-4", "C4 C12 C21", wed18, L, [rec(wed18)], [farm(["deer", "porch-light", "drift-leaf-0", "drift-leaf-1", "drift-leaf-2"])])
    let wed15 = ms(2026, 10, 21, 15)
    fx("looks-5", "C23", wed15, L, [rec(wed15)], [farm(["postcard"])])
    let n23 = ms(2026, 7, 9, 23)
    fx("looks-6", "C10 C14 C15 C16", n23, L, [rec(n23, ["rainbow": true, "wet": true, "star": 6])], [farm(["owl", "rainbow", "puddle", "star-streak"])])
    let c2 = ms(2026, 1, 7, 2)
    fx("looks-7", "C18", c2, L.updated(["unlockDay": ["d": "", "n": 0, "done": 0, "next": 0, "since": "", "coffee": "2026-01-07"]]), [rec(c2)], [farm(["mug"])])
    let an = ms(2026, 3, 4, 10)
    fx("looks-8", "C24", an, L.updated(["unlockDay": ["d": "", "n": 0, "done": 0, "next": 0, "since": "2025-03-04", "coffee": ""]]), [rec(an)], [farm(["cake"])])
    let snow = ms(2026, 1, 15, 11)
    fx("looks-9", "C13", snow, L, [rec(snow)], [farm(["drift-flake"])])

    // Area 11: the bubble.
    fx("bubble", "11.1", J, [:], [rec(J, ["line": "Picked every last one. Lord willin', they'll keep.", "mood": "pleased"])], [.bubble(false)])
    fx("bubble-dim", "11.2", J, [:], [rec(J, ["line": "Quiet day on the ridge.", "dim": true])], [.bubble(true)])
    fx("cows", "11.1 appendix-b", J, [:], [rec(J, ["cows": [42, 7], "moreCows": 2])], [.count("cow", nil), .text("text:white:#42")])

    // Area 2: test weather at a camp.
    fx("rain", "2.8", J, [:], [rec(J, ["weather": ["kind": "rain", "plot": "corn"]])], [.count("cloud-dark", 1)])
    fx("rain-all", "2.8", J, [:], [rec(J, ["weather": ["kind": "rain", "plot": "all"]])], [.count("cloud-dark", 3)])
    fx("dry", "2.9", J, [:], [rec(J, ["weather": ["kind": "dry", "plot": "tobacco"]])], [.dry("tobacco")])

    // One Jeb and one Blue, whatever the number of sessions, at the one place on screen. These check the desktop's own rules
    // (the band draws the first record only), so they need no band output.
    // lead-two: at home he acts out the busy session (reading), not the newer idle one (the idle Jeb would play the banjo).
    fx("lead-two", "4.2 11.1", J, [:], [rec(J), rec(J - 30000, ["pose": "read", "busy": true, "mood": "working"])],
       [.homeHas(["jeb-book"], ["jeb-banjo", "jeb-hold"]), .sceneCount(JEB, 1), .sceneCount(BLUE, 1),
        .story([("place", "home"), ("phase", "stay"), ("acting", "fx01"), ("queue", "")])], since: 800)
    // lead-hold: at home, fx00 (idle, its line fresh) holds the lead against the newer idle fx01 while its line is up.
    fx("lead-hold", "4.12 11.1", J, [:], [rec(J - 5000, ["mood": "pleased", "line": "Holding steady now"]), rec(J)],
       [.homeHas(["jeb-happy", "text:ink:Holding steady now"], ["jeb-banjo"]), .sceneCount(JEB, 1),
        .story([("place", "home"), ("phase", "stay"), ("acting", "fx00"), ("queue", "")])], since: 800)
    // one-jeb: four sessions, one Jeb and one Blue in the whole scene.
    fx("one-jeb", "3.9 4.x", J, [:],
       [rec(J - 1000, ["pose": "read", "busy": true]), rec(J), rec(J - 2000, ["pose": "edit", "busy": true]), rec(J - 3000, ["mood": "pleased"])],
       [.sceneCount(JEB, 1), .sceneCount(BLUE, 1), .homeHas(["jeb-book"], [])], since: 0)
    // place-one: four sessions with something each (hands, cows, rain; a visitor; a truck and a happening), one place drawn: the homestead,
    // acting out fx00; nothing of the others is drawn, 1 Jeb and 1 Blue, one place root and one farm strip. Their calls wait out the home spell.
    let bale: Json = ["t": 3, "load": "bale", "sputter": 0, "dog": false]
    fx("place-one", "one place", J, [:], [
        rec(J - 1000, ["pose": "read", "busy": true]),
        rec(J - 2000, ["hands": [["plot": "tobacco", "look": 2], ["plot": "corn", "look": 4]], "cows": [42, 7], "weather": ["kind": "rain", "plot": "corn"], "building": "app"]),
        rec(J - 3000, ["visit": ["kind": "store", "x": 16, "facing": "in", "phase": "arrive"]]),
        rec(J - 4000, ["truck": bale, "event": ev("revenuer", 40, 96)])],
       [.sceneCount(JEB, 1), .sceneCount(BLUE, 1), .homeHas(["jeb-book"], []),
        .absent(["hand-work-2", "hand-work-4", "cow", "cloud-dark", "rig-store", "truck-bales", "revenuer"]),
        .story([("place", "home"), ("phase", "stay"), ("acting", "fx00"), ("queue", "hands@fx01,weather@fx01,event@fx03,ship@fx03")]), .places("home")], since: 5)
    // queue-order: at home past the medium spell, four calls wait (low, low, medium, low): the medium one goes first, and the lows keep their order.
    let HANDS: Json = [["plot": "tobacco", "look": 2]]
    fx("queue-order", "queue", J, [:],
       [rec(J - 1000, ["hands": HANDS]), rec(J - 2000, ["weather": ["kind": "rain", "plot": "corn"]]), rec(J - 3000, ["event": ev("bells", 12, 60)]),
        rec(J - 4000, ["truck": bale])],
       [.story([("place", "home"), ("phase", "leave"), ("to", "fx02"), ("queue", "hands@fx00,weather@fx01,ship@fx03"), ("reason", "event")]),
        .sceneCount(JEB, 1), .sceneCount(BLUE, 1)],
       since: 400)
    // visit-hold: 30 s into a visit he stays at least a minute, though the session is quiet and a medium call waits.
    fx("visit-hold", "visit", J, [:], [rec(J - 60000), rec(J - 1000, ["event": ev("bells", 12, 60)])],
       [.story([("place", "camp:fx00"), ("phase", "stay"), ("queue", "event@fx01")]), .sceneCount(JEB, 1), .places("camp")], place: "fx00", since: 30)
    // quiet-home: nobody waits and the visit has run its 90 s: he sets out for home, not on to another camp.
    fx("quiet-home", "visit", J, [:], [rec(J - 40000)],
       [.story([("place", "camp:fx00"), ("phase", "leave"), ("to", "home"), ("reason", "homeward"), ("queue", "")])],
       place: "fx00", since: 100)
    // home-quiet: at home with no current record: the calm idle, not a record's nap.
    fx("home-quiet", "home", J, [:], [rec(J - 700000, ["act": "nap"])],
       [.homeHas(["jeb-idle"], ["jeb-sleep"]), .story([("place", "home"), ("phase", "stay"), ("acting", "-")]), .places("home")], since: 0)
    // goodbye: the visited session's record is gone (stale): he waves it off, then moves on (home, nobody waits).
    fx("goodbye", "goodbye", J, [:], [rec(J - 700000)],
       [.homeHas(["jeb-wave"], ["jeb-banjo"]), .story([("place", "camp:fx00"), ("phase", "leave"), ("to", "home"), ("reason", "ended")]), .places("camp")],
       place: "fx00", since: 300)
    // home-default: busy sessions and no call: he stays home acting out the busiest (fx02, reading), though the first is the idle fx00.
    fx("home-default", "home", J, [:],
       [rec(J - 8000), rec(J - 4000, ["pose": "edit", "busy": true, "mood": "working"]), rec(J - 2000, ["pose": "read", "busy": true, "mood": "working"])],
       [.homeHas(["jeb-book"], ["jeb-banjo"]), .sceneCount(JEB, 1), .sceneCount(BLUE, 1),
        .story([("place", "home"), ("phase", "stay"), ("acting", "fx02"), ("queue", "")]), .places("home")], since: 800)
    // call-event: a happening at fx00 calls him out once the 5 minute home spell is up.
    fx("call-event", "call", J, [:], [rec(J - 1000, ["event": ev("bells", 12, 60)])],
       [.story([("place", "home"), ("phase", "leave"), ("to", "fx00"), ("reason", "event"), ("queue", "")]), .sceneCount(JEB, 1), .sceneCount(BLUE, 1)], since: 400)
    // call-spell: a low call (hands) waits out the 15 minute home spell: at 5 minutes he is home with it queued; at 20 he goes.
    fx("call-spell", "call", J, [:], [rec(J - 1000, ["hands": HANDS])],
       [.story([("place", "home"), ("phase", "stay"), ("queue", "hands@fx00"), ("to", "-")]), .places("home")], since: 300)
    fx("call-spell-go", "call", J, [:], [rec(J - 1000, ["hands": HANDS])],
       [.story([("place", "home"), ("phase", "leave"), ("to", "fx00"), ("reason", "hands"), ("queue", "")])], since: 1200)
    // fog (8.9): mist over the homestead's sky rows, the band's own pattern (a gap every third pixel, half and half elsewhere).
    fx("fog", "8.9", J, [:], [rec(J, ["event": ev("fog", 40, 96)])], [.mist(40 / 8, 0, 250)])

    // The backdrop: the ridges stand whole above the hillside, at home and at each camp's land, by season and at night.
    let JAN = ms(2027, 1, 13, 12), JUL = ms(2026, 7, 8, 12)
    for (nm, now, pl) in [("ridges-home", D, "home"), ("ridges-jul", JUL, "home"), ("ridges-jan", JAN, "home"), ("ridges-night", N, "home"),
                          ("ridges-camp0", D, "fx00"), ("ridges-camp1", D, "fx01"), ("ridges-camp2", JAN, "fx02"), ("ridges-camp3", N, "fx03")] {
        fx(nm, "backdrop", now, [:], (0..<4).map { _ in rec(now) }, [.ridges], env: ["JEB_ANIMS": "band"], place: pl, since: pl != "home" ? 800 : nil)
    }

    // Areas (the store's `areas` key): a record's `area` names one by its 8-hex key. Generic fixture text throughout.
    let AK = "a1b2c3d4"
    func area(_ k: Json = [:]) -> Json {
        let a: Json = [
            "v": 1, "made": "offline", "day": "2026-10-20", "seen": "2026-10-21", "name": "Test Area", "terrain": "creek", "palette": "moss", "weather": "fog",
            "mood": "gold", "motif": "bird", "props": ["lantern", "birdhouse", "puddle"], "lore": ["Plain test lore one.", "Plain test lore two."],
            "beats": [["line": "Test beat one.", "prop": "lantern", "zone": "yard"], ["line": "Test beat two.", "prop": nil, "zone": "porch"],
                      ["line": "Test beat three.", "prop": "cloud", "zone": "sky"]]]
        return a.updated(k)
    }
    // area-camp: at a camp whose record names a read area, the land and the strip are the area's (the plain twin render differs in both).
    fx("area-camp", "area", J, [:], [rec(J - 1000, ["area": .string(AK)])], [.areaTheme], place: "fx00", since: 800, areas: .object([(AK, area())]))
    // area-bad: every off-schema area is ignored whole (no theme, a picture identical to the plain twin's).
    let beatsA: Json = .array(["hen", "pup", "bell", "star"].map { ["line": "Beat a.", "prop": .string($0), "zone": "yard"] })
    let BAD: Json = [
        "a1b2c3d4": area(["terrain": "swamp"]), "a1b2c3d5": area(["lore": [.string(String(repeating: "x", count: 65)), "ok line"]]),
        "a1b2c3d6": area(["lore": ["see http://example.com/x", "ok line"]]),
        "a1b2c3d7": area(["props": ["nosuchsprite", "lantern", "birdhouse"]]), "A1B2C3D8": area(), "a1b2c3d": area(), "a1b2c3d9": area(["extra": "x"]),
        "a1b2c3da": area(["props": ["lantern", "birdhouse", "puddle", "cloud", "cow"], "beats": beatsA])]
    fx("area-bad", "area", J, [:], [rec(J - 1000, ["area": "a1b2c3d4"])], [.areaPlain], place: "fx00", since: 800, areas: BAD)
    // area-trip: a call from a camp with a read area sends him there, the area named, its own lines used.
    fx("area-trip", "area", J, [:], [rec(J - 1000, ["area": .string(AK), "event": ev("bells", 12, 60)])],
       [.story([("place", "home"), ("phase", "leave"), ("to", "fx00"), ("reason", "event"), ("area", AK), ("arealines", "1")])],
       since: 400, areas: .object([(AK, area())]))

    let CAMP_FIXTURES: Set<String> = ["hands", "workflow", "mates", "visit-arrive", "visit-deal", "visit-opal", "visit-tractor", "visit-mail", "ev-neighbor",
                                      "ev-neighbor-walk", "cows", "rain", "rain-all", "dry"]
    for i in F.indices where CAMP_FIXTURES.contains(F[i].name) { F[i].place = "fx00" }
    return F
}

/// The store a fixture draws from (and its farm).
func storeOf(_ f: Fixture) -> (store: Json, farm: Json) {
    let farm = BASE.updated(f.farm)
    var store: Json = ["farm": farm]
    for (i, r) in f.live.enumerated() { store.set(String(format: "live:fx%02d", i), r) }
    if let a = f.areas { store.set("areas", a) }
    return (store, farm)
}

// ---- gen ----

func parityGen(_ at: Places) {
    makeDirs(at.fixtures)
    var out: [Json] = []
    for f in F {
        let (store, farm) = storeOf(f)
        writeFile(at.fixtures + "/" + f.name + ".store.json", store.dumps())
        out.append(["name": .string(f.name), "now": .int(f.now), "farm": farm, "live": .array(f.live)])
    }
    // what the apply gate's smoke run needs of each fixture (cli/Gates.swift: gateFixtures), beside the stores
    let smoke: [Json] = F.map { f in
        var row: [(String, Json)] = [("name", .string(f.name)), ("now", .int(f.now)), ("place", .string(f.place)),
                                     ("since", f.since.map(Json.int) ?? .null)]
        row.append(("env", .object(f.env.sorted { $0.key < $1.key }.map { ($0.key, Json.string($0.value)) })))
        return .object(row)
    }
    writeFile(at.fixtures + "/smoke.json", Json.array(smoke).dumps(indent: 1) + "\n")
    let test = at.src + "/modcopy/tests/zz-parity.test.tsx"
    if !isDir(parentDir(test)) {
        print("\(F.count) fixtures; stores written, no \(parentDir(test)) (make a modcopy to write the band's test)")
        return
    }
    writeFile(test, TEST.replacingOccurrences(of: "__FIXTURES__", with: Json.array(out).dumps()).replacingOccurrences(of: "__COLS__", with: String(COLS)))
    print("\(F.count) fixtures; test at \(test)")
}

let TEST = #"""
// Scratch parity test (in a COPY of the mod): the band's own pixels for each desktop fixture.
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

"""#

// ---- compare ----

/// One line of tools/detect: name frame flip x y score, top-left in picture pixels.
struct Match {
    var q: String
    var fr: Int, fl: Int, x: Int, y: Int
    var s: Double
}

/// A found thing relative to an anchor: the Python's (q, fr, x, y) tuples, kept in sets and printed sorted.
struct Hit: Hashable, Comparable, CustomStringConvertible {
    var q: String
    var fr: Int, x: Int, y: Int
    static func < (a: Hit, b: Hit) -> Bool { (a.q, a.fr, a.x, a.y) < (b.q, b.fr, b.x, b.y) }
    var description: String { "(\(pyRepr(q)), \(fr), \(x), \(y))" }
}

func pyRepr(_ hits: [Hit]) -> String { "[" + hits.map { $0.description }.joined(separator: ", ") + "]" }

/// What compare reads from the mod's art once (hooks/pixel-art.ts): sprite sizes and the palette's colour words.
struct ArtInfo {
    var sizes: [String: (Int, Int)] = [:]
    var colours: [String: Int] = [:]

    init(_ path: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("could not read \(path)") }
        let re = try! NSRegularExpression(pattern: #"^  '([^']+)': \{ w: (\d+), h: (\d+)"#, options: [.anchorsMatchLines])
        let ns = text as NSString
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            sizes[ns.substring(with: m.range(at: 1))] = (Int(ns.substring(with: m.range(at: 2))) ?? 8, Int(ns.substring(with: m.range(at: 3))) ?? 8)
        }
        guard let p = search(#"PIXEL_PALETTE: readonly number\[\] = (.*)"#, text), let pal = (try? Json.parse(p[1]))?.array,
              let c = search(#"PIXEL_COLOUR: Readonly<Record<string, number>> = (.*)"#, text), let cols = (try? Json.parse(c[1]))?.object else {
            fail("no palette in \(path)")
        }
        for (name, i) in cols {
            guard let i = i.int, i < pal.count, let rgb = pal[i].int else { continue }
            colours[name] = (rgb >> 16 & 255) | (rgb >> 8 & 255) << 8 | (rgb & 255) << 16
        }
    }

    /// A palette colour as the pictures' colour word (r | g << 8 | b << 16).
    func colour(_ name: String) -> Int {
        guard let c = colours[name] else { fail("no colour \(name) in the mod's art") }
        return c
    }
}

func detect(_ at: Places, _ image: String, _ queries: [String], _ need: String) -> [Match] {
    let out = capture([at.tools + "/detect", at.art, image] + queries, env: environWith(["DETECT_NEED": need]))
    var found: [Match] = []
    for line in out.split(separator: "\n") {
        let parts = line.components(separatedBy: " ")       // rsplit(" ", 5): the name may hold spaces (a text label)
        guard parts.count >= 6, let fr = Int(parts[parts.count - 5]), let fl = Int(parts[parts.count - 4]), let x = Int(parts[parts.count - 3]),
              let y = Int(parts[parts.count - 2]), let s = Double(parts[parts.count - 1]) else { continue }
        found.append(Match(q: parts[0..<parts.count - 5].joined(separator: " "), fr: fr, fl: fl, x: x, y: y, s: s))
    }
    return found
}

/// Among overlapping matches of one family (Jeb's sprites, Blue's), the best name only.
func best(_ matches: [Match], _ family: [String]) -> [Match] {
    var keep: [Match] = []
    let byScore = matches.enumerated().sorted { $0.element.s != $1.element.s ? $0.element.s > $1.element.s : $0.offset < $1.offset }.map { $0.element }
    for m in byScore {
        if family.contains(m.q) && keep.contains(where: { family.contains($0.q) && abs($0.x - m.x) < 6 && abs($0.y - m.y) < 6 }) { continue }
        keep.append(m)
    }
    return keep
}

/// The desktop render as colour words (-1 where clear), through tools/png2raw (cached beside the PNG).
func pngWords(_ at: Places, _ path: String) -> [Int32] {
    let out = path + ".rgba"
    let fm = FileManager.default
    func mtime(_ p: String) -> Date? { (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date }
    if let o = mtime(out), let p = mtime(path), o >= p {} else { _ = capture([at.tools + "/png2raw", path, out], env: environWith([:])) }
    guard let data = fm.contents(atPath: out) else { fail("png2raw made no \(out)") }
    return words([UInt8](data), data.count / 4)
}

/// The band's picture ("W H base64-rgba", as the mod's test printed it) as colour words.
func pixelWords(_ raw: String) -> [Int32] {
    guard let text = try? String(contentsOfFile: raw, encoding: .utf8) else { return [] }
    let parts = text.components(separatedBy: " ")
    guard parts.count == 3, let w = Int(parts[0]), let h = Int(parts[1]), let data = Data(base64Encoded: parts[2]), data.count >= w * h * 4 else { return [] }
    return words([UInt8](data), w * h)
}

private func words(_ b: [UInt8], _ n: Int) -> [Int32] {
    var out = [Int32](repeating: -1, count: n)
    for i in 0..<n where b[i * 4 + 3] != 0 { out[i] = Int32(b[i * 4]) | Int32(b[i * 4 + 1]) << 8 | Int32(b[i * 4 + 2]) << 16 }
    return out
}

/// The band's output file: every `FIX <name> <w> <h> <base64>` line (a later line for the same name wins).
func readBand(_ path: String) -> [String: (w: Int, h: Int, b64: String)] {
    guard let data = FileManager.default.contents(atPath: path) else { fail("could not read \(path)") }
    var band: [String: (w: Int, h: Int, b64: String)] = [:]
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        guard let r = line.range(of: "FIX ") else { continue }
        let parts = line[r.upperBound...].split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, let w = Int(parts[1]), let h = Int(parts[2]), !parts[0].isEmpty else { continue }
        guard let b64 = parts[3].split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" }).first else { continue }
        band[String(parts[0])] = (w, h, String(b64))
    }
    return band
}

/// Renders every fixture and prints one line each, then the count. True when all pass.
@discardableResult
func parityCompare(_ at: Places, _ bandOut: String) -> Bool {
    let band = readBand(bandOut)
    let art = ArtInfo(at.art)
    makeDirs(at.out)
    var results = [[String]](repeating: [], count: F.count)
    let lock = NSLock()
    let slots = DispatchSemaphore(value: min(8, ProcessInfo.processInfo.activeProcessorCount))
    let group = DispatchGroup()
    for (i, f) in F.enumerated() {
        slots.wait()
        group.enter()
        DispatchQueue.global().async {
            let r = compareOne(at, f, band[f.name], art)
            lock.lock(); results[i] = r; lock.unlock()
            slots.signal()
            group.leave()
        }
    }
    group.wait()
    for r in results { print("\(padded(r[2], 5)) \(padded(r[0], 18)) [\(r[1])] \(r[3])") }
    let passed = results.filter { $0[2] == "pass" }.count
    print("-- \(passed) of \(results.count) fixtures pass")
    writeFile(at.out + "/results.json", Json.array(results.map { strings($0) }).dumps(indent: 1))
    return passed == results.count
}

/// One fixture: [name, rows, pass | FAIL | n/a, notes].
private func compareOne(_ at: Places, _ f: Fixture, _ bandPic: (w: Int, h: Int, b64: String)?, _ art: ArtInfo) -> [String] {
    let name = f.name
    if bandPic == nil && f.checks.contains(where: { !DESK_ONLY.contains($0.kind) }) { return [name, f.rows, "n/a", "no band render"] }
    let braw = at.out + "/" + name + ".band.raw"
    var w = 0
    if let b = bandPic {
        w = b.w
        writeFile(braw, "\(b.w) \(b.h) \(b.b64)")
    }
    let png = at.out + "/" + name + ".desk.png"
    let storePath = at.fixtures + "/" + name + ".store.json"
    let bin = at.binary(default: "JebDesktop")
    var envExtra = ["JEB_BENCH": "0.01", "JEB_BENCH_FREEZE": "1", "JEB_BENCH_SCALE": "1", "JEB_BENCH_PNG": png, "JEB_BENCH_STORY": "1", "JEB_STORE_PATH": storePath,
                    "JEB_NOW": String(f.now), "JEB_PLACE": f.place]
    for (k, v) in f.env { envExtra[k] = v }
    if let s = f.since { envExtra["JEB_PLACE_SINCE"] = String(s) }
    let env = environWith(envExtra)
    let geo = capture([bin], env: env)
    guard let g = search(#"geometry scene (\d+) (\d+) farm (\d+) (\d+) (\d+) place (\S+) roots (\d+) farm (\d+) camp (\d+) road (\d+)"#, geo) else {
        return [name, f.rows, "FAIL", "no geometry line from \(bin)"]
    }
    let SW = Int(g[1])!, SH = Int(g[2])!, fxo = Int(g[3])!, road = Int(g[4])!, fw = Int(g[5])!
    let kind0 = g[6]
    let roots = Int(g[7])!, nfarm = Int(g[8])!, ncamp = Int(g[9])!, nroad = Int(g[10])!
    var story: [String: String] = [:]
    if let st = search(#"step t=\S+ start cast=(\d+)/(\d+) tree=(\d+)/(\d+) .*? place=(\S+) phase=(\S+) queue=(\S*) to=(\S+) reason=(\S+) acting=(\S+)"#, geo) {
        for (k, v) in zip(["jeb", "blue", "jebAll", "blueAll", "place", "phase", "queue", "to", "reason", "acting"], st.dropFirst()) { story[k] = v }
    }
    if let ar = search(#" area=(\S+) arealines=(\d) "#, geo) { story["area"] = ar[1]; story["arealines"] = ar[2] }
    let at0 = search(#"area theme (\d) placed (\d+)"#, geo)
    // Every fixture: one place root, only that place's strip, at most one Jeb and one Blue (in the tree too).
    guard let wantStrips = ["home": [1, 0, 0], "camp": [0, 1, 0], "road": [0, 0, 1]][kind0] else { return [name, f.rows, "FAIL", "place \(kind0)?"] }
    func cast(_ k: String) -> Int { Int(story[k] ?? "") ?? 0 }
    var ok = !(roots != 1 || [nfarm, ncamp, nroad] != wantStrips || story.isEmpty || cast("jeb") > 1 || cast("blue") > 1 || cast("jebAll") > 1 || cast("blueAll") > 1)
    func got(_ k: String) -> String { story[k] ?? "None" }
    var notes = ["place \(kind0): \(roots) root, strips farm \(nfarm) camp \(ncamp) road \(nroad), cast \(got("jeb"))/\(got("blue")) (tree \(got("jebAll"))/\(got("blueAll")))"]
    // Regions in the desktop picture (top-down): the stage strip; at a camp the camp's patch and Jeb stand where the farm's do.
    let farmTop = SH - road - 48
    let campX = fxo, campTop = farmTop, cw = fw
    let bandJeb = (x: w - 51 - 40 - 22, y: 0)
    let homeJeb = (x: fxo + fw - 113, y: farmTop)   // the one Jeb of the scene, at either place
    let blueX = bandJeb.x - 20
    let sun = (x: max(4, min(w - 12, blueX - 44)), y: 2)
    // The band's own Jeb-and-Blue corner (they live at the camps here), and its sun or moon (in the sky here).
    let passers: Set<String> = ["truck-empty", "truck-bales", "truck-crate", "truck-jars", "truck-apples", "truck-corn", "dust", "icon-cash", "icon-apple_butter",
                                "icon-twist", "icon-whiskey", "revenuer", "turkey", "blue-wag"]
    func bandFarmOk(_ m: Hit) -> Bool {
        let (sw, _) = art.sizes[m.q] ?? (8, 8)
        if m.x < 0 || m.x + sw > w { return false }
        if blueX - 16 <= m.x + sw && m.x < bandJeb.x + 22 && !passers.contains(m.q) { return false }
        if sun.x - 2 <= m.x && m.x <= sun.x + 9 && m.y <= 11 && sw <= 9 { return false }
        return true
    }
    func desk() -> [Int32] { pngWords(at, png) }
    func bench(_ store: String, _ out: String) {
        var e = env
        e["JEB_STORE_PATH"] = store
        e["JEB_BENCH_PNG"] = out
        _ = capture([bin], env: e)
    }
    func bytes(_ p: String) -> Data? { FileManager.default.contents(atPath: p) }

    for check in f.checks {
        switch check {
        case let .sprites(kind, qs):
            let need = kind == "farm" ? "0.9" : "0.97"
            let bm = best(best(detect(at, braw, qs, need), JEB), BLUE), dm = best(best(detect(at, png, qs, need), JEB), BLUE)
            var bs: Set<Hit>, ds: Set<Hit>
            if kind == "farm" {
                bs = Set(bm.map { Hit(q: $0.q, fr: $0.fr, x: $0.x, y: $0.y) })
                ds = Set(dm.filter { fxo - 20 <= $0.x && $0.x < fxo + fw + 20 && farmTop - 2 <= $0.y && $0.y < farmTop + 48 }
                    .map { Hit(q: $0.q, fr: $0.fr, x: $0.x - fxo, y: $0.y - farmTop) })
                bs = bs.filter(bandFarmOk)
                ds = ds.filter(bandFarmOk)
            } else {
                // home and camp alike: relative to the one Jeb, within reach to his left (the camp's Jeb stands where the home's does)
                let reach = 70
                bs = Set(bm.filter { bandJeb.x - reach <= $0.x && $0.x < bandJeb.x + 40 }.map { Hit(q: $0.q, fr: $0.fr, x: $0.x - bandJeb.x, y: $0.y - bandJeb.y) })
                ds = Set(dm.filter { homeJeb.x - reach <= $0.x && $0.x < campX + cw && campTop - 2 <= $0.y && $0.y < campTop + 48 }
                    .map { Hit(q: $0.q, fr: $0.fr, x: $0.x - homeJeb.x, y: $0.y - homeJeb.y) })
            }
            if bs != ds {
                ok = false
                notes.append("\(kind): band-only \(pyRepr(bs.subtracting(ds).sorted())) desktop-only \(pyRepr(ds.subtracting(bs).sorted()))")
            } else {
                notes.append("\(kind): \(bs.count) match")
            }
        case let .homeHas(want, notWant):
            // Desktop only: what the homestead's Jeb shows (these sprites and text there, those not).
            let dm = best(best(detect(at, png, want + notWant, "0.97"), JEB), BLUE)
            let got = Set(dm.filter { homeJeb.x - 200 <= $0.x && $0.x < fxo + fw && farmTop - 2 <= $0.y && $0.y < farmTop + 48 }.map { $0.q })
            let missing = want.filter { !got.contains($0) }, extra = notWant.filter { got.contains($0) }
            if !missing.isEmpty || !extra.isEmpty { ok = false }
            notes.append("home-has: " + (missing.isEmpty && extra.isEmpty ? "ok" : "missing \(pyRepr(missing)) unwanted \(pyRepr(extra))"))
        case let .sceneCount(fam, want):
            // Desktop only: how many of a family (Jeb's sprites, Blue's) the whole scene draws.
            let n = best(detect(at, png, fam, "0.97"), fam).count
            if n != want { ok = false }
            notes.append("scene-count \(fam[0].components(separatedBy: "-")[0]): \(n) (want \(want))")
        case let .absent(qs):
            // Desktop only: none of these anywhere in the scene (what the other sessions bring is not drawn).
            let found = detect(at, png, qs, "0.9").map { $0.q }
            if !found.isEmpty { ok = false }
            notes.append("absent: " + (found.isEmpty ? "ok" : "found \(pyRepr(Set(found).sorted()))"))
        case let .story(want):
            // Desktop only: the story's state as the bench reports it (place, phase, queue, destination, reason).
            let bad = want.filter { (story[$0.0] ?? "") != $0.1 }
            if !bad.isEmpty { ok = false }
            let shown = bad.map { "\(pyRepr($0.0)): (\(story[$0.0].map { pyRepr($0) } ?? "None"), \(pyRepr($0.1)))" }.joined(separator: ", ")
            notes.append("story: " + (bad.isEmpty ? "ok" : "got/want {\(shown)}"))
        case .areaTheme, .areaPlain:
            // Desktop only: a camp with a read area draws it (theme on, sprites placed, land and strip unlike the plain twin's);
            // one whose area does not read is drawn plain (theme off, the same picture as the twin's, and the same again on a re-render).
            let themed = at0.flatMap { Int($0[1]) } ?? -1, placed = at0.flatMap { Int($0[2]) } ?? -1
            let twin = at.out + "/" + name + ".plain.store.json"
            var st0 = Json.load(storePath) ?? .object([])
            st0.remove("areas")
            for (k, v) in st0.object ?? [] where k.hasPrefix("live:") {
                var r = v
                r.remove("area")
                st0.set(k, r)
            }
            writeFile(twin, st0.dumps())
            let stem = String(png.dropLast(4))
            let png2 = stem + ".plain.png", png3 = stem + ".again.png"
            bench(twin, png2)
            bench(storePath, png3)
            let sameAgain = bytes(png) != nil && bytes(png) == bytes(png3)
            let a = desk(), b = pngWords(at, png2)
            var land = 0, strip = 0
            for y in farmTop - 10..<farmTop { for x in 0..<SW where a[y * SW + x] != b[y * SW + x] { land += 1 } }
            for y in farmTop..<farmTop + 48 { for x in fxo..<fxo + fw where a[y * SW + x] != b[y * SW + x] { strip += 1 } }
            let good: Bool
            if case .areaTheme = check {
                good = themed == 1 && placed > 0 && land > 0 && strip > 0 && sameAgain
            } else {
                good = themed == 0 && placed == 0 && land == 0 && strip == 0 && bytes(png) == bytes(png2) && sameAgain
            }
            if !good { ok = false }
            notes.append("\(check.kind): theme \(themed) placed \(placed), land rows differ \(land), strip differs \(strip), same again \(sameAgain ? "True" : "False")")
        case let .places(want):
            if kind0 != want { ok = false }
            notes.append("places: \(kind0) (want \(want))")
        case .ridges:
            // The far ridge's flat colour fills a band of rows (14..24 above the stage strip) across the
            // whole picture: no hillside, speckle or pine tips reach up over the ridges.
            let px = desk()
            var counts: [Int32: Int] = [:]
            var total = 0
            for y in SH - (road + 48 + 24)...SH - (road + 48 + 14) { for x in 0..<SW { counts[px[y * SW + x], default: 0] += 1; total += 1 } }
            let frac = Double(counts.values.max() ?? 0) / Double(total)
            if frac < 0.97 { ok = false }
            notes.append("ridges: \(fixed(100 * frac, 1))% of the ridge band one flat colour")
        case let .mist(t8, x0, x1):
            // The fog's pattern over the homestead's sky rows (and the band's own, when its render is there).
            var good = [("desktop", mistOk(desk(), SW, fxo, farmTop, t8, x0, x1))]
            if w != 0 { good.append(("band", mistOk(pixelWords(braw), w, 0, 0, t8, x0, x1))) }
            for (_, frac) in good where frac < 0.9 { ok = false }
            notes.append("mist: " + good.map { "\($0.0) \(fixed(100 * $0.1, 0))%" }.joined(separator: ", "))
        case let .count(q, n):
            let bm = detect(at, braw, [q], "0.9"), dm = detect(at, png, [q], "0.9")
            let dcamp = dm.filter { campX - 10 <= $0.x && $0.x < campX + cw && campTop - 10 <= $0.y && $0.y < campTop + 48 }
            let dfarm = dm.filter { fxo - 20 <= $0.x && $0.x < fxo + fw && farmTop - 20 <= $0.y && $0.y < farmTop + 48 }
            let dn = max(dcamp.count, dfarm.count)
            if let n = n {
                if bm.count != n || dn != n { ok = false }
            } else if bm.isEmpty || dn == 0 {  // as many as fit: at least one in each
                ok = false
            }
            notes.append("count \(q): band \(bm.count) desktop \(dn)" + (n.map { " (want \($0))" } ?? " (as fit)"))
        case let .text(q):
            let bn = detect(at, braw, [q], "1.0").count, dn = detect(at, png, [q], "1.0").count
            if bn == 0 || dn == 0 { ok = false }
            notes.append("text \(q): band \(bn) desktop \(dn)")
        case .lanterns:
            let bn = detect(at, braw, ["lantern"], "0.9").count
            let dn = detect(at, png, ["lantern"], "0.9").filter { fxo <= $0.x && $0.x < fxo + fw && farmTop <= $0.y && $0.y < farmTop + 48 }.count
            // The band lights one for each OTHER session; the homestead one for each session but the one acted out here.
            if dn != bn { ok = false }
            notes.append("lanterns: band \(bn) (others) desktop \(dn)")
        case let .bubble(dim):
            // The bubble: the band's own wrap at the room each has (the band's is cut short by the
            // sign; the homestead's, with the one Jeb, has the full 30), its box's right edge at Jeb - 1, text 3 in, 3 down.
            let line = f.live[0]["line"]?.string ?? ""
            let ink = dim ? "grey" : "ink"
            var verdict: [String] = []
            for (img, jx, top, chars) in [(braw, bandJeb.x, 0, nil as Int?), (png, homeJeb.x, farmTop, 30)] {
                var good = false
                for c in chars.map({ [$0] }) ?? Array(stride(from: 30, to: 7, by: -1)) {
                    let lines = bubbleLines(line, c)
                    let tw = lines.map { $0.count * 4 - 1 }.max() ?? 0
                    let wantX = jx - 1 - (tw + 6) + 3
                    let hits = lines.map { detect(at, img, ["text:\(ink):\($0)"], "1.0") }
                    if hits.enumerated().allSatisfy({ i, hs in hs.contains { $0.x == wantX && $0.y == top + 4 + i * 6 } }) {
                        good = true
                        verdict.append("\(c) chars \(pyRepr(lines))")
                        break
                    }
                }
                ok = ok && good
                if !good { verdict.append("not found") }
            }
            notes.append("bubble: band " + verdict[0] + "; desktop " + (verdict.count > 1 ? verdict[1] : "-"))
        case let .pixels(x0, y0, x1, y1):
            // The farm's pixels themselves: every opaque band pixel in the box the same on the homestead.
            let bpx = pixelWords(braw), dpx = desk()
            let back = bandBackdrop(w, f.now, art)
            var same = 0, total = 0
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let b = bpx[y * w + x]
                    if b < 0 || b == back[y * w + x] { continue }
                    total += 1
                    if dpx[(farmTop + y) * SW + fxo + x] == b { same += 1 }
                }
            }
            let frac = Double(same) / Double(max(1, total))
            ok = ok && frac >= 0.97
            notes.append("pixels \(x0),\(y0)-\(x1),\(y1): \(fixed(100 * frac, 1))% of \(total) the same")
        case let .tint(colour, rgb):
            let c = art.colour(colour)
            let t = Int32(((c & 255) * 3 + rgb.0) >> 2 | (((c >> 8 & 255) * 3 + rgb.1) >> 2) << 8 | (((c >> 16 & 255) * 3 + rgb.2) >> 2) << 16)
            let bn = pixelWords(braw).filter { $0 == t }.count, dn = desk().filter { $0 == t }.count
            ok = ok && bn > 0 && dn > 0
            notes.append("tinted \(colour): band \(bn) px, desktop \(dn) px")
        case .lane, .walk:
            // Along the way: the same progress along each one's own lane (the camp lane is shorter).
            let q: String, bx: Int, dx: Int
            switch check {
            case let .lane(sprite, x, reach, sw, _):
                q = sprite
                let rig = sw == 14 ? sw : 40
                let bstop = bandJeb.x - 20 - rig - 6, dstop = (fw - 113 - 20) - rig - 6
                bx = pyRound(Double(-sw) + Double((bstop + sw) * x) / Double(reach))
                dx = pyRound(Double(-sw) + Double((dstop + sw) * x) / Double(reach)) + campX
            case let .walk(sprite, p):
                q = sprite
                bx = pyRound(p / 0.5 * Double(bandJeb.x - 18))
                dx = pyRound(p / 0.5 * Double(fw - 113 - 18)) + campX
            default: continue
            }
            let dm = detect(at, png, [q], "0.9").filter { campX - 60 <= $0.x && $0.x < campX + cw && campTop - 2 <= $0.y && $0.y < campTop + 48 }
            let bm = detect(at, braw, [q], "0.9")
            let bh = bm.filter { abs($0.x - bx) <= 1 }, dh = dm.filter { abs($0.x - dx) <= 2 }
            ok = ok && bh.count >= 1 && dh.count >= 1 && bh[0].fl == dh[0].fl
            notes.append("\(q) along the way: band at \(bx) \(bh.isEmpty ? "missing" : "found"), desktop at \(dx - campX) \(dh.isEmpty ? "missing" : "found")")
        case .dry:
            let bpx = pixelWords(braw), dpx = desk()
            let dry = Int32(art.colour("soil_dry"))
            var bn = 0, dn = 0
            for y in 37..<40 { for x in 0..<w where bpx[y * w + x] == dry { bn += 1 } }
            for y in campTop + 37..<campTop + 40 { for x in campX + 4..<campX + 24 where dpx[y * SW + x] == dry { dn += 1 } }
            ok = ok && bn > 0 && dn > 0
            notes.append("band soil_dry pixels \(bn), camp tobacco soil_dry pixels \(dn)")
        }
    }
    return [name, f.rows, ok ? "pass" : "FAIL", notes.joined(separator: "; ")]
}

/// The band's own wrap of a spoken line: two lines of `chars` at most, the second cut with "..".
func bubbleLines(_ line: String, _ chars: Int = 30) -> [String] {
    var q = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    func cut(_ w: String) -> String { String(w.prefix(max(0, chars - 2))) + ".." }
    var lines = [""]
    while !q.isEmpty {
        let w = q.removeFirst(), cur = lines[lines.count - 1]
        if lines.count == 1 && cur.isEmpty && w.count > chars {
            lines[0] = String(w.prefix(chars))
            q.insert(String(w.dropFirst(chars)), at: 0)
            lines.append("")
            continue
        }
        let nxt = cur.isEmpty ? w : cur + " " + w
        if nxt.count <= chars { lines[lines.count - 1] = nxt }
        else if lines.count < 2 {
            lines.append(w.count > chars ? cut(w) : w)
            if w.count > chars { break }
        } else if cur.isEmpty {
            lines[1] = cut(w)
            break
        } else {
            var head = cur.count + 2 <= chars ? cur : String(cur.prefix(max(0, chars - 2)))
            while let l = head.last, l.isWhitespace { head.removeLast() }
            lines[1] = head + ".."
            break
        }
    }
    return lines.filter { !$0.isEmpty }
}

/// The band's ridges and road (pixel-scene.ts paintBackdrop, paintRoad), to tell its sprites from its backdrop.
func bandBackdrop(_ w: Int, _ nowMs: Int, _ art: ArtInfo) -> [Int32] {
    let t = localTime(Double(nowMs) / 1000)
    let m = Int(t.tm_mon), hour = Int(t.tm_hour)
    let night = hour >= 21 || hour < 6
    let season = m <= 1 || m == 11 ? "winter" : m <= 4 ? "spring" : m <= 7 ? "summer" : "fall"
    let peak = season == "fall" && m == 9
    let morning = !night && 6 <= hour && hour < 9
    func col(_ n: String) -> Int32 { Int32(art.colour(n)) }
    let H = 48, G = H - 9
    var px = [Int32](repeating: -1, count: w * H)
    func sp(_ x: Int, _ y: Int) -> Int { (((x * 73856093) ^ (y * 19349663)) & 0xffffffff) % 100 }
    func farR(_ x: Int) -> Int { let v = Double(x); return pyRound(15 + 4 * sin(v / 37) + 3 * sin(v / 13 + 1.3) + 2 * sin(v / 71 + 0.4)) }
    func midR(_ x: Int) -> Int { let v = Double(x); return pyRound(28 + 2 * sin(v / 23 + 2) + 1 * sin(v / 9) + 1.5 * sin(v / 51 + 1)) }
    let FOL = [col("foliage_orange"), col("foliage_red"), col("foliage_gold")]
    let ridgeFar = col(night ? "ridge_far_night" : "ridge_far"), ridgeMid = col(night ? "ridge_mid_night" : "ridge_mid")
    let snowcap = col("snowcap"), leaf = col("leaf"), pine = col("pine"), fog = col("fog")
    for x in 0..<w {
        let far = max(6, min(G - 6, farR(x))), mid = max(far + 4, min(G - 2, midR(x)))
        for y in far..<G { px[y * w + x] = ridgeFar }
        if season == "winter" && far <= 13 {
            px[far * w + x] = snowcap
            if far <= 10 { px[(far + 1) * w + x] = snowcap }
        }
        for y in mid..<G {
            var word = ridgeMid
            let roll = sp(x, y)
            if !night {
                if season == "fall" && roll < (peak ? 20 : 10) { word = FOL[roll % 3] }
                else if season == "spring" && roll < 12 { word = leaf }
                else if season == "summer" && roll < 15 { word = pine }
            }
            px[y * w + x] = word
        }
        if sp(x, 7) < 18 && mid - 2 > far {
            let tip = night ? ridgeMid : season == "winter" ? snowcap : pine
            px[(mid - 1) * w + x] = tip
            if sp(x, 11) < 50 { px[(mid - 2) * w + x] = tip }
        }
        if season == "winter" && !night && sp(x, 3) < 30 { px[mid * w + x] = snowcap }
        if morning && (x + x / 9) % 3 != 0 { px[(G - 2) * w + x] = fog }
    }
    func rut(_ x: Int, _ k: Int) -> Int { let v = Double(x), j = Double(k); return max(-1, min(1, pyRound(sin(v / 7 + j * 2.1) + 0.6 * sin(v / 3.3 + j)))) }
    let grass = col("grass"), dirt = col("dirt"), dirtLight = col("dirt_light"), dirtDark = col("dirt_dark"), pebble = col("pebble")
    for x in 0..<w {
        px[G * w + x] = grass
        for y in G + 1..<H {
            let roll = sp(x, y + 200)
            px[y * w + x] = roll < 9 ? dirtLight : roll < 15 ? dirtDark : dirt
        }
        px[(42 + rut(x, 0)) * w + x] = dirtDark
        px[(46 + rut(x, 1)) * w + x] = dirtDark
        if sp(x, 77) < 3 {
            let y = G + 1 + sp(x, 78) % 8
            px[y * w + x] = pebble
            if sp(x, 79) < 45 && x + 1 < w { px[y * w + x + 1] = pebble }
        }
        if sp(x, 5) < 8 {
            px[(G - 1) * w + x] = grass
            if sp(x, 6) < 50 { px[(G - 2) * w + x] = leaf }
        }
    }
    return px
}

/// Share of fogged pixels (rows 2..17, the open sky above the crops; columns x0..x1 of a strip at (ox, oy) in a picture
/// W wide) that are the half-and-half mix of the mist colour over one of the gap pixels (where the pattern leaves
/// a gap) within eight columns of it in the same row: the ground behind is speckled, so a near one, not the next.
func mistOk(_ px: [Int32], _ W: Int, _ ox: Int, _ oy: Int, _ t8: Int, _ x0: Int, _ x1: Int) -> Double {
    let mist = [215, 222, 232]
    func rgb(_ a: Int32) -> [Int] { [Int(a) & 255, Int(a) >> 8 & 255, Int(a) >> 16 & 255] }
    var good = 0, total = 0
    for y in 2..<18 {
        for x in x0 + 8..<x1 - 8 {
            if (x + y + t8) % 3 == 0 { continue }
            let a = px[(oy + y) * W + ox + x]
            if a < 0 { continue }
            total += 1
            let mine = rgb(a)
            for k in x - 8..<x + 9 where (k + y + t8) % 3 == 0 && px[(oy + y) * W + ox + k] >= 0 {
                let under = rgb(px[(oy + y) * W + ox + k])
                if (0..<3).allSatisfy({ abs((under[$0] + mist[$0]) / 2 - mine[$0]) <= 3 }) { good += 1; break }
            }
        }
    }
    return Double(good) / Double(max(1, total))
}
