// jebctl-tests: the unit tests for the runtime core (desktop/cli minus main.swift), and the golden probes.
//   jebctl-tests                                   run every test, exit 1 on a failure
//   jebctl-tests --probe jebhome --sb D --stub F   print the jebhome probe (see Probes.swift)
//   jebctl-tests --probe updater-status
// tests/run.sh builds and runs it; the environment it expects (JEB_TEST_NOW, TZ, JEB_HOME, JEB_REPO, ...) is set there.
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
var args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

if let probe = option("--probe") {
    let out: Json
    switch probe {
    case "jebhome":
        guard let sb = option("--sb"), let stub = option("--stub") else { die("usage: --probe jebhome --sb <dir> --stub <file>") }
        out = jebhomeProbe(sb: sb, stub: stub)
    case "updater-status":
        out = updaterStatusProbe()
    default:
        die("unknown probe \(probe)")
    }
    print(out.dumps(indent: 1))
    exit(0)
}

let t = Tester()
jsonTests(t)
envTests(t)
fetchTests(t)
stateTests(t)
homeTests(t)
tagsTests(t)
signersTests(t)
watchdogTests(t)
statusTests(t)
pluginTests(t)
installTests(t)
followTests(t)
applyTests(t)
standaloneTests(t)
commandsTests(t)
doctorTests(t)
exit(t.report())
