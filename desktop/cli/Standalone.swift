// Standalone: `jebctl install` for a jebctl that is not inside a release bundle (the copy the README's curl line fetches into
// ~/.jeb/bin, or the dev build). It is the schema-2 install path: the newest release (the releases/latest
// redirect, no API or sign-in), its manifest signature against signerLines (nothing is pinned yet), its hashes,
// the unpack into ~/.jeb/versions/<tag> with fetchBundle's safety checks, then `exec <ver>/desktop/bin/jebctl install ...` so the
// bundle's own jebctl does the install, and moves an old git clone aside itself once the new one works. An installed Jeb updates instead.
import Foundation

let standaloneUsage = "usage: jebctl install [--repin] [--add-path[=zsh,bash,fish,nu]] [--no-add-path] [--replace-clone (no longer needed)] [--no-agents] [--dry-run] [--verbose] [--plain]"

struct StandaloneFlags: Equatable {
    var dry = false, noAgents = false, verbose = false, repin = false, replaceClone = false, plain = false
    var path = PathFlags()
    var bad: String?        // the first option that is not one of these (--dev and --build-from-source are gone)

    /// What the bundle's own install is told: everything but --replace-clone, which does nothing now (the bundle's install moves an old clone itself).
    var forward: [String] {
        var out: [String] = []
        if dry { out.append("--dry-run") }
        if noAgents { out.append("--no-agents") }
        if verbose { out.append("--verbose") }
        if repin { out.append("--repin") }
        if plain { out.append("--plain") }
        return out + path.forward
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
        case "--plain": f.plain = true
        case "--replace-clone": f.replaceClone = true
        default: if !f.path.take(a) && f.bad == nil { f.bad = a }
        }
    }
    return f
}

/// True for an unpacked release bundle: <root>/bundle.json and <root>/desktop/bin/jebctl (the running binary sits at the latter).
func isBundleRoot(_ root: String) -> Bool {
    isRegularFile(root + "/bundle.json") && isExecutableFile(root + "/desktop/bin/jebctl")
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

/// A progress line; pretty mode shows the step spinner instead and keeps only what `always` names (a dry run's plan).
func standaloneStep(_ s: String, always: Bool = false) { if !Style.pretty || always { say("  " + s) } }

/// Replaces this process with the bundle's jebctl (execve). Only returns, with 1, when it cannot start. A header this process
/// drew is passed on in JEB_HEADER_SHOWN, in the hand-over's environment alone, so the bundle's install does not draw it twice.
func execBundleInstall(_ jebctl: String, _ args: [String]) -> Int32 {
    var cargs: [UnsafeMutablePointer<CChar>?] = ([jebctl, "install"] + args).map { strdup($0) }
    cargs.append(nil)
    var env = ProcessInfo.processInfo.environment
    if Style.headerDrawn { env["JEB_HEADER_SHOWN"] = "1" }
    var cenv: [UnsafeMutablePointer<CChar>?] = env.map { strdup($0.key + "=" + $0.value) }
    cenv.append(nil)
    execve(jebctl, &cargs, &cenv)
    warn("jebctl: could not run \(jebctl): \(String(cString: strerror(errno)))")
    return 1
}

/// Fetch release `tag` with the pinned signers, staging in a private folder under `tmpRoot` that is removed before this returns
/// (the caller then exits or execs, which would skip a defer of its own).
func standaloneFetch(_ tag: String, signers: [String] = signerLines, tmpRoot: String = NSTemporaryDirectory()) -> (path: String?, err: BundleError?) {
    let tmp = (tmpRoot.hasSuffix("/") ? tmpRoot : tmpRoot + "/") + "jebctl-" + UUID().uuidString
    try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(atPath: tmp) }
    let pin = tmp + "/signers"
    do { try writePrivate(signers.joined(separator: "\n") + "\n", to: pin) }
    catch { return (nil, BundleError(why: "\(error)", permanent: false, kind: nil)) }
    return fetchBundle(tag, log: { standaloneStep($0) }, pin: pin, staging: tmp)
}

/// Run `update` until it stops changing the installed tag (at most `passes` times); the last update's exit code. An install
/// that pins only older signers reaches the newest release in two updates (the first adopts the newer signers), so one is not enough.
func standaloneUpdateLoop(passes: Int = 3, update: () -> Int32 = { run([liveJebctl, "update"], capture: false).status },
                          readTag: () -> String? = installedTag) -> Int32 {
    var rc: Int32 = 0
    for pass in 1...passes {
        let before = readTag()
        rc = update()
        let after = readTag()
        if rc != 0 || after == before || pass == passes { break }
        standaloneStep("updated to \(after ?? "a newer release"); checking for a newer release")
    }
    return rc
}

