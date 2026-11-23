// Env: the pinned clock and pid (plan D8), strftime under TZ, the output helpers, run/sh and the regex wrappers.
import Foundation

func envTests(_ t: Tester) {
    t.test("clock pinned by JEB_TEST_NOW and JEB_TEST_PID; sleep advances the pin") {
        setEnvVar("JEB_TEST_NOW", "1780000000"); setEnvVar("JEB_TEST_PID", "4242"); Clock.reload()
        t.eq(Clock.epoch, 1780000000); t.eq(Clock.pid, 4242); t.eq(Clock.isPinned, true)
        Clock.sleep(2.5)
        t.eq(Clock.now, 1780000002.5)
        t.eq(Clock.strftime("%Y-%m-%d %H:%M:%S"), "2026-05-28 15:26:42", "TZ=America/Chicago expected")
        t.eq(Clock.today.0, 2026); t.eq(Clock.today.1, 5); t.eq(Clock.today.2, 28)
        setEnvVar("JEB_TEST_NOW", nil); setEnvVar("JEB_TEST_PID", nil); Clock.reload()
        t.eq(Clock.isPinned, false); t.eq(Clock.pid, getpid())
        t.check(abs(Clock.now - Date().timeIntervalSince1970) < 5, "unpinned clock is not the wall clock")
        setEnvVar("JEB_TEST_NOW", "1780000000"); setEnvVar("JEB_TEST_PID", "4242"); Clock.reload()
    }
    t.test("env lookups follow the environment") {
        setEnvVar("JEB_TEST_X", "a"); t.eq(envVar("JEB_TEST_X"), "a")
        setEnvVar("JEB_TEST_X", nil); t.eq(envVar("JEB_TEST_X"), nil)
        t.eq(expandUser("~/x"), homeDir() + "/x"); t.eq(expandUser("/y"), "/y"); t.eq(expandUser("~"), homeDir())
        t.eq(noLaunchctl, true, "run.sh sets JEB_NO_LAUNCHCTL=1")
    }
    t.test("run and sh") {
        let r = run(["/bin/sh", "-c", "echo out; echo err >&2; exit 3"])
        t.eq(r.status, 3); t.eq(r.out, "out\n"); t.eq(r.err, "err\n"); t.eq(r.text, "out\nerr")
        t.eq(run(["/nonexistent/bin"]).status, 127)
        t.eq(run(["/bin/sh", "-c", "echo $JEB_T"], env: childEnv(["JEB_T": "v"])).out, "v\n")
        dryRun = true; verbose = false; defer { dryRun = false; verbose = true }
        t.eq(sh(["/bin/false"], check: true), 0, "a dry run runs nothing")
    }
    t.test("shQuote") {
        t.eq(shQuote("a/b-c.d"), "a/b-c.d"); t.eq(shQuote(""), "''"); t.eq(shQuote("a b"), "'a b'"); t.eq(shQuote("it's"), "'it'\"'\"'s'")
    }
    t.test("regex wrappers") {
        t.eq(reMatch(#"^v(\d+)\.(\d+)$"#, "v1.2"), ["v1.2", "1", "2"])
        t.eq(reMatch(#"^v\d+$"#, "v1.2"), nil)
        t.eq(reMatch(#"(a)|(b)"#, "b"), ["b", "", "b"])
        t.eq(reFindAll(#"t/(v\d)"#, "t/v1 t/v2"), [["t/v1", "v1"], ["t/v2", "v2"]])
    }
}
