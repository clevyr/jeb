// Standalone: `jebctl install` for a jebctl that is not inside a release bundle (the copy the README's curl line fetches into
// ~/.jeb/bin, or the dev build). It is the schema-2 install path: the newest release (the releases/latest
// redirect, no API or sign-in), its manifest signature against signerLines (nothing is pinned yet), its hashes,
// the unpack into ~/.jeb/versions/<tag> with fetchBundle's safety checks, then `exec <ver>/desktop/bin/jebctl install ...` so the
// bundle's own jebctl does the install. An installed Jeb updates instead; an old git clone is only replaced on request (Q3).
import Foundation

let standaloneUsage = "usage: jebctl install [--repin] [--add-path] [--replace-clone] [--no-agents] [--dry-run] [--verbose]"

struct StandaloneFlags: Equatable {
    var dry = false, noAgents = false, verbose = false, repin = false, addPath = false, replaceClone = false
    var bad: String?        // the first option that is not one of these (--dev and --build-from-source are gone)

    /// What the bundle's own install is told: everything but --replace-clone, which only this step knows.
    var forward: [String] {
        var out: [String] = []
        if dry { out.append("--dry-run") }
        if noAgents { out.append("--no-agents") }
        if verbose { out.append("--verbose") }
        if repin { out.append("--repin") }
        if addPath { out.append("--add-path") }
        return out
    }
}

func parseStandaloneFlags(_ args: [String]) -> StandaloneFlags {
    var f = StandaloneFlags()
    for a in args {
        switch a {
        case "--dry-run": f.dry = true
        case "--no-agents": f.noAgents = true
        case "--verbose": f.verbose = true
        case "--repin": f.repin = true
        case "--add-path": f.addPath = true
        case "--replace-clone": f.replaceClone = true
        default: if f.bad == nil { f.bad = a }
        }
    }
    return f
}

/// True for an unpacked release bundle: <root>/bundle.json and <root>/desktop/bin/jebctl (the running binary sits at the latter).
func isBundleRoot(_ root: String) -> Bool {
    isRegularFile(root + "/bundle.json") && isExecutableFile(root + "/desktop/bin/jebctl")
}

/// An install from before the bundles: a git clone at ~/.jeb/repo or ~/jeb with its Python jebctl. nil when there is none.
func oldCloneInstall() -> String? {
    [jebDir() + "/repo", homeDir() + "/jeb"].first { isRegularFile($0 + "/desktop/jebctl") }
}

/// nil when dir is a usable schema 2 bundle for a standalone install to hand over to; else the reason. fetchBundle has checked
/// the signature, hashes, architecture and member links; this is the shape the bundle's own install needs.
func standaloneBundleProblem(_ dir: String) -> String? {
    guard let b = readBundle(dir) else { return "bundle.json is missing or not an object" }
    let schema = b["schema"]?.int ?? 1
    if schema != 2 { return "this release is a schema \(schema) bundle (a Python-era one); jebctl install needs schema 2" }
    if b["python"] != nil { return "bundle.json names a bundled Python, which a schema 2 bundle does not have" }
    for rel in ["desktop/bin/jebctl", "desktop/release-signers", "mod", ".claude-plugin/marketplace.json", "app/JebDesktop"]
    where !FileManager.default.fileExists(atPath: dir + "/" + rel) {
        return "the bundle lacks \(rel)"
    }
    return isExecutableFile(dir + "/desktop/bin/jebctl") ? nil : "desktop/bin/jebctl is not executable"
}

func standaloneStep(_ s: String) { say("  " + s) }

/// Replaces this process with the bundle's jebctl (execv). Only returns, with 1, when it cannot start.
func execBundleInstall(_ jebctl: String, _ args: [String]) -> Int32 {
    var cargs: [UnsafeMutablePointer<CChar>?] = ([jebctl, "install"] + args).map { strdup($0) }
    cargs.append(nil)
    execv(jebctl, &cargs)
    warn("jebctl: could not run \(jebctl): \(String(cString: strerror(errno)))")
    return 1
}