/// `jebctl install` outside a bundle. flags: what follows `install`. signers: the trusted lines (tests pass their own key).
/// handOff: runs the unpacked bundle's `desktop/bin/jebctl install` (default: exec). The exit code.
func standaloneInstall(_ flags: [String], signers: [String] = signerLines,
                       handOff: (String, [String]) -> Int32 = execBundleInstall,
                       update: () -> Int32 = { run([liveJebctl, "update"], capture: false).status },
                       addPath: ([String]) -> Int32 = { run([liveJebctl, "add-path"] + $0, capture: false).status },
                       readTag: () -> String? = installedTag,
                       latest: () -> String? = { envVar("JEB_RELEASE_TAG") ?? (try? latestTag(releaseBase(releaseRepo()))) },
                       fetch: (String, [String]) -> (path: String?, err: BundleError?) = { standaloneFetch($0, signers: $1) }) -> Int32 {
    let f = parseStandaloneFlags(flags)
    if let bad = f.bad {
        say("jebctl install: unknown option \(bad)\n" + standaloneUsage)
        return 2
    }
    if let e = f.path.error {
        say("jebctl install: \(e)\n" + standaloneUsage)
        return 2
    }
    dryRun = f.dry
    verbose = f.verbose
    let tag = f.dry ? " (dry run)" : ""
    // a Jeb that is already installed updates itself, then says how it is; a schema 1 one has no `update` to run, so it takes
    // the fresh path, which the bundle's own install finishes
    var headerDrawn = false
    if liveValid() && readBundle(currentDir())?["schema"]?.int == 2 {
        Style.announce(plain: "Jeb is installed: updating it\(tag)", mode: .update)
        headerDrawn = true
        if f.dry {
            standaloneStep("would run jebctl update (again while it installs a newer release), then \(f.path.add ? "jebctl add-path and " : "")jebctl doctor", always: true)
            return 0
        }
        let rc = standaloneUpdateLoop(update: update, readTag: readTag)
        if linkState() == "older" { _ = linkJebctl() }      // a link to a clone that moved or went away
        // still behind the newest release (an update that could not get there): the fresh path installs it
        let behind: Bool = {
            guard let newest = latest(), let nk = tagKey(newest) else { return false }
            guard let have = readTag(), let hk = tagKey(have) else { return true }
            return hk < nk
        }()
        if !behind { return finishLiveUpdate(f, rc: rc, addPath: addPath) }
        standaloneStep("still behind the newest release; installing it")
        Style.mode = .install
    }
    return freshInstall(f, tag: tag, headerDrawn: headerDrawn, signers: signers, handOff: handOff, fetch: fetch)
}

/// The live branch's last steps: PATH setup when asked, then the doctor. The exit code.
private func finishLiveUpdate(_ f: StandaloneFlags, rc first: Int32, addPath: ([String]) -> Int32) -> Int32 {
    var rc = first
    if f.path.add {
        if rc == 0 {        // the live jebctl is the updated one: an older one may not know add-path
            let a = addPath(f.path.shells.map { [$0.joined(separator: ",")] } ?? [])
            if a != 0 { rc = a }
        } else {
            say("note: PATH setup was skipped because the update did not finish; run `\(selfCommand()) add-path` to set it up")
        }
    }
    _ = run([liveJebctl, "doctor"], capture: false)
    return rc
}

/// The fresh path: fetch the newest release, verify it with the built-in signers, hand over to the bundle's own install (which
/// does everything to the machine: the state folder, the pin, an old clone, the plugin).
private func freshInstall(_ f: StandaloneFlags, tag: String, headerDrawn: Bool, signers: [String],
                          handOff: (String, [String]) -> Int32, fetch: (String, [String]) -> (path: String?, err: BundleError?)) -> Int32 {
    if !Style.pretty { say("Installing Jeb\(tag)") }
    if Style.pretty {       // the header and the fetch spinner before any network work, so a failure shows under them
        if !headerDrawn { Style.announce(plain: "", mode: .install) }
        lead("fetch")
    }
    /// A failed fetch step closed, then the reason and exit.
    func failFetch(_ msg: String) -> Never {
        if openLine { fin("failed") }
        die(msg)
    }
    let arch = hostArch(), base = releaseBase(releaseRepo())
    standaloneStep("architecture: \(arch)")
    let newest: String
    if let pinned = envVar("JEB_RELEASE_TAG") {
        // a named release instead of the newest (./release smoke <tag>); it is verified like any other
        guard tagKey(pinned) != nil else { failFetch("jebctl: JEB_RELEASE_TAG=\(pinned) is not a release tag (vX.Y.Z)") }
        newest = pinned
    } else {
        do { newest = try latestTag(base) }
        catch let e as FetchError {
            if e.status == 404 { failFetch("jebctl: \(base) has no published release (HTTP 404; is the repository public?)") }
            failFetch("jebctl: could not reach GitHub (\(e)); check the network and run \(selfCommand()) install again")
        } catch { failFetch("jebctl: could not reach GitHub (\(error)); check the network and run \(selfCommand()) install again") }
    }
    standaloneStep((envVar("JEB_RELEASE_TAG") == nil ? "newest release: " : "release (JEB_RELEASE_TAG): ") + newest)
    if f.dry {
        if Style.pretty { fin("skipped (dry run; newest is \(newest))") }
        standaloneStep("would download its manifest, signature and \(arch) zip from \(base)/download/\(newest)/,", always: true)
        standaloneStep("verify the signature and hashes, unpack into \(versionsDir())/<tag> and run the bundle's own install", always: true)
        say("Dry run only; nothing was changed.")
        return 0
    }
    let got = fetch(newest, signers)
    if Style.pretty { fin(got.path == nil ? "failed" : "ok (\(newest))") }
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
