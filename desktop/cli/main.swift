// jebctl: the one command you run (and desktop/bin/jebctl in a release bundle). Native Swift over the runtime in
// desktop/cli/*.swift; this file is only the dispatch. `install` is the bundle's own install inside a release bundle and
// the standalone fetch-and-install form (Standalone.swift) anywhere else. Built by desktop/cli/build.sh.
//   jebctl --version
//   jebctl watchdog [--dry-run] [--no-recheck-wait] [--fake-procs ...]     Watchdog.swift
//   jebctl apply <bundle> [--not-final] [--lock-held] [--no-watch] [--gates-only] [--quick]     Apply.swift
//   jebctl install [...]
//   jebctl [--dry-run] [--verbose] [--no-agents] <command> ...
//   jebctl --probe <name>     only in a JEB_PROBES build (probes/Probes.swift), for the golden checker
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let argv = Array(CommandLine.arguments.dropFirst())

if argv == ["--version"] { say("jebctl \(jebctlVersion)"); exit(0) }

#if JEB_PROBES
if argv.first == "--probe" {
    guard argv.count > 1 else { die("usage: jebctl --probe <name>") }
    let spec = envVar("JEB_PROBE_SPEC").flatMap { try? Json.parse($0) } ?? .object([])
    guard let out = runProbe(argv[1], spec: spec) else { die("jebctl: unknown probe \(argv[1])") }
    print(out.dumps(indent: 1))
    exit(0)
}
#endif

// the watchdog reads its own flags (--dry-run included)
if argv.first == "watchdog" { exit(Watchdog.main(Array(argv.dropFirst()))) }

// apply reads its own flags too (--not-final, --lock-held, ...) and keeps exit 2 for a gate rejection
if argv.first == "apply" { exit(cmdApply(Array(argv.dropFirst()))) }

let args = argv.filter { $0 != "--dry-run" && $0 != "--verbose" }
dryRun = argv.contains("--dry-run")
noAgents = argv.contains("--no-agents")
let cmd = args.first ?? "status"
if argv.contains("--no-agents"), let why = checkSandbox(cmd) { die("jebctl: " + why) }
verbose = argv.contains("--verbose") || !["install", "uninstall"].contains(cmd)
switch cmd {
case "status": cmdStatus()
case "perf": cmdPerf(args)
case "pause-updates": cmdPauseUpdates()
case "resume-updates": cmdResumeUpdates()
case "start": cmdStart()
case "quit": cmdQuit()
case "reload-agents": exit(cmdReloadAgents(args))
case "prune-versions": cmdPruneVersions(args)
case "doctor": exit(cmdDoctor())
case "install":
    // inside a release bundle: its own install; anywhere else (the standalone jebctl, a dev build): fetch the newest release (Standalone.swift)
    if isBundleRoot(bundleRoot()) { exit(cmdInstall(Array(args.dropFirst()))) }
    var rest = argv
    rest.remove(at: rest.firstIndex(of: "install")!)
    exit(standaloneInstall(rest))
case "uninstall": exit(cmdUninstall(Array(args.dropFirst())))
case "follow": exit(cmdFollow(Array(args.dropFirst())))
case "rollback": rollbackBundle()
case "update": exit(cmdUpdate())
case "retry-update": exit(cmdRetryUpdate())
case "screenshot": exit(cmdScreenshot(Array(args.dropFirst())))
case "emoji": exit(cmdEmoji(Array(args.dropFirst())))
default:
    // an unknown command, --help included: the help text and exit 2
    say(helpText)
    exit(2)
}
