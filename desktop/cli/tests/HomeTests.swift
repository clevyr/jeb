// Home: the paths under a scratch $HOME, the Mach-O reader on this test binary, read_bundle, find_claude, resolve and
// the one-time migration (n/a, would move, moved with the plist rewrite and the link back).
import Foundation

func homeTests(_ t: Tester) {
    let h = t.scratch("home") + "/home"
    setEnvVar("HOME", h); setEnvVar("JEB_HOME", nil); setEnvVar("JEB_TOOLS_DIR", nil); setEnvVar("JEB_LAUNCHAGENTS", h + "/Library/LaunchAgents")
    defer { setEnvVar("JEB_HOME", h + "/Library/Application Support/Jeb") }

    t.test("paths hang off $HOME") {
        t.eq(jebDir(), h + "/.jeb"); t.eq(currentDir(), h + "/.jeb/current"); t.eq(versionsDir(), h + "/.jeb/versions"); t.eq(toolsDir(), h + "/.jeb/bin")
        t.eq(newPath(), h + "/Library/Application Support/Jeb"); t.eq(oldPath(), h + "/.claude/jeb-desktop")
        setEnvVar("JEB_TOOLS_DIR", "/t"); t.eq(toolsDir(), "/t"); setEnvVar("JEB_TOOLS_DIR", nil)
    }
    t.test("machoArchs: this binary, a script, a missing file, a hand-made fat header") {
        let me = CommandLine.arguments[0]
        t.eq(machoArchs(me), [hostArch()], me)
        t.eq(machoArchs(envVar("JEB_REPO")! + "/desktop/jebctl"), [])
        t.eq(machoArchs("/nonexistent"), [])
        let fat = t.scratch("macho") + "/fat"
        var bytes: [UInt8] = [0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 2]
        bytes += [0x01, 0x00, 0x00, 0x07] + [UInt8](repeating: 0, count: 16)
        bytes += [0x01, 0x00, 0x00, 0x0c] + [UInt8](repeating: 0, count: 16)
        FileManager.default.createFile(atPath: fat, contents: Data(bytes))
        t.eq(machoArchs(fat), ["arm64", "x86_64"])
        FileManager.default.createFile(atPath: fat, contents: Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01]))
        t.eq(machoArchs(fat), ["arm64"])
        FileManager.default.createFile(atPath: fat, contents: Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00]))
        t.eq(machoArchs(fat), [])
    }
    t.test("readBundle and findClaude") {
        let v = h + "/.jeb/versions/v1.4.0"
        writeFile(v + "/bundle.json", #"{"schema": 1, "tag": "v1.4.0"}"#)
        symlink(v, h + "/.jeb/current")
        t.eq(readBundle(currentDir())?["tag"]?.string, "v1.4.0")
        writeFile(h + "/x/bundle.json", "[1]")
        t.eq(readBundle(h + "/x"), nil)
        t.eq(readBundle("/nonexistent"), nil)
        setEnvVar("PATH", h + "/pbin")
        t.eq(findClaude(), nil)
        writeFile(h + "/pbin/claude", "#!/bin/sh\n", mode: 0o755)
        t.eq(findClaude(), h + "/pbin/claude")
        writeFile(h + "/.local/bin/claude", "#!/bin/sh\n", mode: 0o755)
        t.eq(findClaude(), h + "/.local/bin/claude")
        setEnvVar("PATH", sysPath)
    }
    t.test("resolveHome: JEB_HOME, then the new folder, then a real old folder, else the new") {
        let new = newPath(), old = oldPath()
        setEnvVar("JEB_HOME", "/j"); t.eq(resolveHome(), "/j"); setEnvVar("JEB_HOME", nil)
        t.eq(resolveHome(), new)
        try FileManager.default.createDirectory(atPath: old, withIntermediateDirectories: true)
        t.eq(resolveHome(), old)
        try FileManager.default.createDirectory(atPath: new, withIntermediateDirectories: true)
        t.eq(resolveHome(), new)
        try FileManager.default.removeItem(atPath: new)
        try FileManager.default.removeItem(atPath: old)
        symlink(new, old)
        t.eq(resolveHome(), new, "a symlinked old folder is not a real one")
        unlink(old)
    }
    t.test("migrate: n/a, would move, moved (plists rewritten, old links to new), busy") {
        let new = newPath(), old = oldPath()
        var said: [String] = []
        setEnvVar("JEB_HOME", "/j"); t.eq(migrate(log: { said.append($0) }), "n/a"); setEnvVar("JEB_HOME", nil)
        t.eq(migrate(log: { said.append($0) }), "n/a", "nothing to move")
        writeFile(old + "/release.log", "x")
        writeFile(old + "/launchd/com.jeb.desktop.app.plist", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>Label</key><string>com.jeb.desktop.app</string><key>StandardOutPath</key><string>\(old)/run.log</string><key>ProgramArguments</key><array><string>\(old)/bin/x</string><string>\(old)-not</string></array></dict></plist>")
        writeFile(agentsDir() + "/com.jeb.desktop.app.plist", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>Label</key><string>com.jeb.desktop.app</string><key>StandardOutPath</key><string>\(old)/run.log</string></dict></plist>")
        writeFile(agentsDir() + "/com.other.plist", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>Label</key><string>com.other</string><key>StandardOutPath</key><string>\(old)/run.log</string></dict></plist>")
        t.eq(migrate(log: { said.append($0) }, dry: true), "would move")
        t.eq(said, ["would move the state folder \(old) to \(new)"])
        t.check(isRealDir(old) && !lexists(new), "a dry run moved")
        said = []
        t.eq(migrate(log: { said.append($0) }), "moved")
        t.eq(said, ["moved the state folder to \(new); \(old) now links there"])
        t.eq(readFile(new + "/release.log"), "x")
        t.eq(try FileManager.default.destinationOfSymbolicLink(atPath: old), new)
        t.eq(resolveHome(), new)
        func strings(_ p: String) -> [String] {
            let doc = (try? PropertyListSerialization.propertyList(from: FileManager.default.contents(atPath: p) ?? Data(), format: nil)) as? [String: Any] ?? [:]
            return [doc["StandardOutPath"] as? String ?? ""] + ((doc["ProgramArguments"] as? [String]) ?? [])
        }
        t.eq(strings(new + "/launchd/com.jeb.desktop.app.plist"), ["\(new)/run.log", "\(new)/bin/x", "\(old)-not"])
        t.eq(strings(agentsDir() + "/com.jeb.desktop.app.plist"), ["\(new)/run.log"])
        t.eq(strings(agentsDir() + "/com.other.plist"), ["\(old)/run.log"], "a foreign plist was rewritten")
        t.eq(migrate(log: { said.append($0) }), "n/a", "after the move")
        // busy: a fresh old folder whose updater.lock is held (flock conflicts between open file descriptions, so one
        // held here is enough; no second process needed)
        try FileManager.default.removeItem(atPath: new); unlink(old)
        writeFile(old + "/updater.lock", "")
        let held = open(old + "/updater.lock", O_WRONLY)
        t.check(held >= 0 && flock(held, LOCK_EX | LOCK_NB) == 0, "could not hold the lock")
        said = []
        t.eq(migrate(log: { said.append($0) }), "busy")
        t.eq(said, ["state folder move postponed: updater.lock is held; the next run retries"])
        t.check(isRealDir(old) && !lexists(new), "a busy move happened")
        close(held)
        t.eq(migrate(log: { said.append($0) }), "moved", "after the lock is released")
    }
}
