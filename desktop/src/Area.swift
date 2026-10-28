// A project's area (the mod's hooks/areas.ts), read from the store's `areas` key and
// nothing else of the mod's area data. Read strictly, as a live record is: every
// field is checked against its fixed set, range or shape, and an area with any bad
// enum or bad required field is dropped whole (the camp is then drawn plain). Keys
// that are not in the area's fixed shape are never kept. The free text (lore and
// the beats' lines) is plain printable ASCII, at most 64 characters, with none of
// @ # ` < > { } and no address in it; it is display-only and goes through the
// story's bubble (its own 3x5 font) and nowhere else.

import Foundation

struct AreaBeat: Equatable { let line: String, prop: String?, zone: String }

struct Area: Equatable {
    static let mades: Set<String> = ["model", "offline"]
    static let terrains: Set<String> = ["holler", "ridge", "creek", "orchard", "meadow", "quarry", "woods", "bottomland", "bald", "mill"]
    static let palettes: Set<String> = ["moss", "amber", "slate", "rose", "ember", "frost", "dusk", "clay"]
    static let weathers: Set<String> = ["clear", "fog", "drizzle", "breeze", "hazy", "snowy"]
    static let moods: Set<String> = ["dawn", "noon", "gold", "dusk", "night"]
    static let motifs: Set<String> = ["bird", "fire", "water", "light", "song", "wind"]
    static let spriteCap = 8     // distinct sprite names in one area (its props and its beats' props)
    static let keep = 24         // areas read

    let made: String
    let day: String, seen: String
    let name: String
    let terrain: String, palette: String, weather: String, mood: String, motif: String
    let props: [String]
    let lore: [String]
    let beats: [AreaBeat]

    init?(_ d: [String: Any]) {
        func pick(_ key: String, _ set: Set<String>) -> String? {
            guard let s = d[key] as? String, set.contains(s) else { return nil }
            return s
        }
        guard (d["v"] as? NSNumber)?.intValue == 1, let made = pick("made", Self.mades),
              let day = d["day"] as? String, dateOfKey(day) != nil, let seen = d["seen"] as? String, dateOfKey(seen) != nil,
              let name = d["name"] as? String, isAreaName(name),
              let terrain = pick("terrain", Self.terrains), let palette = pick("palette", Self.palettes), let weather = pick("weather", Self.weathers),
              let mood = pick("mood", Self.moods), let motif = pick("motif", Self.motifs),
              let rawProps = d["props"] as? [Any], (3...5).contains(rawProps.count),
              let rawLore = d["lore"] as? [Any], (2...4).contains(rawLore.count),
              let rawBeats = d["beats"] as? [Any], (3...6).contains(rawBeats.count) else { return nil }
        var props: [String] = []
        for p in rawProps {
            guard let s = p as? String, dropSpriteNames[s] != nil else { return nil }
            props.append(s)
        }
        var lore: [String] = []
        for l in rawLore {
            guard let s = l as? String, isAreaText(s) else { return nil }
            lore.append(s)
        }
        var beats: [AreaBeat] = []
        for b in rawBeats {
            guard let o = b as? [String: Any], let line = o["line"] as? String, isAreaText(line), let zone = o["zone"] as? String, DropSprite.zones.contains(zone) else { return nil }
            var prop: String?
            if let raw = o["prop"], !(raw is NSNull) {
                guard let s = raw as? String, dropSpriteNames[s] != nil else { return nil }
                prop = s
            }
            beats.append(AreaBeat(line: line, prop: prop, zone: zone))
        }
        guard Set(props + beats.compactMap(\.prop)).count <= Self.spriteCap else { return nil }
        self.made = made; self.day = day; self.seen = seen; self.name = name
        self.terrain = terrain; self.palette = palette; self.weather = weather; self.mood = mood; self.motif = motif
        self.props = props; self.lore = lore; self.beats = beats
    }
}

typealias Areas = [String: Area]

/// The areas read from the store's `areas` object: keys are 8 lowercase hex, an area that does not read is left out,
/// and at most 24 are kept (by key order, so every window and every read agrees).
func readAreas(_ object: [String: Any]) -> Areas {
    var out: Areas = [:]
    for key in object.keys.sorted() {
        guard out.count < Area.keep, isAreaKey(key), let d = object[key] as? [String: Any], let area = Area(d) else { continue }
        out[key] = area
    }
    return out
}

