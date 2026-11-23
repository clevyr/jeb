// Builder: the model run. The sandbox settings, the claude argv, the prompt, the brief text and its check against the builder
// commands, and the Builder seam: ClaudeBuilder spawns `claude -p`; the tests substitute one that edits staging and returns 0.
import Foundation

protocol Builder { func run(_ c: Ctx, stage: String, prompt: String, outPath: String) -> (Int32, String) }

struct ClaudeBuilder: Builder {
    func run(_ c: Ctx, stage: String, prompt: String, outPath: String) -> (Int32, String) {
        runBuilder(c, builderArgs(c.p, stage: stage, prompt: prompt), cwd: stage, timeout: C.buildTimeout, outPath: outPath)
    }
}

/// The builder's settings: no auto-memory, and its sandbox: reads only staging and its tools, writes only staging (and
/// $TMPDIR), no network, no unsandboxed retry. D7 and decision 9: no Python, so the venv is no longer readable.
func sandboxSettings(_ p: Paths, stage: String) -> Json {
    let allow = [stage, p.nodeDir, p.home + "/.local/share/claude", p.home + "/.local/bin", p.tools]
    let t = Json.bool(true), f = Json.bool(false)
    return .object([("autoMemoryEnabled", f), ("sandbox", .object([
        ("enabled", t), ("failIfUnavailable", t), ("autoAllowBashIfSandboxed", f), ("allowUnsandboxedCommands", f),
        ("filesystem", .object([("denyRead", .array([.string("~")])), ("allowRead", .array(allow.map(Json.string)))])),
        ("network", .object([("allowedDomains", .array([])), ("strictAllowlist", t)])),
    ]))])
}

/// No path-wide file rules: reading and (under acceptEdits) editing are allowed inside staging only; Bash rules are exact.
func builderAllowed(_ p: Paths, extra: [String] = []) -> [String] {
    ["Bash(ls:*)"] + p.builderCommands.map { "Bash(\($0.joined(separator: " ")))" } + extra.map { "Bash(\($0))" }
}

/// Why `--task` text is not acceptable (empty, too long, or not plain printable text), else nil.
func taskProblem(_ text: String) -> String? {
    if strip(text).isEmpty { return "the task is empty" }
    let n = text.unicodeScalars.count
    if n > C.taskMax { return "the task is \(n) characters; the limit is \(C.taskMax)" }
    if !isPrintable(text) { return "the task has control or unprintable characters" }
    return nil
}

/// The standing prompt, plus the owner's one-off request after the brief when given.
func builderPrompt(_ task: String = "") -> String {
    task.isEmpty ? C.prompt : "\(C.prompt)\n\n--- This run's request from the owner (after the brief) ---\n\(task)\n--- End of the owner's request ---"
}

/// `claude -p ...` flag for flag. --disallowedTools and --allowedTools are variadic, so they stay last, in this order.
func builderArgs(_ p: Paths, stage: String, prompt: String = C.prompt, model: String = C.builderModel, budget: String = C.budget,
                 extraAllowed: [String] = []) -> [String] {
    [p.claude, "-p", prompt, "--model", model, "--permission-mode", "acceptEdits", "--setting-sources", "project", "--strict-mcp-config",
     "--mcp-config", Json.object([("mcpServers", .object([]))]).dumps(), "--settings", sandboxSettings(p, stage: stage).dumps(),
     "--max-budget-usd", budget, "--no-session-persistence", "--output-format", "stream-json", "--verbose",
     "--tools", C.builderTools, "--disallowedTools"] + C.disallowed + ["--allowedTools"] + builderAllowed(p, extra: extraAllowed)
}

/// The brief with its `__HOME__` placeholder replaced by this user's home folder.
func briefText(_ p: Paths) throws -> String {
    guard let t = readText(p.brief) else { throw Abort(msg: "cannot read \(p.brief)") }
    return t.replacingOccurrences(of: "__HOME__", with: p.home)
}

/// Builder commands the brief does not spell out exactly (they would be refused).
func briefMismatch(_ p: Paths) throws -> [String] {
    let t = try briefText(p)
    return p.builderCommands.map { $0.joined(separator: " ") }.filter { !t.contains("`\($0)`") }
}
