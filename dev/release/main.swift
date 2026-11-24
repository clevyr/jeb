// release: cut a Jeb release from this clone (owner side, local, no CI), build its bundles, or smoke-test a published
// one. Not shipped: a development tool, built by build.sh.
//
// The clone is JEB_RELEASE_CLONE when set (tests: a throwaway repo), else the folder three levels above this binary
// (<clone>/dev/release/release).
import Foundation

let usageText = """
./release [patch|minor|major] [--dry-run] | ./release setup [--dry-run] | ./release smoke [TAG] [--dry-run]: cut a Jeb release from this clone (owner side, local, no CI), or smoke-test a published one.

  ./release setup         one-time signing setup. When this clone has no SSH signing key configured, makes
                          ~/.ssh/jeb_signing (ed25519; ssh-keygen asks for a passphrase) unless it exists and
                          points this clone's git at it (gpg.format ssh, user.signingkey = the private key; a
                          release asks for its passphrase once, first, and holds it in a private ssh-agent
                          that ends with the run). Keys carry no email; the principal is `jeb-release`. Then
                          creates desktop/release-signers (ssh allowed_signers format) from that public key
                          when it does not exist; when it exists it is never overwritten: setup shows its
                          fingerprints, whether the configured key is in it, and the line to add when not.
                          Commit and push the file before the first release: installs pin it on first install
                          and adopt it from newer signed releases.
  ./release               the usual way. Picks the bump from the Conventional Commits since the last tag, as
                          release-please does (`!` or a BREAKING CHANGE footer: major, feat: minor, fix/perf/revert:
                          patch; nothing releasable: refuses) and writes release notes from them. The first
                          release (no tag yet) is 1.0.0. The version always comes from the tags; plugin.json
                          only records it.
  ./release patch|minor|major
                          the same with the bump forced. A new version is written to plugin.json and
                          committed (chore(release): v<version>) only after every check passes.
                          Both run the checks (clean tree on the default branch, the signers jebctl pins, mod
                          checks, universal release build, parity and day gates) before anything is written,
                          then the signed tag v<version>, whose message carries the SHA-256 of the app zip.
                          On success they ask once, then push <base> and <tag> and publish the GitHub release
                          with those notes and the assets
                          (`gh release create <tag> --verify-tag --notes-file ... <assets>`), only on y; it
                          refuses when the app zip is missing. Assets: Jeb-<tag>-macos-arm64.zip and -x86_64.zip
                          (the bundles users install: the tree, the prebuilt app and the native jebctl),
                          Jeb-<tag>-manifest.json and its .sig (signed with the tag's key in the `jeb-release`
                          namespace), jebctl-macos (the universal native jebctl, also inside every bundle as
                          desktop/bin/jebctl; its name, size and SHA-256 are in the manifest under "jebctl"; a
                          new user's first copy is a curl of
                          github.com/clevyr/jeb/releases/latest/download/jebctl-macos), and
                          JebDesktop-<tag>-macos.zip (JebDesktop plus the universal detect and png2raw; its
                          SHA-256 is in the signed tag). Without a terminal they print those commands instead.
  ./release bundle --tag vX.Y.Z --out DIR [--ref REF] [--from-tree] [--app DIR] [--key K] [--signers F]
                          builds the release bundles without releasing: Jeb-<tag>-macos-arm64.zip and -x86_64.zip
                          (the tracked tree from `git archive REF` (default HEAD), or with --from-tree the
                          working tree's files; the prebuilt app and the native jebctl from --app (default
                          .git/jeb-release-<tag>/stage; JebDesktop, detect, png2raw and jebctl); bundle.json),
                          then Jeb-<tag>-manifest.json signed with --key (default user.signingkey) in the
                          `jeb-release` namespace and verified against the bundle's own desktop/release-signers
                          (--signers replaces that file, for tests with a throwaway key).
  ./release smoke [TAG]   sandboxed end-to-end check of a published release; never touches the real install. TAG
                          defaults to the newest published release. Under <git dir>/jeb-smoke/<TAG>/ (an earlier
                          one is moved to old-<time>), with a fake HOME, it downloads the manifest, its signature
                          and the release's jebctl-macos over HTTPS (JEB_RELEASE_BASE overrides where releases are
                          read; it is passed into the sandbox), verifies them against desktop/release-signers,
                          checks jebctl-macos against the manifest and that `--version` names the tag, and runs
                          that `jebctl-macos install --no-agents`, which downloads this Mac's zip, unpacks it
                          into <home>/.jeb/versions/<TAG> and runs the bundle's own install (no LaunchAgent,
                          launchctl or PATH change anywhere; a tag older than v1.5.0 is refused: its
                          jebctl-macos installs with gh). It checks the prebuilt app was used, codesign, that
                          JebMod is <home>/.jeb/current/mod, that current resolves and that versions/ holds one
                          folder. Then the installed `jebctl follow --dry-run` and `jebctl doctor` run read-only
                          (JEB_NO_LAUNCHCTL=1) and the doctor's output is shown. Exit 1 on any failure.
  --dry-run               change nothing: no file, tag or push (smoke: prints the plan).

"""

