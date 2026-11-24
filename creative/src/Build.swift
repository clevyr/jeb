// Build: the build, the dry run, the backup, the in-place sync, the rollback and the status. `build` takes the Builder seam;
// `finishBuild` is everything after the model run, so a test can drive exactly that path with a fake builder.
import Foundation

func build(_ c: Ctx, task: String = "", builder: Builder = ClaudeBuilder()) throws -> Int32 {
    let p = c.p
    if !FileManager.default.fileExists(atPath: p.brief) || !FileManager.default.fileExists(atPath: p.mod) { c.log("skip: brief or mod missing"); return 1 }
    let missing = try briefMismatch(p)
    if !missing.isEmpty { c.log("skip: the brief does not list these builder commands exactly: " + missing.joined(separator: "; ")); return 1 }
    try ensureTools(c)
    let id = c.buildID
    c.log("build \(id): staging" + (task.isEmpty ? "" : " (owner task given: \(task.unicodeScalars.count) chars, sha256 \(prefixChars(sha256Hex(task), 8)))"))
    try copyMod(c, to: p.stage)
    try Data(try briefText(p).utf8).write(to: URL(fileURLWithPath: p.stage + "/.creative-brief.md"))
    try Data((readText(p.changelog) ?? "(no builds yet)\n").utf8).write(to: URL(fileURLWithPath: p.stage + "/.creative-changelog.md"))
    try Data(C.gateTsconfig.dumps().utf8).write(to: URL(fileURLWithPath: p.stage + "/tsconfig.gate.json"))  // the gate writes its own
    // The builder's own output, for diagnosing a run (kept private, last 20).
    mkdirp(p.runs)
    let outPath = "\(p.runs)/\(id).log"
    let (code, out) = builder.run(c, stage: p.stage, prompt: builderPrompt(task), outPath: outPath)
    c.log("build \(id): builder exited \(code)")
    let bytes = Array(out.utf8)
    if bytes.count > 200_000 {
        try Data(utf8Ignore(Array(bytes.suffix(200_000))).utf8).write(to: URL(fileURLWithPath: outPath))
        chmod600(outPath)
    }
    let logs = sortedBytes(((try? FileManager.default.contentsOfDirectory(atPath: p.runs)) ?? []).filter { $0.hasSuffix(".log") })
    for old in logs.dropLast(20) { unlink("\(p.runs)/\(old)") }
    for kept in logs.suffix(20) { chmod600("\(p.runs)/\(kept)") }  // files from before the 0600 rule too
    if lexists(p.changelog) { chmod600(p.changelog) }
    return try finishBuild(c, stage: p.stage, id: id)
}

/// Everything after the builder: take the creative files, both gate passes, the swap, the changelog and the log record.
func finishBuild(_ c: Ctx, stage: String, id: String, requireChange: Bool = true) throws -> Int32 {
    let p = c.p
    let (summary, hint) = takeCreative(stage)
    let (problems, gated) = try checkBuild(c, stage: stage, dest: p.gateCopy, requireChange: requireChange, id: id, hint: hint)
    rmrf(stage)
    if !problems.isEmpty {
        c.log("build \(id): rejected: " + problems.joined(separator: "; "))
        rmrf(p.gateCopy)
        return 2
    }
    if try manifest(p.gateCopy) != gated {
        c.log("build \(id): rejected: the gate copy changed after the gate")
        rmrf(p.gateCopy)
        return 2
    }
    let backup = try backupCurrent(c, id)
    do { try syncIntoMod(c, from: p.gateCopy) } catch {
        c.log("build \(id): swap failed (\(describe(error))); restoring \(backup)")
        try syncIntoMod(c, from: backup)
        c.log("build \(id): restored the mod from \(backup)")
        return 1
    }
    rmrf(p.gateCopy)
    let fd = open(p.changelog, O_WRONLY | O_APPEND | O_CREAT, 0o600)
    if fd >= 0 { writeAll(fd, Array("\n## \(id)\n\(summary.isEmpty ? "(no summary)" : summary)\n".utf8)); close(fd) }
    chmod600(p.changelog)
    c.log("build \(id): swapped in (backup \(backup))")
    return 0
}

