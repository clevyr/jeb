// The menu's update lines, from jebHome/update-status.json (written by jebctl) plus what the menu
// itself knows: whether the agent's lock is held, the pause marker, and when the user last clicked. Pure Foundation, no
// AppKit, so a scratch harness can compile it alone. See StatusMenu.swift for the use.

import Foundation

struct UpdateStatus {
    var phase: String
    var detail: String
    var step: Int?
    var steps: Int?
    var started: Double
    var at: Double
    var result: String?     // nil while running; up-to-date, updated, failed, rolled-back or error at the end
    var clicked = false     // the run was started by a menu click (the agent consumed jebHome/check-now)

    static func parse(_ data: Data) -> UpdateStatus? {
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let phase = j["phase"] as? String,
              let started = (j["started"] as? NSNumber)?.doubleValue,
              let at = (j["at"] as? NSNumber)?.doubleValue else { return nil }
        return UpdateStatus(phase: phase, detail: j["detail"] as? String ?? "", step: (j["step"] as? NSNumber)?.intValue, steps: (j["steps"] as? NSNumber)?.intValue,
                            started: started, at: at, result: j["result"] as? String, clicked: j["clicked"] as? Bool ?? false)
    }
}

struct UpdateLines: Equatable {
    var info: String?       // nil: the caller's usual version/build line
    var action: String
    var enabled: Bool
}

enum UpdateText {
    static let staleRunning = 120.0     // a status with no result and no lock this old is a dead run
    static let tooLong = 1800.0
    static let noStart = 60.0

    static func lines(status: UpdateStatus?, lockHeld: Bool, paused: Bool, clickedAt: Double?, now: Double, zone: TimeZone = .current) -> UpdateLines {
        let last = status.flatMap { resultLine($0, zone: zone) }
        if paused { return UpdateLines(info: last, action: "Updates Paused", enabled: false) }
        let running = status.flatMap { $0.result == nil ? $0 : nil }
        if lockHeld || (running.map { now - $0.at < staleRunning } ?? false) {
            guard let s = running else { return UpdateLines(info: last, action: "Update in Progress…", enabled: false) }
            if lockHeld && now - s.started > tooLong { return UpdateLines(info: nil, action: "Update taking longer than expected — see jebctl status", enabled: false) }
            var text = "Update in Progress — " + s.phase
            if let i = s.step, let n = s.steps { text += " (\(i) of \(n))" }
            return UpdateLines(info: nil, action: text + ", " + elapsed(now - s.started), enabled: false)
        }
        if let c = clickedAt, !(status.map { $0.started >= c - 2 } ?? false) {
            if now - c < noStart { return UpdateLines(info: last, action: "Checking for Updates…", enabled: false) }
            return UpdateLines(info: "Couldn't start the update — run jebctl doctor", action: "Check for Updates", enabled: true)
        }
        return UpdateLines(info: last, action: "Check for Updates", enabled: true)
    }

    static func elapsed(_ s: Double) -> String {
        let n = max(0, Int(s))
        return n < 60 ? "\(n) s" : "\(n / 60) min"
    }

    static func cut(_ t: String) -> String { t.count > 60 ? String(t.prefix(59)) + "…" : t }

    private static func updatedVersion(_ s: UpdateStatus) -> String {
        s.detail.lowercased().hasPrefix("updated to ") ? cut(String(s.detail.dropFirst(11))) : cut(s.detail)
    }

    private static func updatedText(_ s: UpdateStatus) -> String { "Updated to " + updatedVersion(s) }

    /// What a finished run tells the user, or nil when it stays silent: a transient error ("... will retry"), an up-to-date
    /// result nobody asked for (only a menu click gets the answer), a repeat of an earlier rejection, or a run still going.
    static func news(_ s: UpdateStatus) -> UpdateNews? {
        guard let r = s.result else { return nil }
        switch r {
        case "up-to-date":
            guard s.clicked else { return nil }
            let m = s.detail.range(of: #"^(\S+) is current$"#, options: .regularExpression)
            return .upToDate(m.map { String(s.detail[$0].dropLast(" is current".count)) })
        case "updated": return .updated(updatedVersion(s))
        case "failed":      // a periodic run that finds the rejected source again only repeats the earlier failure
            guard s.clicked || !s.detail.hasPrefix("no changes since") else { return nil }
            return .failed(s.detail)
        case "rolled-back": return .rolledBack(s.detail)
        case "error": return s.detail.hasSuffix("will retry") ? nil : .error(s.detail)
        default: return nil
        }
    }

    static func resultLine(_ s: UpdateStatus, zone: TimeZone = .current) -> String? {
        guard let r = s.result else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "HH:mm"
        let time = " · " + f.string(from: Date(timeIntervalSince1970: s.at))
        let d = cut(s.detail)
        switch r {
        case "up-to-date": return "Up to date" + time
        case "updated": return updatedText(s) + time
        case "failed": return "Update failed: " + d + time
        case "rolled-back": return "Rolled back: " + d + time
        case "error": return "Update error: " + d + time
        default: return nil
        }
    }
}
