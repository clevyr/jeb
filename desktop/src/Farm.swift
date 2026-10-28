// What the desktop draws from the store's `farm` key: the band's FarmView
// (hooks/scene.ts viewOf), and nothing else. Within `farm` only the fields below
// are taken, each type-checked and capped; names, camps, journal lines, sayings
// and summaries are never read. Strings kept are ids from fixed sets (upgrades,
// builds, unlocks, sprite names, zones, tints) or dates, all checked by shape.

import Foundation

let cropNames = ["tobacco", "corn", "apples"]
let cropLabels = ["tobacco": "TOBACCO", "corn": "CORN", "apples": "APPLES"]

/// A creative drop's sprite placement: a built-in sprite name or a custom picture's id.
struct DropSprite: Equatable {
    let sprite: String, zone: String, frames: Int
    static let zones: Set<String> = ["yard", "sky", "porch", "field", "road"]
    init?(_ raw: Any?) {
        guard let d = raw as? [String: Any], let s = d["sprite"] as? String, isArtId(s, max: 20),
              let z = d["zone"] as? String, Self.zones.contains(z) else { return nil }
        let f = (d["frames"] as? NSNumber)?.intValue ?? 1
        guard f == 1 || f == 2 else { return nil }
        sprite = s; zone = z; frames = f
    }
    init(sprite: String, zone: String, frames: Int) { self.sprite = sprite; self.zone = zone; self.frames = frames }
}

/// A custom picture: `rows` holds h * frames strings of w legend characters (see surprise.ts).
struct DropArt: Equatable {
    let id: String, w: Int, h: Int, frames: Int
    let rows: [String]
    static let legend: [Character: String] = [
        "k": "ink", "w": "white", "g": "grey", "s": "stone", "r": "red", "d": "red_dark", "y": "yellow", "a": "amber",
        "b": "drop", "e": "water", "n": "green", "N": "green_dark", "l": "leaf", "p": "pine", "o": "wood", "O": "wood_dark",
        "t": "dirt", "i": "pink", "u": "purple", "f": "skin", "m": "denim", "c": "corn", "h": "hair_dark", "q": "copper",
    ]
    init?(_ raw: Any?) {
        guard let d = raw as? [String: Any], let id = d["id"] as? String, isArtId(id, max: 20),
              let w = (d["w"] as? NSNumber)?.intValue, let h = (d["h"] as? NSNumber)?.intValue,
              (3...24).contains(w), (3...24).contains(h) else { return nil }
        let frames = (d["frames"] as? NSNumber)?.intValue ?? 1
        guard frames == 1 || frames == 2, let rows = d["rows"] as? [String], rows.count == h * frames,
              rows.allSatisfy({ $0.count == w && $0.allSatisfy { $0 == "." || Self.legend[$0] != nil } }) else { return nil }
        self.id = id; self.w = w; self.h = h; self.frames = frames; self.rows = rows
    }
}

/// Lowercase letters, digits and dashes only.
func isArtId(_ s: String, max: Int) -> Bool {
    (1...max).contains(s.utf8.count) && s.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x2D }
}

/// 'YYYY-MM-DD' or ''.
func isDateKey(_ s: String) -> Bool {
    s.utf8.count == 10 && s.enumerated().allSatisfy { i, c in i == 4 || i == 7 ? c == "-" : c.isASCII && c.isNumber }
}

