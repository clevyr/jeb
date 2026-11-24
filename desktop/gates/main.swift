// jebgates: the desktop's gates as one native tool. Not
// shipped: a development tool beside the sources, built by build.sh.
//
//     jebgates parity gen                  write fixtures/<name>.store.json and, in a modcopy, the band's scratch test
//     jebgates parity [compare] [band-out] render every fixture and compare it with the band's picture (fixtures/band-out.txt)
//     jebgates day [day|kinds|limit|evening|again|night|all]
//     jebgates fake <store> <sessions> [busy|idle] [seconds]
//     jebgates all                         parity compare, then day all
//     jebgates smoke | start               the gates `jebctl apply` runs (desktop/cli/Gates.swift): every fixture renders; 20 s headless
//
// --src names desktop/src (fixtures, tools, modcopy; default: ../src beside this binary) and --bin the desktop binary
// (else JEB_BIN, else JebDesktop for parity and JebDesktop.dev for day; a relative name is looked up in --src).
// JEB_MOD names the mod whose art parity compare reads (default: the repo's). Exit: 0 all passed, 1 something failed,
// 2 usage.
import Foundation

private let USAGE = "usage: jebgates smoke|parity|day|start|fake|all [--bin <desktop binary>] [--src <desktop/src>] [arguments]"

private func usage() -> Never {
    errLine(USAGE)
    exit(2)
}

private var args = Array(CommandLine.arguments.dropFirst())
private var src: String?
private var bin: String?
private var rest: [String] = []
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--src", "--bin":
        if args.isEmpty { usage() }
        if a == "--src" { src = args.removeFirst() } else { bin = args.removeFirst() }
    default: rest.append(a)
    }
}
guard let command = rest.first else { usage() }
rest.removeFirst()

private func defaultSrc() -> String {
    let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
    return parentDir(parentDir(URL(fileURLWithPath: exe).resolvingSymlinksInPath().path)) + "/src"
}

private let at = Places(src: src ?? defaultSrc(), bin: bin)

private func parity(_ a: [String]) -> Int32 {
    var a = a
    switch a.first {
    case "gen":
        parityGen(at)
        return 0
    case "compare": a.removeFirst()
    default: break
    }
    if a.count > 1 { usage() }
    return parityCompare(at, a.first ?? at.fixtures + "/band-out.txt") ? 0 : 1
}

/// The gates `jebctl apply` runs (cli/Gates.swift), on --bin (default JebDesktop in --src) with JEB_MOD's art, in a scratch folder.
private func applyGate(_ name: String, _ at: Places) -> Int32 {
    let mod = environ("JEB_MOD").flatMap { $0.isEmpty ? nil : $0 } ?? parentDir(parentDir(at.art))
    let scratch = makeTempDir("jebgates-")
    defer { try? FileManager.default.removeItem(atPath: scratch) }
    let bin = at.binary(default: "JebDesktop")
    let r = name == "smoke" ? gateSmoke(binary: bin, fixtures: at.fixtures, mod: mod, scratch: scratch)
                            : gateStart(binary: bin, mod: mod, liveStore: environ("JEB_STORE_PATH"), scratch: scratch)
    print("\(name): \(r.ok ? "ok" : "FAILED"): \(r.why)")
    return r.ok ? 0 : 1
}

setvbuf(stdout, nil, _IOLBF, 0)
switch command {
case "parity": exit(parity(rest))
case "day":
    if rest.count > 1 { usage() }
    exit(dayMain(at, rest.first ?? "all"))
case "fake": exit(fakeMain(at, rest))
case "all":
    let p = parity([])
    let d = dayMain(at, "all")
    exit(p != 0 || d != 0 ? 1 : 0)
case "smoke", "start":
    exit(applyGate(command, at))
default: usage()
}
