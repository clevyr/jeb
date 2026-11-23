// Tools: the pinned TypeScript. Installed once by the runner (unsandboxed), its file tree hashed into tools.sha256, and
// verified before every use.
import Foundation

func ensureTools(_ c: Ctx) throws {
    let p = c.p
    if !FileManager.default.isReadableFile(atPath: p.tscJS) || isDir(p.tscJS) {
        rmrf(p.tools); mkdirp(p.tools)
        let (code, out) = run(c, [p.node, p.npm, "install", "--prefix", p.tools, "--ignore-scripts", "--no-audit", "--no-fund",
                                  "--save-exact", "typescript@\(C.tsVersion)"], cwd: p.tools, timeout: 600)
        if code != 0 || !FileManager.default.isReadableFile(atPath: p.tscJS) {
            throw Abort(msg: "could not install typescript@\(C.tsVersion): \(strip(suffixChars(strip(out), 300)))")
        }
        c.log("tools: installed typescript@\(C.tsVersion) in \(p.tools)")
    }
    if !lexists(p.toolsSha) {
        try Data((try treeDigest(p.tools) + "\n").utf8).write(to: URL(fileURLWithPath: p.toolsSha))
        c.log("tools: recorded \(p.toolsSha)")
    }
    try verifyTools(c)
}

func verifyTools(_ c: Ctx) throws {
    let recorded = readText(c.p.toolsSha).map(strip) ?? ""
    let actual = recorded.isEmpty ? "" : try treeDigest(c.p.tools)
    if recorded.isEmpty || actual != recorded {
        throw Abort(msg: "pinned TypeScript in \(c.p.tools) does not match \(c.p.toolsSha); delete both to re-pin")
    }
}
