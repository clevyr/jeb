// InstallTests: the jebctl link and the PATH line of the shell profile (Install.swift). HOME and every path are scratch
// ones (JEB_BIN_DIR, JEB_PROFILE, JEB_BACKUPS); the real ~/.local/bin and shell profile are never read or written.
import Foundation

func installTests(_ t: Tester) {
    /// A scratch HOME with ~/.jeb/current/desktop/bin/jebctl in it; body gets (home, the link folder, the profile).
    func sandbox(_ name: String, _ body: (String, String, String) throws -> Void) rethrows {
        let home = t.scratch(name), fm = FileManager.default
        let bin = home + "/.local/bin", profile = home + "/.zprofile"
        try? fm.createDirectory(atPath: home + "/.jeb/versions/v1/desktop/bin", withIntermediateDirectories: true)
        writeFile(home + "/.jeb/versions/v1/desktop/bin/jebctl", "#!/bin/sh\n", mode: 0o755)
        try? fm.createSymbolicLink(atPath: home + "/.jeb/current", withDestinationPath: "versions/v1")
        let names = ["HOME", "JEB_BIN_DIR", "JEB_PROFILE", "JEB_BACKUPS", "PATH"]
        let was = names.map { envVar($0) }, loud = verbose, dry = dryRun
        for (k, v) in zip(names, [home, bin, profile, home + "/backups", "/usr/bin:/bin"]) { setEnvVar(k, v) }
        verbose = false
        dryRun = false
        defer {
            for (k, v) in zip(names, was) { setEnvVar(k, v) }
            verbose = loud
            dryRun = dry
        }
        try body(home, bin, profile)
    }
    func backupsIn(_ home: String) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: home + "/backups")) ?? []).sorted() }

    t.test("install: the jebctl link is made, recognised, and removed again") {
        sandbox("link") { home, bin, _ in
            let fm = FileManager.default, link = bin + "/jebctl"
            t.eq(linkState(), "none")
            dryRun = true
            t.check(linkJebctl(), "a dry run would link")
            t.check(!lexists(link), "and links nothing")
            dryRun = false
            t.check(linkJebctl(), "linked")
            t.eq(try? fm.destinationOfSymbolicLink(atPath: link), home + "/.jeb/current/desktop/bin/jebctl", "to the stable path")
            t.eq(linkState(), "ours")
            t.check(linkJebctl(), "a second run keeps it")
            unlinkJebctl()
            t.check(!lexists(link), "uninstall removes our link")
        }
    }

    t.test("install: another Jeb's link is replaced, anything else is left alone") {
        sandbox("link-older") { home, bin, _ in
            let fm = FileManager.default, link = bin + "/jebctl", other = home + "/clone/desktop/jebctl"
            try? fm.createDirectory(atPath: home + "/clone/desktop", withIntermediateDirectories: true)
            try? fm.createDirectory(atPath: bin, withIntermediateDirectories: true)
            writeFile(other, "#!/bin/sh\n", mode: 0o755)
            try? fm.createSymbolicLink(atPath: link, withDestinationPath: other)
            t.eq(linkState(), "older")
            t.check(linkJebctl(), "replaced")
            t.eq(linkState(), "ours")
            unlink(link)
            writeFile(link, "#!/bin/sh\necho mine\n", mode: 0o755)
            t.eq(linkState(), "foreign", "a real file")
            t.check(!linkJebctl(), "not set up")
            unlinkJebctl()
            t.eq(readFile(link), "#!/bin/sh\necho mine\n", "and uninstall leaves it")
            unlink(link)
            try? fm.createSymbolicLink(atPath: link, withDestinationPath: "/bin/ls")
            t.eq(linkState(), "foreign", "a link to something else")
        }
    }

    t.test("install: the PATH lines are added once with a backup, and removed with one") {
        sandbox("profile") { home, _, profile in
            writeFile(profile, "export FOO=1")
            let stamp = Clock.strftime("%Y%m%d-%H%M%S")
            t.eq(exportLine(), "export PATH=\"$HOME/.local/bin:$PATH\"")
            t.check(!onPath(binDir()), "not on PATH yet")
            dryRun = true
            pathStep(add: true)
            t.eq(readFile(profile), "export FOO=1", "a dry run writes nothing")
            dryRun = false
            pathStep(add: true)
            let added = "export FOO=1\n\(pathMark)\nexport PATH=\"$HOME/.local/bin:$PATH\"\n"
            t.eq(readFile(profile), added)
            t.eq(backupsIn(home), [".zprofile.\(stamp).bak"], "backed up first")
            t.eq(readFile(home + "/backups/.zprofile.\(stamp).bak"), "export FOO=1", "with the old content")
            pathStep(add: true)
            t.eq(readFile(profile), added, "a second run adds nothing")
            writeFile(profile, added + "export BAR=2\n")
            removeFromProfile()
            t.eq(readFile(profile), "export FOO=1\nexport BAR=2\n", "only Jeb's two lines go")
            t.eq(backupsIn(home).count, 2, "backed up again")
            removeFromProfile()
            t.eq(backupsIn(home).count, 2, "nothing to remove: no backup, no write")
        }
    }

    t.test("install: no profile yet, and a folder already on PATH") {
        sandbox("profile-new") { home, bin, profile in
            pathStep(add: true)
            t.eq(readFile(profile), "\(pathMark)\nexport PATH=\"$HOME/.local/bin:$PATH\"\n", "created")
            t.eq(backupsIn(home), [], "nothing to back up")
            unlink(profile)
            try? FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
            setEnvVar("PATH", "/usr/bin:" + bin)
            pathStep(add: true)
            t.check(!lexists(profile), "on PATH already: the profile is not touched")
        }
    }

    t.test("install: unknown options are refused before anything runs") {
        sandbox("flags") { _, bin, _ in
            t.eq(cmdInstall(["--dev"]), 2)
            t.eq(cmdInstall(["--mode", "release"]), 2)
            t.eq(cmdUninstall(["--bogus"]), 2)
            t.check(!lexists(bin), "nothing was made")
        }
    }
}
