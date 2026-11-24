// Tells the user how an update run ended, on Jeb's own banner (Banner.swift draws it; no macOS notification, so no permission
// and no System Settings entry). The updater posts the Darwin notification com.jeb.desktop.update-finished once, after it has
// written the final jebHome/update-status.json; this observes it, reads the file once and lets UpdateStatus.swift decide whether
// the result speaks. No polling and no record of what was told: one push per finished run, and the new app after a swap is the one
// running when the updater writes the final "updated".
//
// The same notifier greets on a holiday (once per holiday per year, 9:00-21:00 local, silent; Greeting.due in JebLines.swift)
// and honours jebHome/notifications.json, which the menu's Notifications submenu writes (the app is its only writer).
//
// A raw binary, JEB_BENCH and JEB_MENU_TEST only log what would be shown; JEB_BANNER=1 lets a raw binary show banners.
// JEB_MENU_TEST=1 also listens for the distributed notification com.jeb.desktop.notify-test, object "update" or "greet".
// JEB_GREET_TEST=1 lets a forced JEB_HOLIDAY greet and a bench or test run record it (testing only).

import Foundation

/// Must match the notification name jebctl posts when an update finishes.
private let finishedName = "com.jeb.desktop.update-finished"

/// jebHome/notifications.json: {"updates":true,"holidays":true,"greeted":{"halloween":2026}}. Main thread only; unknown keys are kept.
enum NotifyPrefsFile {
    static let path = jebHome + "/notifications.json"
    static func load() -> NotifyPrefs { NotifyPrefs.decode(try? Data(contentsOf: URL(fileURLWithPath: path))).prefs }
    static func update(_ change: (inout NotifyPrefs) -> Void) {
        var (prefs, raw) = NotifyPrefs.decode(try? Data(contentsOf: URL(fileURLWithPath: path)))
        change(&prefs)
        ensurePrivateDir(jebHome)
        writePrivate(prefs.encode(over: raw) + "\n", to: path)
    }
}

final class UpdateNotifier {
    private let statusFile = jebHome + "/update-status.json"
    private let live: Bool
    private let banner: Banner?
    private var greetedDry = Set<String>()      // greetings only logged (not shown), so each is logged once

    /// Shows banners in an app bundle, or in a raw binary with JEB_BANNER=1; never under JEB_BENCH or JEB_MENU_TEST.
    static var liveDefault: Bool { env["JEB_BENCH"] == nil && env["JEB_MENU_TEST"] != "1" && (Bundle.main.bundleIdentifier != nil || env["JEB_BANNER"] == "1") }

    /// `art` is the current art (main.swift gives `{ desktop.art }`, so a reload or a holiday change is seen); `look` is the
    /// day's look (the farm's night, winter, the main screen's area camp) read each time a banner is drawn.
    init(art: @escaping () -> Art?, look: @escaping () -> BannerLook = { BannerLook.now() }, show: Bool = UpdateNotifier.liveDefault) {
        live = show
        banner = show ? Banner(art: art, look: look) : nil
    }

    func start() {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer = observer else { return }
            let me = Unmanaged<UpdateNotifier>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { me.finished() }
        }, finishedName as CFString, nil, .deliverImmediately)
        unlink(jebHome + "/update-notified")        // an old build's record; nothing reads it
        for name in (try? FileManager.default.contentsOfDirectory(atPath: jebHome)) ?? [] where name.hasPrefix("notify-") && (name.hasSuffix(".png") || name.hasSuffix(".png.tmp")) {
            unlink(jebHome + "/" + name)            // the old notifications' head attachments; nothing makes them now
        }
        startGreeting()
        if env["JEB_MENU_TEST"] == "1" {
            DistributedNotificationCenter.default().addObserver(forName: .init("com.jeb.desktop.notify-test"), object: nil, queue: .main) { [weak self] note in
                switch note.object as? String { case "update": self?.finished(); case "greet": self?.greetTick(); default: break }
            }
        }
    }

    /// The first check a minute after start (past the takeover), then every minute: due is cheap and the file says what was done.
    private func startGreeting() {
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.greetTick() }
        RunLoop.main.add(t, forMode: .common)
    }

    private func greetTick() {
        guard NotifyPrefsFile.load().holidays else { return }
        let now = nowDate()
        let hour = Calendar.current.component(.hour, from: now)
        guard let due = Greeting.due(now: now, hour: hour, calendar: .current, greeted: NotifyPrefsFile.load().greeted, env: env) else { return }
        let id = "jeb-greeting-\(due.holiday)-\(due.season)"
        if live || env["JEB_GREET_TEST"] == "1" { NotifyPrefsFile.update { $0.greeted[due.holiday] = due.season } }      // recorded first: a crash never greets twice
        else if !greetedDry.insert(id).inserted { return }
        post(id: id, JebLines.greeting(due.holiday, season: due.season))
    }

    private func finished() {
        guard let status = (try? Data(contentsOf: URL(fileURLWithPath: statusFile))).flatMap(UpdateStatus.parse) else {
            log("notify: finished, but no readable status")
            return
        }
        guard let news = UpdateText.news(status) else { return }
        let holidays = Holiday.current()
        if !NotifyPrefsFile.load().updates {
            guard status.clicked else { log("notify: updates off, quiet"); return }
            post(id: "jeb-update", JebLines.updatesOff(holiday: holidays.first))
            return
        }
        post(id: "jeb-update", JebLines.update(news, seed: "\(status.result ?? "")|\(status.detail)|\(Int(status.started))", holidays: holidays))
    }

    /// JEB_NOTIFY_PREVIEW (main.swift) and the menu's Show Sample Banners: every kind of banner once, queued at once, with
    /// made-up facts; done() when the last is gone (at once when banners are only logged). The greeting is the current holiday's
    /// (JEB_HOLIDAY forces one); none outside a holiday.
    func preview(done: @escaping () -> Void) {
        let hs = Holiday.current(), seed = String(Int(Date().timeIntervalSince1970))
        // A fresh id per run, so a sample never replaces one still waiting from an earlier run.
        for (kind, note) in JebLines.samples(seed: seed, holidays: hs, on: nowDate(), calendar: .current) {
            post(id: (kind.hasPrefix("greeting") ? "jeb-greeting-preview-" : "jeb-preview-") + kind + "-" + seed, note)
        }
        guard let banner = banner else { done(); return }
        banner.onIdle = { [weak banner] in banner?.onIdle = nil; done() }
    }

    private func post(id: String, _ note: Note) {
        guard let banner = banner else {
            log("notify: would show [\(id)] \"\(note.title)\" / \(note.subtitle): \(note.body.replacingOccurrences(of: "\n", with: " / ")) (\(note.sprite))")
            return
        }
        banner.show(note, id: id)
    }
}
