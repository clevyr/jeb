// Holiday windows for the desktop's sprite variants (Art.swift looks up `<base>--<holiday>` first while one is active; a variant keeps its base's width and frame count and may be up to 8 rows taller, drawn from the feet up).
// Pure and Foundation only. Dates are local-time calendar days, inclusive. The mod's TypeScript band never uses this.

import Foundation

enum Holiday {
    /// In the order they are tried; the windows never overlap.
    static let names = ["newyear", "valentines", "stpatricks", "easter", "july4", "halloween", "thanksgiving", "christmas"]

    private struct Day: Comparable {
        let y: Int, m: Int, d: Int
        static func < (a: Day, b: Day) -> Bool { (a.y, a.m, a.d) < (b.y, b.m, b.d) }
    }

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
    static func thanksgiving(year y: Int, calendar: Calendar) -> Int {
        var c = DateComponents(); c.year = y; c.month = 11; c.day = 1
        let weekday = calendar.date(from: c).map { calendar.component(.weekday, from: $0) } ?? 5 // Sunday = 1 ... Thursday = 5
        return 1 + (5 - weekday + 7) % 7 + 21
    }

    /// The holiday whose window holds `date` (local time in `calendar`), or nil.
    static func active(on date: Date, calendar: Calendar) -> String? {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = p.year, let m = p.month, let d = p.day else { return nil }
        let today = Day(y: y, m: m, d: d)
        func fixed(_ m1: Int, _ d1: Int, _ m2: Int, _ d2: Int) -> Bool { today >= Day(y: y, m: m1, d: d1) && today <= Day(y: y, m: m2, d: d2) }
        if fixed(12, 31, 12, 31) || fixed(1, 1, 1, 1) { return "newyear" }
        if fixed(2, 13, 2, 14) { return "valentines" }
        if fixed(3, 16, 3, 17) { return "stpatricks" }
        let e = easter(year: y)
        var sunday = DateComponents(); sunday.year = y; sunday.month = e.month; sunday.day = e.day
        if let s = calendar.date(from: sunday), let sat = calendar.date(byAdding: .day, value: -1, to: s) {
            let q = calendar.dateComponents([.year, .month, .day], from: sat)
            if let qy = q.year, let qm = q.month, let qd = q.day, today >= Day(y: qy, m: qm, d: qd), today <= Day(y: y, m: e.month, d: e.day) { return "easter" }
        }
        if fixed(7, 3, 7, 4) { return "july4" }
        if fixed(10, 24, 10, 31) { return "halloween" }
        let thu = thanksgiving(year: y, calendar: calendar)
        if fixed(11, thu - 3, 11, thu) { return "thanksgiving" }
        if fixed(12, 18, 12, 26) { return "christmas" }
        return nil
    }

    /// JEB_HOLIDAY: `none` is off, a known name is forced (also under JEB_BENCH, to preview). Otherwise none under JEB_BENCH
    /// (parity, day and smoke stay deterministic whatever the date), else the real current date.
    static func current(env: [String: String] = ProcessInfo.processInfo.environment, now: Date = Date(), calendar: Calendar = .current) -> String? {
        if let forced = env["JEB_HOLIDAY"] {
            if forced == "none" { return nil }
            if names.contains(forced) { return forced }
        }
        if env["JEB_BENCH"] != nil { return nil }
        return active(on: now, calendar: calendar)
    }
}