/// --replace-clone (Q3): the old install's agents are booted out, its folder moves to <clone>.old (no git needed), its
/// CLAUDE_CODE_PLUGIN_DIRS entry leaves settings.json (backup first). nil: carry on with the fresh install; else the exit code.
func replaceOldClone(_ clone: String, _ f: StandaloneFlags) -> Int32? {
    let old = clone + ".old", tag = f.dry ? " (dry run)" : ""
    say("Replacing the old install at \(clone)\(tag)")
    if lexists(old) {
        say("jebctl: \(old) already exists; move it away first. Nothing was changed.")
        return 1
    }
    do { _ = try loadSettings(settingsPath()) } catch {      // before anything moves: a settings file we cannot edit stops here
        say("jebctl: \(error)")
        return 1
    }
    if f.noAgents {
        standaloneStep("agents: left loaded (--no-agents)")
    } else {
        for l in allLabels { launchctl(["bootout", "\(guiDomain)/\(l)"]) }      // "not loaded" is ignored
        standaloneStep("agents: " + (f.dry ? "would boot out the old LaunchAgents" : "booted out"))
    }
    if f.dry {
        standaloneStep("would move \(clone) to \(old)")
    } else if rename(clone, old) != 0 {
        say("jebctl: could not move \(clone) to \(old): \(String(cString: strerror(errno)))")
        return 1
    } else {
        standaloneStep("moved \(clone) to \(old)")
    }
    let act = removeEntry(clone + "/mod", dry: f.dry, say: { detail($0) })
    standaloneStep("plugin entry: " + (act == "absent" ? "not listed in \(settingsPath())" : f.dry ? "would remove it (backup first)" : "removed (backup first)"))
    return nil
}

/// `jebctl install` outside a bundle. flags: what follows `install`. signers: the trusted lines (tests pass their own key).
/// handOff: runs the unpacked bundle's `desktop/bin/jebctl install` (default: exec). The exit code.
func standaloneInstall(_ flags: [String], signers: [String] = signerLines,
                       handOff: (String, [String]) -> Int32 = execBundleInstall) -> Int32 {
    let f = parseStandaloneFlags(flags)
    if let bad = f.bad {
        say("jebctl install: unknown option \(bad)\n" + standaloneUsage)
        return 2
    }
    dryRun = f.dry
    verbose = f.verbose
    let tag = f.dry ? " (dry run)" : ""
    // a Jeb that is already installed updates itself, then says how it is
    if liveValid() {
        say("Jeb is installed: updating it\(tag)")
        if f.dry {
            standaloneStep("would run jebctl update, then jebctl doctor")
            return 0
        }
        let rc = run([liveJebctl, "update"], capture: false).status
        _ = run([liveJebctl, "doctor"], capture: false)
        return rc
    }
    if let clone = oldCloneInstall() {
        if !f.replaceClone {
            say("an old install is at \(clone): run jebctl install --replace-clone")
            return 1
        }
        if let rc = replaceOldClone(clone, f) { return rc }
    }
    say("Installing Jeb\(tag)")
    let arch = hostArch(), base = releaseBase(releaseRepo())
    standaloneStep("architecture: \(arch)")
    let newest: String
    do { newest = try latestTag(base) }
    catch let e as FetchError {
        if e.status == 404 { die("jebctl: \(base) has no published release (HTTP 404; is the repository public?)") }
        die("jebctl: could not reach GitHub (\(e)); check the network and run jebctl install again")
    } catch { die("jebctl: could not reach GitHub (\(error)); check the network and run jebctl install again") }
    standaloneStep("newest release: \(newest)")
    if f.dry {
        standaloneStep("would download its manifest, signature and \(arch) zip from \(base)/download/\(newest)/,")
        standaloneStep("verify the signature and hashes, unpack into \(versionsDir())/<tag> and run the bundle's own install")
        say("Dry run only; nothing was changed.")
        return 0
    }
    let tmp = NSTemporaryDirectory() + "jebctl-" + UUID().uuidString
    try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(atPath: tmp) }
    let pin = tmp + "/signers"
    do { try writePrivate(signers.joined(separator: "\n") + "\n", to: pin) } catch { die("jebctl: \(error)") }
    let got = fetchBundle(newest, log: { standaloneStep($0) }, pin: pin, staging: tmp)
    guard let ver = got.path else {
        let e = got.err
        die("jebctl: " + (e?.permanent == true ? "refusing release \(newest): " : "could not fetch \(newest): ") + (e?.why ?? "unknown error"))
    }
    if let why = standaloneBundleProblem(ver) {
        try? FileManager.default.removeItem(atPath: ver)
        die("jebctl: refusing release \(newest): \(why)")
    }
    standaloneStep("running the bundle's install")
    return handOff(ver + "/desktop/bin/jebctl", f.forward)
}