/// 8 lowercase hex characters.
func isAreaKey(_ s: String) -> Bool {
    s.utf8.count == 8 && s.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
}

/// Letters and spaces, 1 to 16, with a letter in it.
func isAreaName(_ s: String) -> Bool {
    (1...16).contains(s.utf8.count) && s.utf8.allSatisfy { $0 == 0x20 || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }
        && s.contains { $0 != " " }
}

/// One line of an area's text: printable ASCII, 1 to 64, none of @ # ` < > { }, no address.
func isAreaText(_ s: String) -> Bool {
    guard (1...64).contains(s.utf8.count), s.utf8.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E && !"@#`<>{}".utf8.contains($0) }),
          s.contains(where: { $0 != " " }) else { return false }
    let low = s.lowercased()
    return !low.contains("://") && !low.contains("www.")
}

private let dayFormat: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = .current
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

/// A real 'YYYY-MM-DD' day (local), or nil.
func dateOfKey(_ s: String) -> Date? { isDateKey(s) ? dayFormat.date(from: s) : nil }

// MARK: - The look

/// What a camp is drawn as when its record names an area that is read: the area and its key.
struct AreaTheme: Equatable {
    let key: String
    let area: Area
    /// What a repaint keys on.
    var tag: String { "\(key)|\(area.terrain)|\(area.palette)|\(area.weather)|\(area.mood)|\(area.motif)" }

    /// The existing colour each palette leans toward (art.colour names).
    static let paletteColour = ["moss": "leaf", "amber": "amber", "slate": "stone", "rose": "pink", "ember": "red", "frost": "snowcap", "dusk": "purple", "clay": "dirt"]
    /// The existing colour a terrain speckles the hillside with, and how far the hill's crest lifts.
    static let terrainColour = ["holler": "pine", "ridge": "stone", "creek": "water", "orchard": "foliage_red", "meadow": "yellow", "quarry": "grey",
                                "woods": "green_dark", "bottomland": "leaf", "bald": "dirt_light", "mill": "wood"]
    static let terrainRise = ["holler": 1, "ridge": 1, "creek": -1, "orchard": 0, "meadow": -1, "quarry": 1, "woods": 1, "bottomland": -1, "bald": 0, "mill": 0]
    /// The existing colour a mood warms or cools the land toward, and how much.
    static let moodMix: [String: (String, Double)] = ["dawn": ("pink", 0.10), "noon": ("white", 0.05), "gold": ("amber", 0.14), "dusk": ("purple", 0.14), "night": ("ink", 0.22)]

    /// Where each existing sprite stands: in the sky, the yard, or on the field.
    static let skySprites: Set<String> = ["cardinal", "bluebird", "butterfly", "firefly", "cloud", "rainbow", "star", "parachute", "owl", "bell"]
    static let yardSprites: Set<String> = ["cow", "hen", "pup", "turkey", "groundhog", "deer", "puddle", "tractor"]
    func zone(of sprite: String) -> String {
        if Self.skySprites.contains(sprite) { return "sky" }
        if Self.yardSprites.contains(sprite) { return "yard" }
        return ["field", "porch", "yard"][Int(hashOf("\(key)\(sprite)") % 3)]
    }
    /// The motif's own sprite, one more in the area's sky when the area has room for another distinct sprite.
    static let motifSprite = ["bird": "bluebird", "fire": "lantern", "water": "puddle", "light": "firefly", "song": "note", "wind": "cloud"]

    /// The sprites this area stands in its camp: its props where their kind stands, its beats' props at their zones, the motif.
    var drops: [DropSprite] {
        var out: [DropSprite] = []
        var names = Set<String>()
        func add(_ s: String, _ zone: String) {
            guard out.count < Area.spriteCap, names.contains(s) || names.count < Area.spriteCap else { return }
            names.insert(s)
            out.append(DropSprite(sprite: s, zone: zone, frames: 1))
        }
        for p in area.props { add(p, zone(of: p)) }
        for b in area.beats { if let p = b.prop { add(p, b.zone) } }
        if let m = Self.motifSprite[area.motif], names.count < Area.spriteCap { add(m, "sky") }
        return out
    }
}
