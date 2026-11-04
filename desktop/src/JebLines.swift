// What Jeb says on a banner: his lines for an update result and for a holiday greeting, picked by a stable hash so the
// same event always reads the same, plus when a greeting is due and the notification preferences file. Pure Foundation, so a
// scratch harness can compile it with Holiday.swift and UpdateStatus.swift. See UpdateNotifier.swift for the use.

import Foundation

enum UpdateNews: Equatable { case upToDate(String?), updated(String), failed(String), rolledBack(String), error(String) }

/// How a result reads: the banner's tab colour (a holiday's own colour overrides it).
enum Tone { case good, bad, plain }

/// One banner: the exact fact goes in the subtitle, Jeb's line in the body, and `sprite` picks the pose beside them. `holiday`
/// is set only when the holiday's own line was used. The title keeps the emoji (VoiceOver and logs); the banner draws none.
struct Note: Equatable { var title: String; var subtitle: String; var body: String; var sprite: String; var sound = true; var tone: Tone = .plain; var holiday: String? }

enum JebLines {
    /// FNV-1a 64 over the UTF-8 bytes (Hasher is seeded per process, so it can never pick a line).
    static func fnv(_ s: String) -> UInt64 {
        s.utf8.reduce(0xcbf29ce484222325) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
    }

    static func pick(_ lines: [String], _ seed: String) -> String { lines[Int(fnv(seed) % UInt64(lines.count))] }

    static let emoji = ["newyear": "🥂", "valentines": "💘", "stpatricks": "☘️", "easter": "🐣", "july4": "🎆", "halloween": "🎃", "thanksgiving": "🦃", "christmas": "🎄", "none": ""]
    static let greetingName = ["newyear": "Happy New Year", "valentines": "Happy Valentine's Day", "stpatricks": "Happy St. Patrick's Day", "easter": "Happy Easter",
                               "july4": "Happy Fourth of July", "halloween": "Happy Halloween", "thanksgiving": "Happy Thanksgiving", "christmas": "Merry Christmas"]

    private static let upToDate = ["Nothin' new. Same jar as yesterday.", "Checked the still. Same batch.", "Rows are hoed. Nothin' to plant.", "Nothin' come down the road.", "Sit a spell. Work'll keep."]
    private static let updated = ["That'll do. Pour you a jar?", "Done and dusted.", "Another row hoed.", "Fresh batch, bottled up.", "Swapped her out. Runs smooth."]
    private static let failed = ["Well, that went sideways.", "Batch went sour. Dumpin' the mash.", "That dog won't hunt.", "Hornworms got into that one.", "Kept the old jar."]
    private static let rolledBack = ["That one bucked like a mule.", "Didn't take. Old one's back.", "Sour as a green persimmon.", "Tried it. Went back to what works."]
    private static let error = ["Couldn't get down the road.", "Truck won't start. Try later.", "Creek rose. Couldn't get through.", "Lord willin', next time."]

    /// Per holiday: lines for a good result (updated, up to date), then for a bad one.
    private static let holidayLines: [String: (good: [String], bad: [String])] = [
        "newyear": (["New year. Same holler. New jar.", "Rung in a fresh one. Happy new year."], ["New year, same old snag.", "Year's young. That one ain't."]),
        "valentines": (["Tied a red ribbon on this one.", "Sweet as sorghum. All done."], ["Ain't sweet on this one.", "Heart's broke. Kept the old one."]),
        "stpatricks": (["Luck held. Green as clover.", "Found a four-leaf one. Done."], ["Luck ran dry.", "Leprechaun swiped that one."]),
        "easter": (["Found this one in the tall grass.", "Hatched a fresh one."], ["Egg's cracked.", "Fox got in the henhouse."]),
        "july4": (["Went off like a bottle rocket.", "Fireworks in the holler. All set."], ["Dud. Fizzled in the yard.", "Wet powder. Kept the old one."]),
        "halloween": (["Pumpkins in, fresh batch in the jar.", "Ghosts approve. Fresh batch is in."], ["Somethin' spooky got in the mash.", "Mind the ghosts. This one's haunted."]),
        "thanksgiving": (["Somethin' to be thankful for.", "Set the table. New one's served."], ["Turkey's dry. Kept the old one.", "Burnt the rolls. Kept the old one."]),
        "christmas": (["Tree's up. New one's under it.", "Sleigh bells. Fresh one's in."], ["Coal in the stockin' this year.", "Stockin's empty. Kept the old one."]),
    ]

    private static let greetings = [
        "newyear": ["New year. Same holler.", "Rung in the year. Blue slept through."],
        "valentines": ["Fixin' a jar for the neighbors.", "Red ribbon on the whole batch."],
        "stpatricks": ["Wearin' green. Blue's got a clover.", "Luck's on the porch. Green, too."],
        "easter": ["Miss Opal hid eggs in the orchard again.", "Eggs in the orchard. Blue found one."],
        "july4": ["Blue's under the porch. Bottle rockets.", "Mind the rockets. Blue won't."],
        "halloween": ["Pumpkins are in. Mind the ghosts.", "Frost on the pumpkin. Fodder's shocked."],
        "thanksgiving": ["Wild turkey out back. Ham on the table.", "Table's set. Blue's watchin' the bird."],
        "christmas": ["Tree's up. Snow'd be nice.", "Blue's got a bow on. Don't ask."],
    ]