func dateKeyOf(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

/// Whole days from one date key to another (local calendar).
func daysBetween(_ from: String, _ to: String) -> Int {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
    guard let a = f.date(from: from), let b = f.date(from: to) else { return Int.max }
    return Calendar.current.dateComponents([.day], from: a, to: b).day ?? Int.max
}

struct Decor: Equatable { let day: String; let sprites: [DropSprite]; let window: (from: Int, to: Int)?; let lasts: String
    static func == (a: Decor, b: Decor) -> Bool { a.day == b.day && a.sprites == b.sprites && a.window?.from == b.window?.from && a.window?.to == b.window?.to && a.lasts == b.lasts }
}

struct Farm: Equatable {
    var crops: [String: [Int]] = [:]
    var upgrades: Set<String> = []
    var built: Set<String> = []
    var barn: [String: Int] = [:]   // tobacco counts every bale ever cut, as the band does
    var jars = 0, cash = 0
    var materials: [String: Int] = [:]
    var appleButter = 0, twists = 0, whiskey = 0
    var aged: [Double] = []          // ms each aging jar is ready
    var quilt: [String] = []         // the last ten squares' colour codes
    var unlocks: [String] = []
    var pile = 1, coffee = "", since = ""
    var decor: [Decor] = []
    var structures: [[DropSprite]] = []
    var art: [DropArt] = []
    var festival = (d: "", tint: "")

    static let materialOrder = ["lumber", "stone", "straw", "iron", "sugar", "copper"]
    static let upgradeIds: Set<String> = ["mailbox", "chair", "hen", "pup", "coat", "still2"]
    static let squareCodes: Set<String> = ["B", "R", "G", "P", "Y", "N"]
    static let tints: [String: (Int, Int, Int)] = ["gold": (255, 200, 80), "rose": (240, 130, 150), "mint": (130, 220, 170), "sky": (120, 180, 240), "dusk": (170, 130, 220)]
    static let stockCap = 100

    init() {}
    init(_ farm: [String: Any]) {
        let dict = { (key: String) in farm[key] as? [String: Any] ?? [:] }
        let int = { (d: [String: Any], key: String) in max(0, min(1_000_000_000, (d[key] as? NSNumber)?.intValue ?? 0)) }
        let ids = { (key: String, max: Int) in ((farm[key] as? [Any]) ?? []).compactMap { $0 as? String }.filter { isArtId($0.lowercased(), max: 24) }.prefix(max) }
        for crop in cropNames {
            crops[crop] = ((dict("crops")[crop] as? [Any]) ?? []).prefix(8).map { max(0, min(3, ($0 as? NSNumber)?.intValue ?? 0)) }
        }
        upgrades = Set(ids("upgrades", 32))
        built = Set(ids("built", 32))
        barn = ["tobacco": int(dict("lifetime"), "bales"), "corn": int(dict("barn"), "corn"), "apples": int(dict("barn"), "apples")]
        jars = int(dict("shelf"), "appleCinnamon")
        cash = int(dict("ledger"), "cash")
        let rawMaterials = dict("materials"), goods = dict("goods")
        let rawAged = ((goods["aged"] as? [Any]) ?? []).prefix(50).compactMap { (($0 as? [String: Any])?["readyAt"] as? NSNumber)?.doubleValue }
        // viewOf's stackStock: past the cap only the shown columns keep their counts,
        // and those only while the stack is crowded (more than five piles at the cap).
        let rawStock = Self.materialOrder.map { ($0, int(rawMaterials, $0)) }
            + [("appleButter", int(goods, "appleButter")), ("twists", int(goods, "twists")), ("whiskey", int(goods, "whiskey"))]
        let counts = rawStock.map(\.1).dropLast() + [int(goods, "whiskey") + rawAged.count]
        let isCrowded = counts.filter { $0 >= Self.stockCap }.count > 5
        let shown = Set(Self.columns(of: rawStock).map(\.id))
        let keep = { (id: String, n: Int) in shown.contains(id) ? (isCrowded ? n : min(n, Self.stockCap)) : 0 }
        for (id, n) in rawStock.prefix(6) { materials[id] = keep(id, n) }
        appleButter = keep("appleButter", int(goods, "appleButter"))
        twists = keep("twists", int(goods, "twists"))
        whiskey = isCrowded ? int(goods, "whiskey") : min(int(goods, "whiskey"), Self.stockCap)
        aged = rawAged
        quilt = ((farm["quilt"] as? [Any]) ?? []).suffix(10).compactMap { ($0 as? [String: Any])?["c"] as? String }.filter { Self.squareCodes.contains($0) }
        unlocks = Array(ids("unlocks", 64))
        let lumber = int(rawMaterials, "lumber")
        pile = 1 + (lumber >= 5 ? 1 : 0) + (lumber >= 20 ? 1 : 0) + (lumber >= 50 ? 1 : 0)
        let day = dict("unlockDay")
        coffee = (day["coffee"] as? String).flatMap { isDateKey($0) ? $0 : nil } ?? ""
        since = (day["since"] as? String).flatMap { isDateKey($0) ? $0 : nil } ?? ""

        // The creative drops (drops.ts viewOfDrops): decor with sprites, structures, the art they name, the festival.
        for item in ((farm["surprises"] as? [Any]) ?? []).prefix(30) {
            guard let s = item as? [String: Any], (s["kind"] as? String) == "decor", let day = s["day"] as? String, isDateKey(day) else { continue }
            let sprites = ((s["sprites"] as? [Any]) ?? []).prefix(3).compactMap(DropSprite.init)
            guard !sprites.isEmpty else { continue }
            var window: (Int, Int)?
            if let w = s["window"] as? [String: Any], let a = (w["from"] as? NSNumber)?.intValue, let b = (w["to"] as? NSNumber)?.intValue, (0...24).contains(a), (0...24).contains(b) { window = (a, b) }
            let lasts = (s["lasts"] as? String) == "week" ? "week" : "today"
            decor.append(Decor(day: day, sprites: Array(sprites), window: window, lasts: lasts))
        }
        let creative = dict("creative")
        structures = ((creative["structures"] as? [Any]) ?? []).prefix(12).compactMap { item in
            let sprites = (((item as? [String: Any])?["sprites"] as? [Any]) ?? []).prefix(3).compactMap(DropSprite.init)
            return sprites.isEmpty ? nil : Array(sprites)
        }
        let named = Set((decor.flatMap(\.sprites) + structures.flatMap { $0 }).map(\.sprite))
        art = ((creative["art"] as? [Any]) ?? []).prefix(16).compactMap(DropArt.init).filter { named.contains($0.id) }
        if let f = creative["festival"] as? [String: Any], let d = f["d"] as? String, isDateKey(d), let t = f["tint"] as? String, Self.tints[t] != nil {
            festival = (d, t)
        }
    }

    func stage(_ crop: String, _ i: Int) -> Int {
        guard let stages = crops[crop], stages.indices.contains(i) else { return 0 }
        return max(0, min(3, stages[i]))
    }

    /// The five biggest piles (ties by order), kept in order (crafting.ts stackColumns).
    static func columns(of stock: [(String, Int)]) -> [(id: String, count: Int)] {
        let stocked = stock.enumerated().filter { $0.element.1 > 0 }
        let top = Set(stocked.sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }.prefix(5).map(\.offset))
        return stocked.filter { top.contains($0.offset) }.map { (id: $0.element.0, count: $0.element.1) }
    }

    /// The stack as the clock leaves it: aged jars that are ready count as whiskey.
    func columns(now: Date) -> [(id: String, count: Int)] {
        let ready = aged.filter { $0 <= now.timeIntervalSince1970 * 1000 }.count
        let stock = Self.materialOrder.map { ($0, materials[$0] ?? 0) } + [("appleButter", appleButter), ("twists", twists), ("whiskey", whiskey + ready)]
        return Self.columns(of: stock)
    }

    /// The creative sprites on show now (drops.ts dropLooks): structures, then live decor in its hours; at most 8.
    func dropLooks(now: Date) -> [(sprite: DropSprite, art: DropArt?)] {
        let today = dateKeyOf(now), hour = Calendar.current.component(.hour, from: now)
        var out: [(sprite: DropSprite, art: DropArt?)] = []
        func add(_ s: DropSprite) {
            let custom = art.first { $0.id == s.sprite }
            guard dropSpriteNames[s.sprite] != nil || custom != nil, out.count < 8 else { return }
            out.append((s, custom))
        }
        structures.forEach { $0.forEach(add) }
        for item in decor {
            let age = daysBetween(item.day, today)
            let live = item.lasts == "week" ? age >= 0 && age < 7 : age == 0
            if live && (item.window.map { hour >= $0.from && hour < $0.to } ?? true) { item.sprites.forEach(add) }
        }
        return out
    }

    func festivalTint(now: Date) -> String { festival.d != "" && festival.d == dateKeyOf(now) ? festival.tint : "" }

    static func == (a: Farm, b: Farm) -> Bool {
        a.crops == b.crops && a.upgrades == b.upgrades && a.built == b.built && a.barn == b.barn && a.jars == b.jars && a.cash == b.cash
            && a.materials == b.materials && a.appleButter == b.appleButter && a.twists == b.twists && a.whiskey == b.whiskey && a.aged == b.aged
            && a.quilt == b.quilt && a.unlocks == b.unlocks && a.pile == b.pile && a.coffee == b.coffee && a.since == b.since
            && a.decor == b.decor && a.structures == b.structures && a.art == b.art && a.festival == b.festival
    }
}

/// The creative drops' built-in allowlist (surprise.ts DROP_SPRITES): id -> art name.
let dropSpriteNames: [String: String] = [
    "cow": "cow", "hen": "hen", "pup": "pup", "turkey": "turkey", "groundhog": "groundhog", "deer": "deer", "cardinal": "cardinal",
    "bluebird": "bluebird", "owl": "owl", "butterfly": "butterfly", "firefly": "firefly", "mug": "mug", "lunch": "lunch",
    "postcard": "postcard", "cake": "cake", "rainbow": "rainbow", "puddle": "puddle", "star": "star-streak", "bell": "prop-bell",
    "parachute": "prop-parachute", "lantern": "lantern", "cloud": "cloud", "birdhouse": "birdhouse", "jar": "icon-jar",
    "cash": "icon-cash", "apples": "icon-apples", "corn": "icon-corn", "bale": "icon-bale", "lumber": "icon-lumber",
    "stone": "icon-stone", "sugar": "icon-sugar", "note": "note", "heart": "heart", "opal": "opal", "tractor": "rig-tractor",
]