// ---- the clone ----

let clone: String = {
    if let c = envVar("JEB_RELEASE_CLONE"), !c.isEmpty { return c }
    let a0 = CommandLine.arguments[0]
    var p = pyRealpath(a0.contains("/") ? a0 : (which(a0) ?? a0))
    for _ in 0..<3 { p = (p as NSString).deletingLastPathComponent }
    return p
}()
let desk = clone + "/desktop"
let srcDir = desk + "/src"
let signersPath = desk + "/release-signers"
let pluginJson = clone + "/mod/.claude-plugin/plugin.json"
let repo = "clevyr/jeb"

// ---- leaving ----

/// Folders to remove on the way out (a bundle's work folder, a parity snapshot).
var scratch: [String] = []
/// Appended to a fail() message: what to do about a half-made release.
var failAdvice = ""

func cleanUp() {
    for d in scratch { try? FileManager.default.removeItem(atPath: d) }
    scratch = []
    lockKey()
}

/// The release tool's own refusals.
func fail(_ msg: String) -> Never {
    cleanUp()
    die("release: " + msg + failAdvice)
}

/// A release step's refusal (printed as is, with no prefix).
func stop(_ msg: String) -> Never {
    cleanUp()
    die(msg)
}

/// How far a release got, for Ctrl-C: 0 outside the steps, 1 in them before the release commit, 2 after it.
var stage: Int32 = 0

private func onInterrupt(_: Int32) {
    func put(_ fd: Int32, _ s: StaticString) { _ = write(fd, s.utf8Start, s.utf8CodeUnitCount) }
    put(1, "\n")
    switch stage {
    case 1: put(2, "release: stopped; nothing was written\n")
    case 2: put(2, "release: stopped after the release commit, before the tag; run it again to tag it\n")
    default: put(2, "release: stopped\n")
    }
    if agentPid > 1 { kill(agentPid, SIGTERM) }
    _exit(1)
}

// ---- children ----

/// A program by name: on PATH, else /usr/bin.
func tool(_ name: String) -> String { which(name) ?? "/usr/bin/" + name }

/// argv with its program made absolute (run() does not search PATH): ./x is beside cwd, a bare name is looked up.
func absolute(_ argv: [String], cwd: String? = nil) -> [String] {
    var a = argv
    if a[0].hasPrefix("/") { return a }
    a[0] = a[0].contains("/") ? (cwd ?? FileManager.default.currentDirectoryPath) + "/" + a[0] : tool(a[0])
    return a
}

@discardableResult
func git(_ args: [String]) -> RunResult { run([tool("git"), "-C", clone] + args) }

@discardableResult
func git(_ args: String...) -> RunResult { git(args) }

func cfg(_ key: String) -> String { git("config", "--get", key).out.trimmingCharacters(in: .whitespacesAndNewlines) }

/// A path inside the git dir (git rev-parse --git-path), absolute.
func gitPath(_ name: String) -> String {
    let p = git("rev-parse", "--git-path", name).out.trimmingCharacters(in: .whitespacesAndNewlines)
    return p.hasPrefix("/") ? p : clone + "/" + p
}

/// The environment plus extra.
func environ(_ extra: [String: String]) -> [String: String] {
    ProcessInfo.processInfo.environment.merging(extra) { _, new in new }
}

// ---- probes (desktop/tests/check.sh) ----

