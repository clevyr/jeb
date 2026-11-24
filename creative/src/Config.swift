// Config: every constant, list and regex of the runner (creative/DESIGN.md), and Paths, the value that holds every place the
// runner reads or writes. main builds Paths from HOME and the binary's own folder; the tests build it from temporary folders.
import Foundation

struct Paths {
    var mod, root, cache, backups, brief: String
    var home, claude, nodeDir, node, npm, tools, toolsSha: String
    init(home: String, exeDir: String) {
        self.home = home
        mod = (exeDir as NSString).deletingLastPathComponent + "/mod"
        brief = exeDir + "/brief.md"
        root = home + "/.claude/jeb-creative"
        cache = home + "/Library/Caches/jeb-creative"
        backups = home + "/.claude/backups/jeb"
        tools = cache + "/tools"
        toolsSha = root + "/tools.sha256"
        nodeDir = home + "/.nvm/versions/node/v24.15.0"
        node = nodeDir + "/bin/node"
        npm = nodeDir + "/bin/npm"
        // Absolute, so the builder's Bash rules match one binary exactly.
        claude = home + "/.local/bin/claude"
    }
    var staging: String { cache + "/staging" }
    var stage: String { staging + "/jeb" }
    var gateCopy: String { cache + "/gate/jeb" }
    var log: String { root + "/runs.log" }
    var changelog: String { root + "/CHANGELOG.md" }
    var lock: String { root + "/.lock" }
    var runs: String { root + "/runs" }
    var tscJS: String { tools + "/node_modules/typescript/bin/tsc" }
    var validateCmd: [String] { [claude, "plugin", "validate", "."] }
    var tscCmd: [String] { [node, tscJS, "--noEmit", "-p", "tsconfig.gate.json"] }
    var testCmd: [String] { [claude, "plugin", "test", "."] }
    /// The commands the builder may run, exactly as the brief lists them (D7: the art command is gone).
    var builderCommands: [[String]] { [validateCmd, tscCmd, testCmd] }
}

enum C {
    static let keepBackups = 5, buildTimeout = 45 * 60, testTimeout = 10 * 60, summaryMax = 2000, taskMax = 1000
    static let budget = "3", tsVersion = "5.6.3", builderModel = "claude-sonnet-5-5"
    static let prompt = "Read .creative-brief.md and .creative-changelog.md, then follow the brief."
    static let disallowed = ["WebSearch", "WebFetch", "Agent", "Workflow"]
    // The only built-in tools the builder session has at all; everything else is absent.
    static let builderTools = "Bash,Edit,Read,Write,Glob,Grep"
    /// The type-check the gate runs: hooks and types; the test files are checked by running them.
    static let gateTsconfig = Json.object([("extends", .string("./tsconfig.json")),
                                           ("include", .array([".claude-plugin/types", "hooks", "types"].map(Json.string)))])
    // Patterns a build may never add (counted against the current mod). Python `re` text; ICU accepts every one unchanged.
    static let counted: [(String, String)] = [
        ("model calls", #"\$\.model\."#), ("mcp calls", #"\$\.mcp\."#), ("fs reads", #"\$\.fs\.read"#),
        ("timers", #"\$\.clock\.(every|after)\("#), ("raw timers", #"\b(setTimeout|setInterval)\("#), ("fetch calls", #"\bfetch\("#),
        // The desktop is the only place Jeb shows: no interface inside Claude.
        ("ui calls", #"\$\.ui\."#), ("ui hooks", #"on\(\s*['"`]ui\."#), ("commands", #"\$\.command\."#), ("sound or voice", #"\$\.audio\."#),
        // Ways to reach a $ noun without writing `$.noun`.
        ("indexed $", #"\$\s*\["#), ("aliased $", #"=\s*\$\s*[;\n)]"#),
    ]
    static let forbidden = [
        #"\$\.http\."#, #"\$\.process\."#, #"\$\.fs\.(write|remove|mkdir|rename)"#, #"ui\.notify"#,
        #"on\(\s*['"`]prompt\.(compose|section|context|attachment)"#, #"on\(\s*['"`]attribution\.text"#,
        #"component: '(UserMessage|AssistantMessage|ToolUse|ToolResult|ToolGroup|AskUserQuestion|InfoNotice|CommandOutput)'"#,
        #"\beval\("#, #"new Function\("#,
    ]
    static let creativeFiles = [".creative-brief.md", ".creative-changelog.md", ".creative-hint.txt", ".creative-summary.md"]
    /// Every file a gated build may contain (relative path, whole match). D7: no art sources.
    static let allowedFiles = [
        #"hooks/[^/]+\.tsx?"#, #"hooks/hooks\.json"#, #"tests/[^/]+\.test\.tsx"#, #"types/index\.d\.ts"#, #"art/out/.+\.(png|gif)"#,
        #"tsconfig\.json"#, #"\.claude-plugin/plugin\.json"#, #"\.claude-plugin/icon\.png"#, #"\.claude-plugin/types/.+"#,
    ]
    /// What a build may not change at all (D7 and decision 1b: pixel-art.ts joins the pinned list).
    static let pinnedFiles = [
        "hooks/hooks.json", ".claude-plugin/plugin.json", ".claude-plugin/icon.png", "tsconfig.json", "hooks/signals.ts",
        "hooks/surprise.ts", "hooks/news.ts", "hooks/pixel-art.ts", "hooks/areas.ts", "tests/guard.test.tsx",
    ]
    /// Tests that hold the guarantees; they stay word for word.
    static let lockedTests = ["guard.test.tsx", "perf.test.tsx", "lore.test.tsx", "drops.test.tsx"]
    static let pinnedLines = [("hooks/drops.ts", #"\bMODEL_DAILY_CAP\s*[:=]"#)]
    /// The engine regenerates it, so the builder's copy is never used or synced.
    static let typesDir = [".claude-plugin", "types"]
    // Categories from `claude plugin validate --json` that may not gain items, and ones that may.
    static let guarded = ["hooks", "calls", "env writes", "env reads", "answers its own command", "gating hook without .catch"]
    static let openCategories = ["state writes", "state reads"]
    static let kitFlakeRetries = 4
    static let kitFlake = "it did not finish: its run passed 600000 ms and was killed"
    static let defaultHint = "Been tinkering around the place. Keep your eyes peeled."
    static let usage = "usage: jeb-creative-build [--task TEXT | --dry-run | --rollback | --status | --probe legit|hostile]"
}
