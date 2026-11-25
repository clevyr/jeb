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

    t.test("install --no-agents: the link and PATH targets must sit inside the sandbox HOME") {
        sandbox("sandboxlinks") { home, _, _ in
            t.check(checkSandboxLinks() == nil, "bin and profile under HOME pass")
            let was = envVar("JEB_BIN_DIR")
            setEnvVar("JEB_BIN_DIR", "/usr/local/bin")
            t.check(checkSandboxLinks()?.contains("JEB_BIN_DIR") == true, "a link folder outside HOME is refused")
            setEnvVar("JEB_BIN_DIR", was)
            let prof = envVar("JEB_PROFILE")
            setEnvVar("JEB_PROFILE", "/etc/profile")
            t.check(checkSandboxLinks()?.contains("JEB_PROFILE") == true, "a profile outside HOME is refused")
            setEnvVar("JEB_PROFILE", prof)
        }
    }

    t.test("install --no-agents: with JEB_PROFILE set the shells' own folders are never written, so they are not checked") {
        sandbox("sandboxlinks-profile") { home, _, _ in
            let names = ["XDG_CONFIG_HOME", "ZDOTDIR"]
            let was = names.map { envVar($0) }
            defer { for (k, v) in zip(names, was) { setEnvVar(k, v) } }
            setEnvVar("XDG_CONFIG_HOME", "/etc/xdg")
            setEnvVar("ZDOTDIR", "/etc/zd")
            t.eq(checkSandboxLinks(), nil, "JEB_PROFILE inside HOME: ZDOTDIR and XDG outside are allowed")
            setEnvVar("JEB_BIN_DIR", "/usr/local/bin")
            t.check(checkSandboxLinks()?.contains("JEB_BIN_DIR") == true, "the link folder is still checked")
            setEnvVar("JEB_BIN_DIR", home + "/.local/bin")
            setEnvVar("JEB_PROFILE", "/etc/profile")
            t.check(checkSandboxLinks()?.contains("JEB_PROFILE") == true, "and so is the profile's folder")
            setEnvVar("JEB_PROFILE", nil)
            t.check(checkSandboxLinks()?.contains("ZDOTDIR") == true, "without JEB_PROFILE ZDOTDIR is checked again")
        }
    }

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

    /// sandbox without JEB_PROFILE, with SHELL set and XDG_CONFIG_HOME / ZDOTDIR cleared (body sets them when it needs them).
    func shellBox(_ name: String, shell: String, _ body: (String) throws -> Void) rethrows {
        try sandbox(name) { home, _, _ in
            let names = ["JEB_PROFILE", "SHELL", "XDG_CONFIG_HOME", "ZDOTDIR"]
            let was = names.map { envVar($0) }
            defer { for (k, v) in zip(names, was) { setEnvVar(k, v) } }
            for k in names { setEnvVar(k, nil) }
            setEnvVar("SHELL", "/bin/" + shell)
            try body(home)
        }
    }
    let mark = pathMark + "\n"
    let sh = mark + "export PATH=\"$HOME/.local/bin:$PATH\"\n"
    let nuBlock = mark + "$env.PATH = ($env.PATH | split row (char esep) | prepend (\"~/.local/bin\" | path expand) | uniq)\n"
    let fishFile = mark + "fish_add_path -g ~/.local/bin\n"

    t.test("add-path: zsh alone gets only .zprofile") {
        shellBox("ap-zsh", shell: "zsh") { home in
            pathStep(add: true)
            t.eq(readFile(home + "/.zprofile"), sh)
            for f in ["/.bash_profile", "/.profile", "/.config/fish/conf.d/jeb.fish"] { t.check(!lexists(home + f), "\(f) not made") }
        }
    }

    t.test("add-path: a shell that has config is set up too, fish with its own file") {
        shellBox("ap-fish", shell: "zsh") { home in
            try? FileManager.default.createDirectory(atPath: home + "/.config/fish", withIntermediateDirectories: true)
            t.eq(pathTargets(nil).map { $0.shell }, ["zsh", "fish"])
            pathStep(add: true)
            t.eq(readFile(home + "/.zprofile"), sh)
            t.eq(readFile(home + "/.config/fish/conf.d/jeb.fish"), fishFile)
        }
    }

    t.test("add-path: nushell goes under Library or XDG_CONFIG_HOME") {
        shellBox("ap-nu", shell: "nu") { home in
            pathStep(add: true)
            t.eq(readFile(home + "/Library/Application Support/nushell/env.nu"), nuBlock)
            t.check(!lexists(home + "/.profile"), "nu is not a sh shell")
            try? FileManager.default.removeItem(atPath: home + "/Library")
            setEnvVar("XDG_CONFIG_HOME", home + "/xdg")
            pathStep(add: true)
            t.eq(readFile(home + "/xdg/nushell/env.nu"), nuBlock)
            t.check(!lexists(home + "/Library"), "and nothing under Library")
        }
    }

    t.test("add-path: an explicit list writes only those shells") {
        shellBox("ap-list", shell: "zsh") { home in
            pathStep(add: true, only: ["fish"])
            t.eq(readFile(home + "/.config/fish/conf.d/jeb.fish"), fishFile)
            t.check(!lexists(home + "/.zprofile"), "zsh untouched")
            t.eq(parseShellList("zsh,nu"), ["zsh", "nu"])
            t.eq(parseShellList("zsh,tcsh"), nil)
        }
    }

    t.test("add-path: an explicit list is written even when this shell already has the folder on PATH") {
        shellBox("ap-list-onpath", shell: "zsh") { home in
            setEnvVar("PATH", "/usr/bin:" + binDir())
            pathStep(add: true)
            t.check(!lexists(home + "/.config/fish/conf.d/jeb.fish"), "no list: on PATH, nothing written")
            pathStep(add: true, only: ["fish"])
            t.eq(readFile(home + "/.config/fish/conf.d/jeb.fish"), fishFile)
        }
    }

    t.test("add-path: a second run changes nothing, then uninstall removes every block and keeps other lines") {
        shellBox("ap-twice", shell: "zsh") { home in
            let fm = FileManager.default
            try? fm.createDirectory(atPath: home + "/.config/fish", withIntermediateDirectories: true)
            try? fm.createDirectory(atPath: home + "/Library/Application Support/nushell", withIntermediateDirectories: true)
            let nu = home + "/Library/Application Support/nushell/env.nu"
            writeFile(home + "/.zprofile", "export A=1\n")
            writeFile(nu, "let x = 1\n")
            writeFile(home + "/.bash_profile", "export B=2\n")
            pathStep(add: true)
            let z = readFile(home + "/.zprofile"), n = readFile(nu), made = backupsIn(home)
            t.eq(z, "export A=1\n" + sh)
            t.eq(n, "let x = 1\n" + nuBlock)
            t.eq(readFile(home + "/.bash_profile"), "export B=2\n" + sh, "bash has config, so it is set up too")
            t.eq(made.count, 3)
            pathStep(add: true)
            t.eq(readFile(home + "/.zprofile"), z)
            t.eq(readFile(nu), n)
            t.eq(backupsIn(home), made, "no second backup")
            unlinkJebctl()
            t.eq(readFile(home + "/.zprofile"), "export A=1\n")
            t.eq(readFile(nu), "let x = 1\n")
            t.eq(readFile(home + "/.bash_profile"), "export B=2\n")
            t.check(!lexists(home + "/.config/fish/conf.d/jeb.fish"), "our jeb.fish is gone")
        }
    }

    t.test("add-path: a jeb.fish that is not ours is left alone by add and remove") {
        shellBox("ap-foreign", shell: "fish") { home in
            let f = home + "/.config/fish/conf.d/jeb.fish"
            writeFile(f, "# mine\nset -x JEB 1\n")
            pathStep(add: true)
            t.eq(readFile(f), "# mine\nset -x JEB 1\n")
            removeFromProfile()
            t.eq(readFile(f), "# mine\nset -x JEB 1\n")
            t.eq(backupsIn(home), [])
        }
    }

    t.test("add-path: a dry run writes nothing") {
        shellBox("ap-dry", shell: "zsh") { home in
            dryRun = true
            pathStep(add: true, only: ["zsh", "fish", "nu"])
            t.check(!lexists(home + "/.zprofile") && !lexists(home + "/.config"), "nothing written")
        }
    }

    t.test("add-path: in pretty mode the check is left for the end of the install, with no new-terminal line") {
        shellBox("ap-pretty", shell: "zsh") { home in
            Style.pretty = true
            defer { Style.pretty = false; pathConfirmPending = nil }
            pathStep(add: true, only: ["zsh", "bash"])
            t.eq(pathConfirmPending?.map(\.shell), ["zsh", "bash"])
            t.check(pathConfirmPending?.allSatisfy(\.has) == true, "both written")
        }
    }

    t.test("add-path: a login zsh finds jebctl once the line is written, and not before") {
        shellBox("ap-check", shell: "zsh") { home in
            let bin = home + "/.local/bin"
            try? FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: bin + "/jebctl", contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
            let target = { pathTargets(["zsh"])[0] }
            t.eq(checkShell(target()), .missing)
            pathStep(add: true, only: ["zsh"])
            t.eq(checkShell(target()), .found)
            t.eq(checkShell(PathTarget(shell: "nosuchshell", file: "", has: true)), .unchecked)
        }
    }

    t.test("add-path: nushell's folder follows nushell's rule for XDG_CONFIG_HOME") {
        shellBox("ap-nudir", shell: "nu") { home in
            t.eq(nuDir(), home + "/Library/Application Support/nushell")
            setEnvVar("XDG_CONFIG_HOME", home + "/xdg")
            t.eq(nuDir(), home + "/xdg/nushell")
            setEnvVar("XDG_CONFIG_HOME", "relative/xdg")
            t.eq(nuDir(), home + "/Library/Application Support/nushell", "a relative XDG_CONFIG_HOME is ignored, as nushell does")
        }
    }

    t.test("add-path: ZDOTDIR is respected") {
        shellBox("ap-zdot", shell: "zsh") { home in
            setEnvVar("ZDOTDIR", home + "/zd")
            pathStep(add: true)
            t.eq(readFile(home + "/zd/.zprofile"), sh)
            t.check(!lexists(home + "/.zprofile"), "not in HOME")
            removeFromProfile()
            t.eq(readFile(home + "/zd/.zprofile"), "")
        }
    }

    t.test("add-path: JEB_PROFILE keeps the one-file behaviour") {
        sandbox("ap-profile") { home, _, profile in
            try? FileManager.default.createDirectory(atPath: home + "/.config/fish", withIntermediateDirectories: true)
            setEnvVar("SHELL", "/bin/fish")
            t.eq(pathTargets(nil), [PathTarget(shell: "profile", file: profile, has: false)])
            pathStep(add: true, only: ["fish", "nu"])
            t.eq(readFile(profile), sh)
            t.check(!lexists(home + "/.config/fish/conf.d"), "no other file")
        }
    }

    t.test("add-path: flags are parsed, a bad shell and a clash are usage errors") {
        var f = PathFlags()
        t.check(f.take("--add-path=zsh,nu") && f.error == nil, "taken")
        t.eq(f.shells, ["zsh", "nu"])
        t.eq(f.forward, ["--add-path=zsh,nu"])
        var g = PathFlags()
        t.check(g.take("--add-path") && g.shells == nil && g.forward == ["--add-path"], "plain")
        var h = PathFlags()
        t.check(h.take("--no-add-path") && h.no && h.forward == ["--no-add-path"], "no")
        t.check(h.take("--add-path") && h.error != nil, "the clash")
        var b = PathFlags()
        t.check(b.take("--add-path=tcsh") && b.error != nil, "an unknown shell")
        t.check(!b.take("--repin"), "other flags are not ours")
        sandbox("ap-flags") { _, bin, _ in
            t.eq(cmdInstall(["--add-path", "--no-add-path"]), 2)
            t.eq(cmdInstall(["--add-path=csh"]), 2)
            t.eq(cmdAddPath(["csh"]), 2)
            t.check(!lexists(bin), "nothing was made")
        }
    }

    /// Runs body with stdout pointed at a file; returns what was printed.
    func printed(_ body: () -> Void) -> String {
        let file = t.scratch("stdout") + ".txt"
        fflush(stdout)
        let saved = dup(1), fd = open(file, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        dup2(fd, 1)
        close(fd)
        body()
        fflush(stdout)
        dup2(saved, 1)
        close(saved)
        return readFile(file) ?? ""
    }

    t.test("bash: the PATH line goes in the first login file that exists, and a new .bash_profile never hides another") {
        shellBox("bash-profile", shell: "bash") { home in
            writeFile(home + "/.bashrc", "x\n")
            writeFile(home + "/.profile", "export P=1\n")
            t.eq(pathFile("bash"), home + "/.profile")
            pathStep(add: true)
            t.eq(readFile(home + "/.profile"), "export P=1\n" + sh, "into .profile")
            t.check(!lexists(home + "/.bash_profile"), "no .bash_profile made")
        }
        shellBox("bash-none", shell: "bash") { home in
            t.eq(pathFile("bash"), home + "/.bash_profile", "nothing: .bash_profile")
            pathStep(add: true)
            t.eq(readFile(home + "/.bash_profile"), sh)
            t.check(!lexists(home + "/.profile"), "and only that")
        }
        shellBox("bash-login", shell: "bash") { home in
            writeFile(home + "/.bash_login", "export L=1\n")
            writeFile(home + "/.profile", "export P=1\n")
            pathStep(add: true)
            t.eq(readFile(home + "/.bash_login"), "export L=1\n" + sh, ".bash_login comes before .profile")
            t.eq(readFile(home + "/.profile"), "export P=1\n")
            t.check(!lexists(home + "/.bash_profile"), "no .bash_profile made")
        }
        shellBox("bash-configured", shell: "zsh") { home in
            t.check(!shellConfigured("bash"), "no bash files")
            writeFile(home + "/.bash_login", "")
            t.check(shellConfigured("bash"), "a .bash_login is the signal")
        }
    }

    t.test("bash: uninstall finds an older install's line in any of the three login files") {
        shellBox("bash-uninstall", shell: "zsh") { home in
            writeFile(home + "/.bash_profile", "export B=1\n" + sh)
            writeFile(home + "/.profile", "export P=1\n")
            writeFile(home + "/.bash_login", sh + "export L=1\n")
            removeFromProfile()
            t.eq(readFile(home + "/.bash_profile"), "export B=1\n", ".bash_profile cleaned though .profile exists")
            t.eq(readFile(home + "/.bash_login"), "export L=1\n", ".bash_login cleaned though .bash_profile comes first")
            t.eq(readFile(home + "/.profile"), "export P=1\n", ".profile untouched")
        }
        shellBox("bash-uninstall-profile", shell: "bash") { home in
            writeFile(home + "/.profile", sh)
            removeFromProfile()
            t.eq(readFile(home + "/.profile"), "", ".profile is listed once, not twice")
            t.eq(backupsIn(home).count, 1, "one backup")
        }
    }

    t.test("install: a profile that cannot be written is a warning, the other shells are still set up") {
        shellBox("ro-profile", shell: "zsh") { home in
            writeFile(home + "/.zprofile", "export Z=1\n")
            writeFile(home + "/.bashrc", "x\n")
            chmod(home + "/.zprofile", 0o444)
            var ok = true
            let out = printed { ok = pathStep(add: true) }
            t.check(!ok, "reported as a problem")
            t.eq(readFile(home + "/.zprofile"), "export Z=1\n", "the read-only file is as it was")
            t.eq(readFile(home + "/.bash_profile"), sh, "bash is still done")
            t.check(out.contains("warning: cannot write \(home)/.zprofile"), "the file is named: \(out)")
            if case .failed = classifyStep(unwritableStep(home + "/.zprofile")) {} else { t.check(false, "pretty mode shows it as a failed step") }
            chmod(home + "/.zprofile", 0o644)
        }
    }

    t.test("bash: ~/.profile alone does not make bash a configured shell") {
        shellBox("bash-profile-only", shell: "zsh") { home in
            writeFile(home + "/.profile", "export P=1\n")
            t.check(!shellConfigured("bash"), "a .profile is not a bash signal")
            pathStep(add: true, only: nil)
            t.eq(readFile(home + "/.profile"), "export P=1\n", "nothing written to .profile")
            t.eq(readFile(home + "/.zprofile"), sh, "zsh got it")
        }
        shellBox("bash-rc-profile", shell: "zsh") { home in
            writeFile(home + "/.bashrc", "x\n")
            writeFile(home + "/.profile", "export P=1\n")
            t.check(shellConfigured("bash"), "a .bashrc is")
            pathStep(add: true)
            t.eq(readFile(home + "/.profile"), "export P=1\n" + sh, ".bashrc + .profile: still into .profile")
        }
    }

    t.test("install: a profile reached through a link gets the block once") {
        shellBox("link-dup", shell: "zsh") { home in
            writeFile(home + "/.profile", "export P=1\n")
            writeFile(home + "/.bashrc", "x\n")
            try? FileManager.default.createSymbolicLink(atPath: home + "/.zprofile", withDestinationPath: home + "/.profile")
            pathStep(add: true)
            t.eq(readFile(home + "/.profile"), "export P=1\n" + sh, "one block")
            t.eq(backupsIn(home).count, 1, "one backup")
            let ts = [pathTarget("zsh"), pathTarget("bash")]
            t.eq(addToProfile(ts[0]), .already, "a stale target is re-read")
        }
    }

    t.test("install: a profile that cannot be backed up is reported as that, and left as it is") {
        shellBox("bak-fail", shell: "zsh") { home in
            writeFile(home + "/.zprofile", "export Z=1\n")
            let ro = home + "/ro"
            try? FileManager.default.createDirectory(atPath: ro, withIntermediateDirectories: true)
            chmod(ro, 0o555)
            let was = envVar("JEB_BACKUPS")
            setEnvVar("JEB_BACKUPS", ro + "/backups")
            defer { setEnvVar("JEB_BACKUPS", was); chmod(ro, 0o755) }
            if getuid() == 0 { return }
            var ok = true
            let out = printed { ok = pathStep(add: true) }
            t.check(!ok, "a problem")
            t.eq(readFile(home + "/.zprofile"), "export Z=1\n", "left as it is")
            t.check(out.contains("warning: could not back up \(home)/.zprofile; left it as it is"), out)
            t.check(!out.contains("cannot write"), out)
            if case .failed = classifyStep(backupFailedStep(home + "/.zprofile")) {} else { t.check(false, "pretty: failed step") }
        }
    }

    t.test("install: a profile that cannot be read is not overwritten") {
        shellBox("unreadable", shell: "zsh") { home in
            writeFile(home + "/.zprofile", "export Z=1\n")
            chmod(home + "/.zprofile", 0o200)
            defer { chmod(home + "/.zprofile", 0o644) }
            if getuid() == 0 { return }
            var ok = true
            let out = printed { ok = pathStep(add: true) }
            t.check(!ok, "a problem")
            chmod(home + "/.zprofile", 0o644)
            t.eq(readFile(home + "/.zprofile"), "export Z=1\n", "untouched")
            t.check(out.contains("warning: cannot read \(home)/.zprofile; check its permissions"), out)
            if case .failed = classifyStep(unreadableStep(home + "/.zprofile")) {} else { t.check(false, "pretty: failed step") }
        }
    }

    t.test("exportLine and reloadCommand shell-quote a non-default folder") {
        sandbox("export-quote") { home, _, _ in
            let was = envVar("JEB_BIN_DIR")
            defer { setEnvVar("JEB_BIN_DIR", was) }
            let d = home + "/my \"b$in"
            setEnvVar("JEB_BIN_DIR", d)
            t.eq(exportLine(), "export PATH=" + shQuote(d) + ":\"$PATH\"")
            t.eq(reloadCommand("zsh"), exportLine())
            t.eq(reloadCommand("bash"), exportLine())
            t.check(exportLine().contains("'"), "quoted")
        }
    }

    /// A scratch HOME with a valid schema 2 bundle as ~/.jeb/current, so liveValid() holds.
    func makeLive(_ home: String) {
        let v = home + "/.jeb/versions/v1"
        writeFile(v + "/bundle.json", "{\"schema\":2,\"tag\":\"v1\"}")
        writeFile(v + "/app/JebDesktop", "x", mode: 0o755)
    }

    t.test("add-path: not installed is refused, success writes and exits 0, a second run is still 0") {
        sandbox("addpath-rc") { home, bin, profile in
            var rc: Int32 = 9
            let out = printed { rc = cmdAddPath([]) }
            t.eq(rc, 1, "not installed")
            t.check(out.contains("Jeb is not installed"), out)
            makeLive(home)
            rc = 9
            _ = printed { rc = cmdAddPath([]) }
            t.eq(rc, 0, "wrote")
            t.eq(readFile(profile), sh)
            t.eq(linkState(), "ours")
            rc = 9
            let again = printed { rc = cmdAddPath([]) }
            t.eq(rc, 0, "already set up")
            t.check(again.contains("already has the PATH line"), again)
            setEnvVar("PATH", "/usr/bin:" + bin)
            rc = 9
            let onPathOut = printed { rc = cmdAddPath([]) }
            t.eq(rc, 0, "already on PATH")
            t.check(!onPathOut.contains("already has the PATH line"), "its own message path")
        }
    }

    t.test("add-path: a foreign jebctl at the link path, or a file that cannot be written, is exit 1") {
        sandbox("addpath-fail") { home, bin, profile in
            makeLive(home)
            writeFile(bin + "/jebctl", "#!/bin/sh\necho mine\n", mode: 0o755)
            var rc: Int32 = 0
            _ = printed { rc = cmdAddPath([]) }
            t.eq(rc, 1, "the link is refused")
            t.check(!lexists(profile), "and the profile is not written")
            unlink(bin + "/jebctl")
            writeFile(profile, "export Z=1\n")
            chmod(profile, 0o444)
            _ = printed { rc = cmdAddPath([]) }
            t.eq(rc, 1, "a read-only profile")
            chmod(profile, 0o644)
        }
        shellBox("addpath-fish-foreign", shell: "zsh") { home in
            makeLive(home)
            writeFile(home + "/.config/fish/conf.d/jeb.fish", "# mine\n")
            var rc: Int32 = 0
            _ = printed { rc = cmdAddPath(["fish"]) }
            t.eq(rc, 1, "a named shell's file left alone")
        }
    }

    t.test("uninstall: a jeb.fish with other lines keeps them, one that is only Jeb's goes") {
        shellBox("fish-strip", shell: "fish") { home in
            let f = home + "/.config/fish/conf.d/jeb.fish"
            writeFile(f, fishFile + "set -x A 1\n")
            removeFromProfile()
            t.eq(readFile(f), "set -x A 1\n", "only Jeb's two lines go")
            t.eq(backupsIn(home).count, 1, "after a backup")
            writeFile(f, fishFile + "\n")
            removeFromProfile()
            t.check(!lexists(f), "nothing else left: the file goes")
        }
    }

    t.test("add-path: a folder with a space or a quote is quoted for fish and nushell, the default lines stay") {
        sandbox("quoting") { home, _, _ in
            t.eq(pathLine("fish"), "fish_add_path -g ~/.local/bin")
            setEnvVar("JEB_BIN_DIR", "/opt/bin")
            t.eq(pathLine("fish"), "fish_add_path -g /opt/bin", "a plain folder is not quoted")
            t.eq(pathLine("nu"), "$env.PATH = ($env.PATH | split row (char esep) | prepend \"/opt/bin\" | uniq)")
            setEnvVar("JEB_BIN_DIR", "/opt/my bin/it's")
            t.eq(pathLine("fish"), "fish_add_path -g '/opt/my bin/it\\'s'", "single quotes, ' escaped")
            t.eq(pathLine("nu"), "$env.PATH = ($env.PATH | split row (char esep) | prepend \"/opt/my bin/it's\" | uniq)", "a space needs no escape in nushell")
            setEnvVar("JEB_BIN_DIR", "/opt/a \"b\" \\c")
            t.eq(pathLine("fish"), "fish_add_path -g '/opt/a \"b\" \\\\c'", "a backslash is doubled")
            t.eq(pathLine("nu"), "$env.PATH = ($env.PATH | split row (char esep) | prepend r#'/opt/a \"b\" \\c'# | uniq)", "a raw string")
            t.eq(nuQuote("/a'#\"b"), "r##'/a'#\"b'##", "more # than any '# inside")
        }
    }
}
