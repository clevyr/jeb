// jeb-creative-build: the daily creative build for the Jeb mod. Copies the mod (../mod, beside this binary) to a staging folder
// and lets a headless Sonnet session build one new thing there (it reads brief.md beside this binary). It has no web access and
// no subagents; its Bash runs in a sandbox that reads only staging and its tools, writes only there, and reaches no network.
// After it exits, the runner copies staging to a folder of its own and gates that copy. Only a build that passes every gate is
// synced into the mod, in place; the old mod is backed up first. A failed build is thrown away. Nothing here installs, loads
// or schedules anything: the builder runs only when the owner runs it.
//
//   jeb-creative-build               build, gate, swap in on success
//   jeb-creative-build --task TEXT   build as above, with a one-off request (up to 1000 printable characters) added to the prompt
//   jeb-creative-build --dry-run     copy and gate the current mod, no model run
//   jeb-creative-build --rollback    restore the most recent backup
//   jeb-creative-build --status      last runs and backups
//   jeb-creative-build --probe legit|hostile   sandbox probe, a Haiku run (cents), by hand
//
// Exit codes: 0 done; 1 skipped, failed or error; 2 rejected by the gate, or bad arguments; 3 another run holds the lock.
import Foundation

enum Command { case build(String), dryRun, rollback, status, probe(String) }

/// nil for anything that is not exactly one of the commands above (decision 3: no unknown argument starts a paid build).
func parseArgs(_ a: [String]) -> Command? {
    switch a.first {
    case nil: return .build("")
    case "--dry-run" where a.count == 1: return .dryRun
    case "--rollback" where a.count == 1: return .rollback
    case "--status" where a.count == 1: return .status
    case "--probe" where a.count == 2 && ["legit", "hostile"].contains(a[1]): return .probe(a[1])
    case "--task" where a.count == 2: return .build(a[1])
    default: return nil
    }
}

func homeFolder() -> String {
    if let h = ProcessInfo.processInfo.environment["HOME"], !h.isEmpty { return h }
    return getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
}

func runMain() -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.first == "--task" && args.count != 2 { print("--task: usage: --task TEXT"); return 2 }
    guard let cmd = parseArgs(args) else {
        FileHandle.standardError.write(Data((C.usage + "\n").utf8))
        return 2
    }
    // The executable's own folder, symlinks resolved: mod and brief.md are found beside it.
    let exe = URL(fileURLWithPath: CommandLine.arguments[0].contains("/") ? CommandLine.arguments[0] : (Bundle.main.executablePath ?? CommandLine.arguments[0]))
    let c = Ctx(Paths(home: homeFolder(), exeDir: exe.resolvingSymlinksInPath().deletingLastPathComponent().path))
    if case .build(let task) = cmd, args.first == "--task", let problem = taskProblem(task) { print("--task: \(problem)"); return 2 }
    mkdirp(c.p.root)
    let lock = open(c.p.lock, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    if lock < 0 || flock(lock, LOCK_EX | LOCK_NB) != 0 { print("another run is in progress"); return 3 }
    do {
        switch cmd {
        case .build(let task): return try build(c, task: task)
        case .dryRun: return try dryRun(c)
        case .rollback: return try rollback(c)
        case .status: return status(c)
        case .probe(let phase): return try probe(c, phase)
        }
    } catch let a as Abort {
        c.log("aborted: \(a.msg)")
        return 1
    } catch {
        c.log("error: \(describe(error))")
        return 1
    }
}

exit(runMain())
