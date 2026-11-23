// Re-loading Jeb's LaunchAgents when launchd has dropped them (the plists still in ~/Library/LaunchAgents, the
// services gone: updates then stop silently, and the menu's kickstart fails with "Could not find service").
//
// Two moments act: a "Check for Updates" click whose kickstart finds no service bootstraps the plist and kickstarts
// again (or tells the menu it couldn't), and a release install's start re-loads com.jeb.desktop.release and
// .watchdog when they are not loaded. com.jeb.desktop itself is never touched (the app is running), nor the dev
// agents. Only a plist whose program lives under ~/.jeb/current is loaded, so a sandbox's or a stray one never is;
// JEB_MENU_TEST=1 and JEB_NO_LAUNCHCTL=1 only log. AgentHealRule is pure (no I/O) so a scratch harness can
// compile it with Foundation alone; AgentHeal is the launchctl wrapper around it.

import Foundation

/// What the wrapper should do; `report` carries the reason for the log (the menu shows a fixed line).
enum AgentAction: Equatable {
    case none
    case bootstrap                  // `launchctl bootstrap gui/<uid> <plist>`
    case bootstrapThenKickstart
    case skip(String)               // nothing runs; the reason is logged
    case report(String)             // the start failed; logged and shown in the menu
}

struct AgentFacts {
    var label: String
    var loaded: Bool                // launchctl knows the service (kickstart or print exited 0)
    var plist: String?              // the plist's path under the LaunchAgents folder, nil when it is missing
    var program: [String] = []      // its ProgramArguments
    var installMode: String         // jebHome/install-mode, "" when missing
    var liveRoot: String            // ~/.jeb/current
    var dryRun: Bool                // JEB_MENU_TEST=1 or JEB_NO_LAUNCHCTL=1: never call launchctl
}

enum AgentHealRule {
    static let menuLine = "Couldn't start the update — run jebctl doctor"
    static let startupLabels = ["com.jeb.desktop.release", "com.jeb.desktop.watchdog"]

    /// After a click's kickstart.
    static func onClick(_ f: AgentFacts) -> AgentAction {
        if f.loaded { return .none }
        if f.dryRun { return .skip("would bootstrap \(f.label)") }
        guard let plist = f.plist else { return .report("\(f.label) is not loaded and \(f.label).plist is not installed") }
        guard let problem = plistProblem(f) else { return .bootstrapThenKickstart }
        return .report("\(plist): \(problem)")
    }

    /// At app start, for one of `startupLabels`.
    static func atStart(_ f: AgentFacts) -> AgentAction {
        guard f.installMode == "release", startupLabels.contains(f.label) else { return .none }
        if f.loaded { return .none }
        if f.dryRun { return .skip("would bootstrap \(f.label)") }
        guard let plist = f.plist else { return .skip("\(f.label) is not loaded and \(f.label).plist is not installed") }
        guard let problem = plistProblem(f) else { return .bootstrap }
        return .skip("\(plist): \(problem)")
    }

    /// Why the plist must not be loaded: its program (argument 0, or 1 for an interpreter) is not under the live root.
    private static func plistProblem(_ f: AgentFacts) -> String? {
        let root = f.liveRoot.hasSuffix("/") ? f.liveRoot : f.liveRoot + "/"
        let live = f.program.prefix(2).contains { $0.hasPrefix(root) }
        return live ? nil : "ProgramArguments \(f.program) are not under \(f.liveRoot)"
    }
}