func backupFolders(_ c: Ctx) -> [String] {
    sortedBytes((try? FileManager.default.contentsOfDirectory(atPath: c.p.backups)) ?? []).filter { isDir(c.p.backups + "/" + $0) }
}

/// Copy the live mod, links kept as links, to backups/<id>/jeb; then keep the newest 5 backups (errors ignored).
func backupCurrent(_ c: Ctx, _ id: String) throws -> String {
    let dest = "\(c.p.backups)/\(id)/jeb"
    mkdirp((dest as NSString).deletingLastPathComponent)
    try FileManager.default.copyItem(atPath: c.p.mod, toPath: dest)
    for old in backupFolders(c).dropLast(C.keepBackups) { rmrf(c.p.backups + "/" + old) }
    return dest
}

/// Make the mod folder match `src`, in place, never touching `.claude-plugin/types/`. The folder is never renamed: sessions watch
/// it and reload once a quick run of saves stops. Each changed file is written to a temporary name and renamed over the old one.
func syncIntoMod(_ c: Ctx, from src: String) throws {
    let mod = c.p.mod
    for e in try walk(src) where !isTypes(e.rel) {
        let dst = mod + "/" + e.rel, cur = lstatOf(dst)
        if isDirMode(e.st) {
            if let cur = cur, !isDirMode(cur) { unlink(dst) }
            mkdir(dst, 0o777)
        } else if isRegular(e.st) {
            if let cur = cur, isRegular(cur), readBytes(dst) == readBytes(e.path) { continue }
            if let cur = cur, isDirMode(cur) { rmrf(dst) }
            let tmp = dst + ".swap-tmp"
            unlink(tmp)
            try createFile(tmp, readBytes(e.path) ?? [], mode: e.st.st_mode & 0o7777)
            let tv = timeval(tv_sec: e.st.st_mtimespec.tv_sec, tv_usec: Int32(e.st.st_mtimespec.tv_nsec / 1000))
            var both = [tv, tv]
            chmod(tmp, e.st.st_mode & 0o7777); utimes(tmp, &both)
            if rename(tmp, dst) != 0 { throw Abort(msg: "could not replace \(shown(e.rel))") }
        } else { throw Abort(msg: "not a plain file: \(shown(e.rel))") }
    }
    for e in try walk(mod).reversed() where !isTypes(e.rel) && !lexists(src + "/" + e.rel) {
        if isDirMode(e.st) { try FileManager.default.removeItem(atPath: e.path) } else if unlink(e.path) != 0 { throw Abort(msg: "could not remove \(shown(e.rel))") }
    }
}

func dryRun(_ c: Ctx) throws -> Int32 {
    let p = c.p
    let missing = try briefMismatch(p)
    if !missing.isEmpty { c.log("dry run: the brief does not list these builder commands exactly: " + missing.joined(separator: "; ")); return 2 }
    try ensureTools(c)
    let stage = p.staging + "/dry"
    try copyMod(c, to: stage)
    let problems = try gateStaging(c, stage: stage, dest: p.gateCopy, requireChange: false)
    rmrf(stage); rmrf(p.gateCopy)
    c.log("dry run: " + (problems.isEmpty ? "passes every gate" : "would reject: " + problems.joined(separator: "; ")))
    return problems.isEmpty ? 0 : 2
}

func rollback(_ c: Ctx) throws -> Int32 {
    guard let latest = backupFolders(c).last else { c.log("rollback: no backups"); return 1 }
    try syncIntoMod(c, from: "\(c.p.backups)/\(latest)/jeb")
    rmrf("\(c.p.backups)/\(latest)")
    c.log("rollback: restored \(latest)")
    return 0
}

func status(_ c: Ctx) -> Int32 {
    c.echo(readText(c.p.log).map { suffixChars($0, 3000) } ?? "no runs yet")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: c.p.backups)).map(sortedBytes)
    c.echo("backups: " + (names.map { $0.joined(separator: ", ") } ?? "none"))
    return 0
}