private func probe(_ name: String) -> Int32 {
    let spec = (try? Json.parse(envVar("JEB_PROBE_SPEC") ?? "{}")) ?? .object([])
    switch name {
    case "constants":
        let out: Json = .object([
            ("TREE", .array(tree.map(Json.string))), ("PRUNE", .array(prune.map(Json.string))), ("REQUIRED", .array(required.map(Json.string))),
            ("REPO", .string(repo)),
            ("SMOKE_MIN", .array([.int(smokeMin.0), .int(smokeMin.1), .int(smokeMin.2)])), ("SMOKE_TAG_RE", .string(tagPattern)),
            ("INITIAL_VERSION", .string(initialVersion)), ("CC_RE", .string(ccPattern)),
            ("NOTE_GROUPS", .array(noteGroups.map { .array([.string($0.0), .string($0.1)]) })), ("app_name", .string(appZipName("v1.2.3"))),
            ("host_arch", .string(hostArch())),
        ])
        say(out.dumps(indent: 1))
    case "release-plan": say(releasePlanProbe(spec).dumps(indent: 1))
    default: die("release: no probe named \(name)", 2)
    }
    return 0
}

// ---- the release ----

/// ./release [patch|minor|major]: the key first, then the steps, the bundles and (asked once) the push and the GitHub release.
private func release(_ bump: String) -> Int32 {
    noPrivateKeys()
    if !dryRun { unlockKey() }
    defer { lockKey() }
    stage = 1
    let (tag, base) = releaseSteps(["--parity", "--bump", bump], wrapped: true)
    stage = 0
    if dryRun { return 0 }
    if headTags(git: { git($0) }).last != tag { fail("no release tag at HEAD after the release; nothing to push") }
    let notes = gitPath("jeb-release-notes-\(tag).md")
    let adir = gitPath("jeb-release-\(tag)")
    let zp = adir + "/" + appZipName(tag)
    if !isRegularFile(zp) {
        fail("the app zip \(zp) is missing, so no release is published (installs never compile); remove the local tag and run ./release again")
    }
    failAdvice = "\nthe signed tag \(tag) exists locally but nothing was pushed or published; remove it (git tag -d \(tag)) and run ./release again, or fix the problem and run ./release bundle --tag \(tag) --out <dir>"
    let extra = makeBundles(tag: tag, ref: "HEAD", appDir: adir + "/stage", out: adir + "/bundles", key: signingKey())
    failAdvice = ""
    let publish = ["gh", "release", "create", tag, "--verify-tag", "--title", tag] + (isRegularFile(notes) ? ["--notes-file", notes] : ["--generate-notes"]) + [zp] + extra
    let push = "git push origin \(base) \(tag)\n  " + publish.joined(separator: " ")
    if isatty(0) == 0 || isatty(1) == 0 {
        say("no terminal; not pushing. To publish, run:\n  " + push)
        return 0
    }
    print("Push \(base) and \(tag) to origin and publish the GitHub release? [y/N] ", terminator: "")
    fflush(stdout)
    if (readLine() ?? "").trimmingCharacters(in: .whitespaces).lowercased() != "y" {
        say("not pushed. To publish, run:\n  " + push)
        return 0
    }
    var rc = run([tool("git"), "-C", clone, "push", "origin", base, tag], capture: false).status
    if rc != 0 { return rc }
    guard let gh = which("gh") else {
        say("pushed, but gh is not installed. To publish the GitHub release, run:\n  " + publish.joined(separator: " "))
        return 1
    }
    rc = run([gh] + publish.dropFirst(), cwd: clone, capture: false).status
    if rc != 0 {
        say("pushed, but the GitHub release was not created. Installs still follow the tag. To retry, run:\n  " + publish.joined(separator: " "))
    }
    return rc
}

private func main(_ argv: [String]) -> Int32 {
    if argv.first == "--probe" { return probe(argv.count > 1 ? argv[1] : "") }
    dryRun = argv.contains("--dry-run")
    let rest = argv.filter { $0 != "--dry-run" }
    switch rest.first {
    case "bundle": return bundleCmd(Array(rest.dropFirst()))
    case "smoke" where rest.count <= 2: return smoke(rest.count == 2 ? rest[1] : nil)
    case "steps":
        // the steps alone (the release steps on their own): what desktop/tests/check.sh drives in a throwaway repo
        stage = 1
        _ = releaseSteps(Array(rest.dropFirst()), wrapped: false)
        return 0
    default: break
    }
    if !([[], ["setup"], ["patch"], ["minor"], ["major"]] as [[String]]).contains(rest) {
        say(usageText)
        return 2
    }
    return rest == ["setup"] ? setup() : release(rest.first ?? "auto")
}

signal(SIGINT, onInterrupt)
exit(main(Array(CommandLine.arguments.dropFirst())))
