// Tells the user how an update run ended, with a macOS notification. The updater posts the Darwin notification
// com.jeb.desktop.update-finished once, after it has written the final jebHome/update-status.json; this observes it, reads
// the file once and lets UpdateStatus.swift decide whether the result speaks. No polling and no record of what was told:
// one push per finished run, and the new app after a swap is the one running when the updater writes the final "updated".
//
// UNUserNotificationCenter needs an app bundle; a raw binary, JEB_BENCH and JEB_MENU_TEST only log what would be posted.

import Foundation
import UserNotifications

/// Must match FINISHED_NOTIFICATION in updater.py.
private let finishedName = "com.jeb.desktop.update-finished"

final class UpdateNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let statusFile = jebHome + "/update-status.json"
    private var asked = false
    private let live = Bundle.main.bundleIdentifier != nil && env["JEB_BENCH"] == nil && env["JEB_MENU_TEST"] != "1"

    func start() {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer = observer else { return }
            let me = Unmanaged<UpdateNotifier>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { me.finished() }
        }, finishedName as CFString, nil, .deliverImmediately)
    }

    private func finished() {
        guard let status = (try? Data(contentsOf: URL(fileURLWithPath: statusFile))).flatMap(UpdateStatus.parse) else {
            log("notify: finished, but no readable status")
            return
        }
        guard let note = UpdateText.notification(status) else { return }
        post(note.title, note.body)
    }

    private func post(_ title: String, _ body: String) {
        guard live else {
            log("notify: would post \"\(title)\": \(body)")
            return
        }
        let center = UNUserNotificationCenter.current()
        if !asked {
            asked = true
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                log("notify: authorization \(granted ? "granted" : "denied")\(error.map { " (\($0))" } ?? "")")
            }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "jeb-update", content: content, trigger: nil)) { error in
            if let error = error { log("notify: post failed: \(error)") }
        }
    }

    /// An accessory app is never frontmost, so without this the banner would be dropped.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}
