// Doctor: the closing summary (steps de-duplicated, in priority order, numbered; "All good." when nothing failed).
import Foundation

func doctorTests(_ t: Tester) {
    t.test("doctorSummary says All good. when nothing failed") {
        t.eq(doctorSummary(steps: [], problems: 0), ["All good."])
    }
    t.test("doctorSummary lists each step once, in priority order, numbered, commands padded") {
        let steps: [FixStep] = [.newSession, .resume, .reinstall, .start, .reinstall, .start, .resume]
        let got = doctorSummary(steps: steps, problems: 7)
        t.eq(got, [
            "7 problems. To fix them, in order:",
            "  1. jebctl install         reinstalls the app, background agents and plugin",
            "  2. jebctl start           starts the desktop app",
            "  3. jebctl resume-updates  updates were paused on purpose; check before resuming",
            "  4. Start a new Claude Code session so the plugin loads",
        ])
    }
    t.test("doctorSummary names jebctl by a working path when it is not on PATH") {
        let got = doctorSummary(steps: [.restartAll, .redownload("~/.jeb/bin/jebctl")], problems: 2, jebctl: "~/.local/bin/jebctl")
        t.eq(got, [
            "2 problems. To fix them, in order:",
            "  1. ~/.jeb/bin/jebctl install                                 downloads the release again",
            "  2. ~/.local/bin/jebctl quit, then ~/.local/bin/jebctl start  stops every copy, then starts one",
        ])
    }
    t.test("doctorSummary uses the singular for one problem") {
        t.eq(doctorSummary(steps: [.retry], problems: 1), ["1 problem. To fix it, in order:", "  1. jebctl retry-update  runs the last failed update again"])
    }
    t.test("nextFixStep picks runnable steps in priority order") {
        let steps: [FixStep] = [.update, .newSession, .start, .reinstall]
        t.eq(nextFixStep(steps, tried: []), .reinstall)
        t.eq(nextFixStep(steps, tried: [.reinstall]), .start)
    }
    t.test("nextFixStep skips steps already tried and ones it cannot run") {
        let steps: [FixStep] = [.addPath("jebctl"), .newSession, .network, .start, .update]
        t.eq(nextFixStep(steps, tried: [.start]), .update)
    }
    t.test("nextFixStep leaves update and retry-update alone while updates are paused") {
        t.eq(nextFixStep([.resume, .retry, .update, .start], tried: []), .start)
        t.eq(nextFixStep([.resume, .retry, .update], tried: []), nil)
    }
    t.test("nextFixStep is nil when nothing runnable is left") {
        t.eq(nextFixStep([.resume, .newSession, .addPath("jebctl")], tried: []), nil)
        t.eq(nextFixStep([.start, .update], tried: [.start, .update]), nil)
        t.eq(nextFixStep([], tried: []), nil)
    }
}
