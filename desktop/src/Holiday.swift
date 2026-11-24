// Holiday windows for the desktop's banner, greetings and sprite variants (Art.swift looks up `<base>--<holiday>` first while a
// holiday with costume art is active; a variant keeps its base's width and frame count and may be up to 8 rows taller, drawn
// from the feet up). More than one holiday can be active at once, so a day answers a list, its main days first. Pure and
// Foundation only (tools/detect is compiled from this file alone).
// Dates are local-time calendar days, inclusive. The mod's TypeScript band never uses this.

import Foundation

enum Holiday {
    /// Every holiday, in the order they sort when active together (after the ones on their main day).
    static let names = ["christmas", "newyear", "easter", "valentines", "stpatricks", "july4", "halloween", "thanksgiving"]

    struct Day: Comparable, Hashable {
        let y: Int, m: Int, d: Int
        static func < (a: Day, b: Day) -> Bool { (a.y, a.m, a.d) < (b.y, b.m, b.d) }
    }

    /// One holiday's window (inclusive) and its main days, for the window that starts in `start.y`.
    struct Window { let name: String, start: Day, end: Day, coreFrom: Day, coreTo: Day }

    // MARK: civil days through noon UTC

    private static let utcZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
    private static let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = utcZone; return c }()

    private static func noon(_ d: Day) -> Date {
        utc.date(from: DateComponents(year: d.y, month: d.m, day: d.d, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }
    private static func day(_ date: Date) -> Day {
        let p = utc.dateComponents([.year, .month, .day], from: date)
        return Day(y: p.year ?? 0, m: p.month ?? 1, d: p.day ?? 1)
    }
    private static func add(_ d: Day, _ n: Int) -> Day { day(utc.date(byAdding: .day, value: n, to: noon(d)) ?? noon(d)) }

    /// Western Easter Sunday (anonymous Gregorian algorithm).
    static func easter(year y: Int) -> (month: Int, day: Int) {
        let a = y % 19, b = y / 100, c = y % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31, day = (h + l - 7 * m + 114) % 31 + 1
        return (month, day)
    }

    /// The 4th Thursday of November.
    static func thanksgiving(year y: Int) -> Int {
        let weekday = utc.component(.weekday, from: noon(Day(y: y, m: 11, d: 1)))     // Sunday = 1 ... Thursday = 5
        return 1 + (5 - weekday + 7) % 7 + 21
    }

    /// Every window that starts in year `y`.
    static func windows(startYear y: Int) -> [Window] {
        var out: [Window] = []
        func put(_ name: String, _ s: Day, _ e: Day, core: ClosedRange<Day>? = nil) {
            let c = core ?? s...e
            out.append(Window(name: name, start: s, end: e, coreFrom: c.lowerBound, coreTo: c.upperBound))
        }
        func fixed(_ name: String, _ m1: Int, _ d1: Int, _ m2: Int, _ d2: Int, core: ClosedRange<Day>? = nil) {
            put(name, Day(y: y, m: m1, d: d1), Day(y: y, m: m2, d: d2), core: core)
        }
        func on(_ m: Int, _ d: Int) -> ClosedRange<Day> { Day(y: y, m: m, d: d)...Day(y: y, m: m, d: d) }
        put("newyear", Day(y: y, m: 12, d: 31), Day(y: y + 1, m: 1, d: 1), core: Day(y: y + 1, m: 1, d: 1)...Day(y: y + 1, m: 1, d: 1))
        fixed("valentines", 2, 13, 2, 14, core: on(2, 14))
        fixed("stpatricks", 3, 16, 3, 17, core: on(3, 17))
        let e = easter(year: y), sunday = Day(y: y, m: e.month, d: e.day)
        put("easter", add(sunday, -1), sunday, core: sunday...sunday)
        fixed("july4", 7, 3, 7, 4, core: on(7, 4))
        fixed("halloween", 10, 24, 10, 31, core: on(10, 31))
        let thu = thanksgiving(year: y)
        fixed("thanksgiving", 11, thu - 3, 11, thu, core: on(11, thu))
        fixed("christmas", 12, 18, 12, 26, core: on(12, 25))
        return out
    }

    private static func localDay(_ date: Date, _ calendar: Calendar) -> Day? {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = p.year, let m = p.month, let d = p.day else { return nil }
        return Day(y: y, m: m, d: d)
    }

    /// The windows holding `today` (a window may have started last year).
    private static func holding(_ today: Day) -> [Window] {
        (windows(startYear: today.y) + windows(startYear: today.y - 1)).filter { $0.start <= today && today <= $0.end }
    }

    /// The holidays whose windows hold `date` (local time in `calendar`): those on their main day first, then by `names`.
    static func active(on date: Date, calendar: Calendar) -> [String] {
        guard let today = localDay(date, calendar) else { return [] }
        func rank(_ w: Window) -> (Int, Int) { (w.coreFrom <= today && today <= w.coreTo ? 0 : 1, names.firstIndex(of: w.name) ?? names.count) }
        return holding(today).sorted { rank($0) < rank($1) }.map { $0.name }
    }

    /// The year a holiday's window started in (New Year's spans two years, so January counts for the year before).
    static func season(_ name: String, on date: Date, calendar: Calendar) -> Int {
        guard let today = localDay(date, calendar) else { return 0 }
        return holding(today).first { $0.name == name }?.start.y ?? today.y
    }

    /// JEB_HOLIDAY: `none` is off, a comma list of known names is forced (also under JEB_BENCH, to preview). Otherwise none under
    /// JEB_BENCH (parity, day and smoke stay deterministic whatever the date), else the real current date.
    static func current(env: [String: String] = ProcessInfo.processInfo.environment, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        if let forced = env["JEB_HOLIDAY"] {
            if forced == "none" { return [] }
            let list = forced.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { names.contains($0) }
            if !list.isEmpty { return list }
        }
        if env["JEB_BENCH"] != nil { return [] }
        return active(on: now, calendar: calendar)
    }

    // MARK: the check (run by bannerCheck)

    /// Pinned dates, clashes, time-zone independence and a sweep of every day 2026-2040. Returns how many checks
    /// ran, the failures, and the most holidays active at once.
    static func check() -> (checks: Int, failures: [String], maxActive: Int) {
        var checks = 0, failures: [String] = []
        func expect(_ ok: Bool, _ what: @autoclosure () -> String) { checks += 1; if !ok { failures.append(what()) } }
        let utcCal = utc
        func at(_ y: Int, _ m: Int, _ d: Int, _ cal: Calendar) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        }
        func zone(_ id: String) -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: id) ?? utcZone; return c }
        let pins: [(String, Int, Int, Int)] = [("valentines", 2026, 2, 14), ("stpatricks", 2026, 3, 17), ("easter", 2026, 4, 5), ("july4", 2026, 7, 4),
                                              ("halloween", 2026, 10, 31), ("thanksgiving", 2026, 11, 26), ("christmas", 2026, 12, 25), ("newyear", 2027, 1, 1)]
        for (name, y, m, d) in pins { expect(active(on: at(y, m, d, utcCal), calendar: utcCal).contains(name), "\(name) should be active on \(y)-\(m)-\(d)") }
        expect(active(on: at(2026, 12, 25, utcCal), calendar: utcCal).first == "christmas", "Christmas leads on its main day")
        expect(!active(on: at(2026, 6, 1, utcCal), calendar: utcCal).contains("christmas"), "no Christmas in June")
        expect(season("newyear", on: at(2028, 1, 1, utcCal), calendar: utcCal) == 2027, "a January day belongs to the season that started in December")
        for id in ["America/Los_Angeles", "America/New_York", "Asia/Kolkata", "Pacific/Auckland"] {
            let cal = zone(id)
            var differ = 0
            for (m, d) in [(2, 14), (3, 17), (4, 5), (7, 4), (10, 31), (11, 26), (12, 25), (12, 31)] where active(on: at(2026, m, d, cal), calendar: cal) != active(on: at(2026, m, d, utcCal), calendar: utcCal) { differ += 1 }
            expect(differ == 0, "the holidays differ in \(id) on \(differ) day(s)")
        }
        // every day 2026-2040
        let costume: Set<String> = ["halloween", "thanksgiving", "christmas"]
        var seen: [String: [Int: Int]] = [:], maxActive = 0
        var d = Day(y: 2026, m: 1, d: 1)
        while d.y <= 2040 {
            let list = active(on: noon(d), calendar: utcCal)
            maxActive = max(maxActive, list.count)
            if !Set(list).isSubset(of: Set(names)) || Set(list).count != list.count { failures.append("bad names on \(d): \(list)") }
            if list.filter({ costume.contains($0) }).count > 1 { failures.append("costume holidays overlap on \(d): \(list)") }
            for n in list { seen[n, default: [:]][d.y, default: 0] += 1 }
            d = add(d, 1)
        }
        checks += 2
        for n in names {
            for y in 2026...2040 { expect((seen[n]?[y] ?? 0) >= 1, "\(n) never active in \(y)") }
        }
        return (checks, failures, maxActive)
    }
}