    /// Every body line Jeb can say on its own (no update reason), for the banner's fit check.
    static var allLines: [String] {
        upToDate + updated + failed + rolledBack + error + holidayLines.values.flatMap { $0.good + $0.bad } + greetings.values.flatMap { $0 } + [updatesOff(holiday: nil).body]
    }

    /// One of every kind of banner with made-up facts (JEB_NOTIFY_PREVIEW, JEB_BANNER_CHECK); a greeting for each active holiday.
    static func samples(seed: String, holidays: [String], on date: Date, calendar: Calendar) -> [(kind: String, note: Note)] {
        var out: [(String, Note)] = [
            ("updated", update(.updated("v1.5.1"), seed: seed + "1", holidays: holidays)),
            ("up-to-date", update(.upToDate("v1.5.1"), seed: seed + "2", holidays: holidays)),
            ("failed", update(.failed("the gates rejected the build (parity)"), seed: seed + "3", holidays: holidays)),
            ("rolled-back", update(.rolledBack("the new build stopped drawing"), seed: seed + "4", holidays: holidays)),
            ("error", update(.error("could not reach GitHub"), seed: seed + "5", holidays: holidays)),
            ("updates-off", updatesOff(holiday: holidays.first))]
        for (i, h) in holidays.enumerated() { out.append((i == 0 ? "greeting" : "greeting-" + h, greeting(h, season: Holiday.season(h, on: date, calendar: calendar)))) }
        return out
    }

    static func title(_ holiday: String?) -> String { "Jeb" + (holiday.flatMap { emoji[$0] }.map { " " + $0 } ?? "") }

    /// `holidays` are the active ones, main days first: the update's lines come from the first with lines for this result.
    static func update(_ n: UpdateNews, seed: String, holidays: [String]) -> Note {
        let subtitle: String, plain: [String], good: Bool
        let sprite: String
        var reason: String?
        switch n {
        case .upToDate(let v): subtitle = v.map { "Up to date on " + $0 } ?? "Up to date"; sprite = "jeb-sip"; plain = upToDate; good = true
        case .updated(let v): subtitle = "Updated to " + v; sprite = "jeb-happy"; plain = updated; good = true
        case .failed(let r): subtitle = "Update failed"; reason = r; sprite = "jeb-think"; plain = failed; good = false
        case .rolledBack(let r): subtitle = "Rolled back"; reason = r; sprite = "jeb-think"; plain = rolledBack; good = false
        case .error(let r): subtitle = "Update error"; reason = r; sprite = "jeb-idle"; plain = error; good = false
        }
        let themed = holidays.compactMap { h in holidayLines[h].map { (h, good ? $0.good : $0.bad) } }.first { !$0.1.isEmpty }
        let line = pick(themed?.1 ?? plain, seed)
        return Note(title: title(themed?.0), subtitle: subtitle, body: reason.map { UpdateText.cut($0) + "\n" + line } ?? line, sprite: sprite, tone: good ? .good : .bad, holiday: themed?.0)
    }

    static func updatesOff(holiday: String?) -> Note {
        Note(title: title(holiday), subtitle: "Update notifications are off", body: "Turn 'em back on under Notifications.", sprite: "jeb-idle", holiday: holiday)
    }

    /// Silent: a greeting never makes a sound.
    static func greeting(_ holiday: String, season: Int) -> Note {
        Note(title: title(holiday), subtitle: greetingName[holiday] ?? "Howdy", body: pick(greetings[holiday] ?? ["Howdy, neighbor."], "\(holiday)|\(season)"), sprite: "jeb-wave", sound: false, holiday: holiday)
    }
}

enum Greeting {
    static let hours = 9..<21

    /// The holiday to greet for now, or nil: none under JEB_BENCH (unless JEB_GREET_TEST=1), outside `hours`, no holiday, or already
    /// greeted this season. Only the real date counts (a forced JEB_HOLIDAY never greets) unless JEB_GREET_TEST=1.
    static func due(now: Date, hour: Int, calendar: Calendar, greeted: [String: Int], env: [String: String]) -> (holiday: String, season: Int)? {
        let test = env["JEB_GREET_TEST"] == "1"
        guard hours.contains(hour), test || env["JEB_BENCH"] == nil else { return nil }
        let active = test ? Holiday.current(env: env, now: now, calendar: calendar) : Holiday.active(on: now, calendar: calendar)
        for h in active {
            let season = Holiday.season(h, on: now, calendar: calendar)
            if greeted[h] != season { return (h, season) }
        }
        return nil
    }
}

struct NotifyPrefs: Equatable {
    var updates = true, holidays = true, sound = false     // sound: a banner's Pop, off until asked for
    var greeted: [String: Int] = [:]

    /// A missing or unreadable file gives the defaults; `raw` keeps every key so a newer app's extras survive a write.
    static func decode(_ data: Data?) -> (prefs: NotifyPrefs, raw: [String: Any]) {
        guard let data = data, let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (NotifyPrefs(), [:]) }
        var p = NotifyPrefs()
        p.updates = raw["updates"] as? Bool ?? true
        p.holidays = raw["holidays"] as? Bool ?? true
        p.sound = raw["sound"] as? Bool ?? false
        for (k, v) in raw["greeted"] as? [String: Any] ?? [:] { if let n = (v as? NSNumber)?.intValue { p.greeted[k] = n } }
        return (p, raw)
    }

    func encode(over raw: [String: Any]) -> String {
        var doc = raw
        doc["updates"] = updates
        doc["holidays"] = holidays
        doc["sound"] = sound
        doc["greeted"] = greeted
        let data = (try? JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
