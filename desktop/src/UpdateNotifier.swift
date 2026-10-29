// Tells the user how an update run ended, with a macOS notification. The updater posts the Darwin notification
// com.jeb.desktop.update-finished once, after it has written the final jebHome/update-status.json; this observes it, reads
// the file once and lets UpdateStatus.swift decide whether the result speaks. No polling and no record of what was told:
// one push per finished run, and the new app after a swap is the one running when the updater writes the final "updated".
//
// UNUserNotificationCenter needs an app bundle; a raw binary, JEB_BENCH and JEB_MENU_TEST only log what would be posted.
// The banner carries Jeb's head (the menu bar's, scaled up) as an attachment; if it cannot be made the banner goes without.

import Foundation
import UserNotifications
import ImageIO
import UniformTypeIdentifiers

/// Must match FINISHED_NOTIFICATION in updater.py.
private let finishedName = "com.jeb.desktop.update-finished"

final class UpdateNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let statusFile = jebHome + "/update-status.json"
    private var asked = false
    private var loggedHeadFailure = false
    /// The current art (main.swift gives `{ desktop.art }`, so a reload or a holiday change is seen).
    var art: (() -> Art)?
    private let headFile = jebHome + "/notify-head.png"
    private let headScale = 8
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
            log("notify: would post \"\(title)\": \(body) (with Jeb's head attached)")
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
        if let head = headAttachment() { content.attachments = [head] }
        center.add(UNNotificationRequest(identifier: "jeb-update", content: content, trigger: nil)) { error in
            if let error = error { log("notify: post failed: \(error)") }
        }
    }

    /// The menu bar's head (StatusMenu.setIcon: the top 20 rows of jeb-idle) at a whole-number scale, centred on a transparent
    /// square, written 0600 and atomically to jebHome; nil (logged once) if any step fails.
    private func headAttachment() -> UNNotificationAttachment? {
        func fail(_ why: String) -> UNNotificationAttachment? {
            if !loggedHeadFailure { loggedHeadFailure = true; log("notify: posting without the head: \(why)") }
            return nil
        }
        guard let art = art?() else { return fail("no art") }
        guard let head = art.image("jeb-idle", rows: art.headRows("jeb-idle", 20), scale: headScale) else { return fail("art has no jeb-idle head") }
        let side = max(head.width, head.height)
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return fail("no canvas") }
        ctx.interpolationQuality = .none
        ctx.draw(head, in: CGRect(x: (side - head.width) / 2, y: (side - head.height) / 2, width: head.width, height: head.height))
        let png = NSMutableData()
        guard let image = ctx.makeImage(), let dest = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return fail("no encoder") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return fail("encode failed") }
        let tmp = headFile + ".tmp"
        try? FileManager.default.createDirectory(atPath: jebHome, withIntermediateDirectories: true)
        unlink(tmp)
        guard FileManager.default.createFile(atPath: tmp, contents: png as Data, attributes: [.posixPermissions: 0o600]),
              rename(tmp, headFile) == 0 else { unlink(tmp); return fail("cannot write \(headFile)") }
        do { return try UNNotificationAttachment(identifier: "jeb-head", url: URL(fileURLWithPath: headFile), options: nil) }
        catch { return fail("attach failed: \(error)") }
    }

    /// An accessory app is never frontmost, so without this the banner would be dropped.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}
