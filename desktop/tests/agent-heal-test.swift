// Checks AgentHealRule (desktop/src/AgentHeal.swift) by the action it returns. Compiled with that file alone by
// run-agent-heal-test.sh: plain swiftc, no XCTest, so a plain Command Line Tools install runs it.

import Foundation

var failures = 0
func check(_ name: String, _ got: AgentAction, _ want: AgentAction) {
    if got == want { print("ok    \(name)") } else { print("FAIL  \(name): got \(got), want \(want)"); failures += 1 }
}
func isReport(_ a: AgentAction) -> Bool { if case .report = a { return true } else { return false } }
func isSkip(_ a: AgentAction) -> Bool { if case .skip = a { return true } else { return false } }
func check(_ name: String, _ got: AgentAction, _ want: (AgentAction) -> Bool, _ wantText: String) {
    if want(got) { print("ok    \(name)") } else { print("FAIL  \(name): got \(got), want \(wantText)"); failures += 1 }
}

let root = "/Users/me/.jeb/current"
let agents = "/Users/me/Library/LaunchAgents"
func facts(_ label: String = "com.jeb.desktop.release", loaded: Bool = false, plist: Bool = true, program: [String]? = nil,
           mode: String = "release", dryRun: Bool = false) -> AgentFacts {
    AgentFacts(label: label, loaded: loaded, plist: plist ? "\(agents)/\(label).plist" : nil,
               program: program ?? ["\(root)/desktop/bin/jebctl", "follow"], installMode: mode, liveRoot: root, dryRun: dryRun)
}

// A click
check("click: loaded and ok", AgentHealRule.onClick(facts(loaded: true)), .none)
check("click: not loaded, plist ok", AgentHealRule.onClick(facts()), .bootstrapThenKickstart)
check("click: not loaded, no plist", AgentHealRule.onClick(facts(plist: false)), isReport, "report")
check("click: plist outside the live root", AgentHealRule.onClick(facts(program: ["/tmp/sandbox/.jeb/current/desktop/bin/jebctl", "follow"])), isReport, "report")
check("click: plist with no program", AgentHealRule.onClick(facts(program: [])), isReport, "report")
check("click: interpreter first, script under the live root", AgentHealRule.onClick(facts(program: ["\(root)/python/bin/python3", "\(root)/desktop/jebctl", "follow"])), .bootstrapThenKickstart)
check("click: live root only as a prefix of another folder", AgentHealRule.onClick(facts(program: ["\(root)-old/desktop/bin/jebctl"])), isReport, "report")
check("click: the live root is not the program's directory", AgentHealRule.onClick(facts(program: ["/usr/bin/env", "\(root)"])), isReport, "report")
check("click: test flag never bootstraps", AgentHealRule.onClick(facts(dryRun: true)), isSkip, "skip")
check("click: dev clone's update agent run by the system python (not under the live root)", AgentHealRule.onClick(facts("com.jeb.desktop.update", program: ["/usr/bin/python3", "-I", "\(root)/desktop/updater.py"], mode: "dev")), isReport, "report")
check("click: dev clone's update agent under the live root", AgentHealRule.onClick(facts("com.jeb.desktop.update", program: ["\(root)/python/bin/python3", "-I", "\(root)/desktop/updater.py"], mode: "dev")), .bootstrapThenKickstart)

// App start
check("start: release, not loaded, plist ok", AgentHealRule.atStart(facts()), .bootstrap)
check("start: watchdog too", AgentHealRule.atStart(facts("com.jeb.desktop.watchdog", program: ["\(root)/desktop/bin/jebctl", "watchdog"])), .bootstrap)
check("start: loaded", AgentHealRule.atStart(facts(loaded: true)), .none)
check("start: dev mode", AgentHealRule.atStart(facts(mode: "dev")), .none)
check("start: mode missing", AgentHealRule.atStart(facts(mode: "")), .none)
check("start: no plist", AgentHealRule.atStart(facts(plist: false)), isSkip, "skip")
check("start: plist outside the live root", AgentHealRule.atStart(facts(program: ["/Users/me/jeb/desktop/bin/jebctl", "follow"])), isSkip, "skip")
check("start: never com.jeb.desktop", AgentHealRule.atStart(facts("com.jeb.desktop", program: ["/Users/me/Applications/JebDesktop.app/Contents/MacOS/JebDesktop"])), .none)
check("start: never the dev update agent", AgentHealRule.atStart(facts("com.jeb.desktop.update")), .none)
check("start: test flag never bootstraps", AgentHealRule.atStart(facts(dryRun: true)), isSkip, "skip")
check("start: no-launchctl flag with a loaded service", AgentHealRule.atStart(facts(loaded: true, dryRun: true)), .none)

// The flags never yield a launchctl action, whatever else is true
for f in [facts(dryRun: true), facts(plist: false, dryRun: true), facts(program: [], dryRun: true), facts(mode: "dev", dryRun: true)] {
    for a in [AgentHealRule.onClick(f), AgentHealRule.atStart(f)] {
        if a == .bootstrap || a == .bootstrapThenKickstart { print("FAIL  flags: \(f) gave \(a)"); failures += 1 }
    }
}
print("ok    flags: no launchctl action under the test flags")

if failures > 0 { print("\(failures) failure(s)"); exit(1) }
print("all passed")
