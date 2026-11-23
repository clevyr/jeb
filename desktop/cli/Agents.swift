// Agents: the LaunchAgents of an install. Ported from desktop/jebctl (labels_for, mode, plists, write_plists,
// scrubbed_env, spawn_reload, cmd_reload_agents). Bundle layout only (plan D1): every path a plist names is under
// ~/.jeb/current, the watchdog and release agents run the native jebctl there, and the dev-mode update agent is gone
// (its label stays in allLabels so uninstall and doctor still find a leftover one).
import Foundation

let allLabels = ["com.jeb.desktop", "com.jeb.desktop.watchdog", "com.jeb.desktop.update", "com.jeb.desktop.release"]

/// release follows tags (release agent), never local edits; dev shipped local src edits (update agent) and is gone.
func labelsFor(_ mode: String) -> [String] {
    allLabels.filter { $0 != (mode == "dev" ? "com.jeb.desktop.release" : "com.jeb.desktop.update") }
}

/// JEB_HOME/install-mode as the Python read it: "dev" or "release", and "dev" for a missing or odd file. Only status
/// and doctor print it; the agents are the release ones whatever it says.
func installMode() -> String {
    guard let d = FileManager.default.contents(atPath: modeFilePath) else { return "dev" }
    let m = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return ["dev", "release"].contains(m) ? m : "dev"
}

var installedApp: String { appDir() + "/JebDesktop.app" }
var installedExe: String { installedApp + "/Contents/MacOS/JebDesktop" }
/// The mod and the app source the plists render (JEB_MOD, JEB_SRC): `current`'s, JEB_SRC overriding the second.
var liveMod: String { currentDir() + "/mod" }
var liveSrc: String { envVar("JEB_SRC").flatMap { $0.isEmpty ? nil : $0 } ?? currentDir() + "/desktop/src" }
/// The native jebctl of the live version: what the agents and every detached helper run.
var liveJebctl: String { currentDir() + "/desktop/bin/jebctl" }

// ---- plists ----

/// The LaunchAgent dictionaries of a mode, in label order.
func plists(_ mode: String = "release") -> [(label: String, doc: [String: Any])] {
    let env = ["PATH": sysPath, "JEB_MOD": liveMod, "JEB_SRC": liveSrc]
    let out: [(label: String, doc: [String: Any])] = [
        ("com.jeb.desktop", [
            "Label": "com.jeb.desktop",
            "ProgramArguments": [installedExe],
            "EnvironmentVariables": env.merging(["JEB_START": "launchd"]) { _, new in new },
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ThrottleInterval": 10,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": stateHome + "/run.log",
            "StandardErrorPath": stateHome + "/run.log",
        ]),
        ("com.jeb.desktop.watchdog", [
            "Label": "com.jeb.desktop.watchdog",
            "ProgramArguments": [liveJebctl, "watchdog"],
            "EnvironmentVariables": env,
            "StartInterval": 30,        // no RunAtLoad: at login the agent's own RunAtLoad start goes first
            "ProcessType": "Background",
            "LimitLoadToSessionType": "Aqua",
            "StandardErrorPath": stateHome + "/watchdog.err",
        ]),
        ("com.jeb.desktop.release", [
            "Label": "com.jeb.desktop.release",
            "ProgramArguments": [liveJebctl, "follow"],
            "EnvironmentVariables": env,
            "RunAtLoad": true,
            "StartInterval": 21600,     // every 6 h
            "Nice": 10,
            "ProcessType": "Background",
            "LimitLoadToSessionType": "Aqua",
            "StandardErrorPath": stateHome + "/release.err",
        ]),
    ]
    let want = labelsFor(mode)
    return out.filter { want.contains($0.label) }
}

/// Writes each plist of the mode into dest (0644, XML). A dry run only prints what it would render.
func writePlists(_ dest: String, _ mode: String = "release") {
    if !dryRun { try? FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true) }
    for (label, doc) in plists(mode) {
        let p = dest + "/" + label + ".plist"
        let env = doc["EnvironmentVariables"] as? [String: String] ?? [:]
        detail("plist \(label): JEB_MOD=\(env["JEB_MOD"] ?? "") JEB_SRC=\(env["JEB_SRC"] ?? "")")
        if dryRun { continue }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: doc, format: .xml, options: 0),
              FileManager.default.createFile(atPath: p, contents: data) else { die("jebctl: cannot write \(p)") }
        chmod(p, 0o644)
        detail("wrote " + p)
    }
}

// ---- launchctl ----

/// The gui domain of this user, where the agents load.
var guiDomain: String { "gui/\(getuid())" }

/// launchctl through jebctl's sh(): found on PATH as the Python did (the sandboxes put a fake one first), echoed with
/// --verbose, skipped on a dry run.
/// launchctl through the PATH one (a sandbox puts a fake first). JEB_NO_LAUNCHCTL=1 never reaches the real /bin/launchctl: the
/// call only succeeds, so a sandbox cannot touch the user's LaunchAgents.
func launchctlRun(_ args: [String]) -> RunResult {
    let bin = which("launchctl") ?? "/bin/launchctl"
    if noLaunchctl && bin == "/bin/launchctl" { return RunResult(status: 0, out: "", err: "") }
    return run([bin] + args)
}

@discardableResult
func launchctl(_ args: [String]) -> Int32 {
    detail("$ launchctl " + args.joined(separator: " "))
    if dryRun { return 0 }
    let r = launchctlRun(args)
    if !r.text.isEmpty && verbose { say(r.text) }
    return r.status
}

/// The environment for a detached jebctl: this one's without the paths a caller may have pointed at another version.
func scrubbedEnv() -> [String: String] {
    ProcessInfo.processInfo.environment.filter { !["JEB_MOD", "JEB_SRC", "JEB_BUNDLE_MOD"].contains($0.key) }
}

/// Reload the release agents once this process has exited (a detached jebctl in a new session, so launchd does not
/// take it down with follow). Under --no-agents or JEB_NO_LAUNCHCTL it only logs.
func spawnReload(noAgents: Bool) {
    if noAgents || noLaunchctl {
        rlog("convert: would reload the LaunchAgents once this run has exited (sandbox: skipped)")
        return
    }
    spawnDetached([liveJebctl, "reload-agents", "--wait-pid", String(Clock.pid)], env: scrubbedEnv(), output: stateHome + "/release.err")
}

/// Hidden: wait for --wait-pid to exit (at most 120 s), then bootout and bootstrap each release LaunchAgent.
func cmdReloadAgents(_ args: [String]) -> Int32 {
    _ = waitPid(args)
    for l in labelsFor("release") {
        if args.contains("--no-agents") || noLaunchctl {
            rlog("reload-agents: would reload \(l) (sandbox: skipped)")
            continue
        }
        launchctl(["bootout", "\(guiDomain)/\(l)"])
        let r = run([which("launchctl") ?? "/bin/launchctl", "bootstrap", guiDomain, agentsDir() + "/" + l + ".plist"])
        rlog("reload-agents: \(l) " + (r.status == 0 ? "reloaded" : "bootstrap failed: \(String(r.text.prefix(150)))"))
    }
    return 0
}
