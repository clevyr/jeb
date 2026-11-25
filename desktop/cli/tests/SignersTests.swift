// Signers: allowed_signers lines (key_line, parse_signers) and the pin under a scratch JEB_HOME: pin, widen, adopt.
// The signature checks themselves (verify_manifest on real signed files) are the verify-manifest goldens.
import Foundation

func signersTests(_ t: Tester) {
    let dir = t.scratch("signers")
    let home = dir + "/Jeb"
    setHome(home)
    let K = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJebJebJebJebJebJebJebJebJebJebJebJebJebJebJebJ"
    let blob = fields(K)[1]
    let K2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOtherOtherOtherOtherOtherOtherOtherOtherOth"

    t.test("keyLine: the blob, and the namespaces option with its token index") {
        t.eq(keyLine("jeb-release \(K)"), KeyLine(blob: blob, ns: nil))
        t.eq(keyLine("me namespaces=\"git,jeb-release\" \(K) a comment"), KeyLine(blob: blob, ns: .init(index: 1, names: ["git", "jeb-release"])))
        t.eq(keyLine("  me\tcert-authority  namespaces=\"jeb-release\" \(K)"), KeyLine(blob: blob, ns: .init(index: 2, names: ["jeb-release"])))
        t.eq(keyLine("me namespaces=\",git,,\" \(K)"), KeyLine(blob: blob, ns: .init(index: 1, names: ["git"])), "empty names dropped")
        t.eq(keyLine("me namespaces=\"\" \(K)"), KeyLine(blob: blob, ns: .init(index: 1, names: [])))
        t.eq(keyLine("me namespaces=\"a\" namespaces=\"b\" \(K)"), KeyLine(blob: blob, ns: .init(index: 2, names: ["b"])), "the last option wins")
        t.eq(keyLine("me namespaces=\"jeb-release\",valid-after=\"20250101\" \(K)"), KeyLine(blob: blob, ns: nil), "only a namespaces token of its own counts")
        t.eq(keyLine("me \(K) namespaces=\"git\""), KeyLine(blob: blob, ns: nil), "an option after the key is a comment")
        t.eq(keyLine("me ecdsa-sha2-nistp256 AAAAE2Vj"), KeyLine(blob: "AAAAE2Vj", ns: nil))
        t.eq(keyLine("me sk-ssh-ed25519@openssh.com AAAAGnNr"), KeyLine(blob: "AAAAGnNr", ns: nil))
        for none in ["", "   ", "# a comment", "#me \(K)", "me namespaces=\"git\"", "me ssh-ed25519", "\(K)", "me rsa AAAA"] {
            t.eq(keyLine(none), nil, String(reflecting: none))
        }
    }
    t.test("parseSigners: every line principal namespaces=\"..jeb-release..\" keytype base64, or nothing") {
        let good = "jeb-release namespaces=\"jeb-release\" \(K)", both = "me@example.com namespaces=\"git,jeb-release\" \(K2)"
        t.eq(parseSigners(good + "\n" + both + "\n"), [Signer(principal: "jeb-release", keyType: "ssh-ed25519", key: blob), Signer(principal: "me@example.com", keyType: "ssh-ed25519", key: fields(K2)[1])])
        t.eq(parseSigners("# c\r\n\r\n" + good), [Signer(principal: "jeb-release", keyType: "ssh-ed25519", key: blob)], "comments, blanks, CRLF, no final newline")
        for (why, text) in [("empty", ""), ("only comments", "# c\n\n"), ("no namespaces", "jeb-release \(K)\n"), ("git only", "me namespaces=\"git\" \(K)\n"),
                            ("another option", "me cert-authority namespaces=\"jeb-release\" \(K)\n"), ("a trailing comment", good + " comment\n"),
                            ("not base64", "me namespaces=\"jeb-release\" ssh-ed25519 AAAA*\n"), ("one bad line among good", good + "\nme namespaces=\"git\" \(K2)\n"),
                            ("no key", "me namespaces=\"jeb-release\"\n")] {
            t.check(parseSigners(text) == nil, "\(why): parsed")
        }
    }
    t.test("pinSigners: trust on first install, kept unless --repin, 0600") {
        verbose = false; defer { verbose = true }
        let src = dir + "/release-signers"
        writeFile(src, "one\n")
        dryRun = true; pinSigners(repin: false, from: src); dryRun = false
        t.check(!lexists(pinnedSignersPath), "a dry run pinned")
        pinSigners(repin: false, from: src)
        t.eq(readFile(pinnedSignersPath), "one\n"); t.eq(fileMode(pinnedSignersPath), "0o600"); t.eq(fileMode(home), "0o700")
        writeFile(src, "two\n")
        pinSigners(repin: false, from: src)
        t.eq(readFile(pinnedSignersPath), "one\n", "an existing pin is kept")
        pinSigners(repin: true, from: src)
        t.eq(readFile(pinnedSignersPath), "two\n")
    }
    t.test("widenSigners adds namespaces to pinned keys, never a key") {
        verbose = false; defer { verbose = true }
        let src = dir + "/shipped"
        writeFile(src, "jeb-release namespaces=\"git,jeb-release\" \(K)\nnew namespaces=\"jeb-release\" \(K2)\n")
        writeFile(pinnedSignersPath, "# pinned\nme  namespaces=\"x,git\"   \(K) note\n")
        dryRun = true; t.eq(widenSigners(src), true); dryRun = false
        t.eq(readFile(pinnedSignersPath), "# pinned\nme  namespaces=\"x,git\"   \(K) note\n", "a dry run wrote")
        t.eq(widenSigners(src), true)
        t.eq(readFile(pinnedSignersPath), "# pinned\nme namespaces=\"x,git,jeb-release\" \(K) note\n", "own names first; only the changed line is rejoined")
        t.eq(fileMode(pinnedSignersPath), "0o600")
        t.eq(widenSigners(src), false, "nothing left to add")
        writeFile(pinnedSignersPath, "me \(K)\n")
        t.eq(widenSigners(src), false, "a pinned line without namespaces is left alone")
        t.eq(widenSigners(dir + "/nope"), false)
        unlink(pinnedSignersPath)
        t.eq(widenSigners(src), false, "no pin")
    }
    t.test("adoptSigners: the pin follows newer verified releases") {
        let text = "jeb-release namespaces=\"jeb-release\" \(K)\n", src = dir + "/adopt"
        writeFile(src, text)
        unlink(pinnedSignersPath)
        var rs = Json.object([("failed", .array([]))])
        t.eq(adoptSigners(&rs, tag: "junk", src: src), false)
        t.eq(adoptSigners(&rs, tag: "v1.5.0", src: dir + "/nope"), false)
        t.eq(rs["signers_from"]?.dumps(), nil)
        dryRun = true; var dry = rs; t.eq(adoptSigners(&dry, tag: "v1.5.0", src: src), true); dryRun = false
        t.check(!lexists(pinnedSignersPath), "a dry run adopted")
        t.eq(adoptSigners(&rs, tag: "v1.5.0", src: src), true)
        t.eq(readFile(pinnedSignersPath), text); t.eq(fileMode(pinnedSignersPath), "0o600")
        t.eq(rs.dumps(), #"{"failed": [], "signers_from": "v1.5.0"}"#)
        writeFile(src, "jeb-release namespaces=\"jeb-release\" \(K2)\n")
        t.eq(adoptSigners(&rs, tag: "v1.5.0", src: src), false, "the same release again")
        t.eq(adoptSigners(&rs, tag: "v1.4.9", src: src), false, "an older release")
        t.eq(readFile(pinnedSignersPath), text)
        writeFile(src, "me namespaces=\"git\" \(K2)\n")
        t.eq(adoptSigners(&rs, tag: "v1.6.0", src: src), false, "an unusable file")
        t.eq(rs["signers_from"]?.string, "v1.5.0"); t.eq(readFile(pinnedSignersPath), text)
        writeFile(src, text)
        t.eq(adoptSigners(&rs, tag: "v1.6.0", src: src), true, "already matching still moves signers_from")
        t.eq(rs["signers_from"]?.string, "v1.6.0")
        rs.set("signers_from", .string("not-a-tag"))
        writeFile(src, "jeb-release namespaces=\"jeb-release\" \(K2)\n")
        t.eq(adoptSigners(&rs, tag: "v1.0.0", src: src), true, "a signers_from that is no tag counts as older")
        t.eq(readFile(pinnedSignersPath), "jeb-release namespaces=\"jeb-release\" \(K2)\n")
    }
    t.test("verifyManifest without a pin, and pinHash") {
        unlink(pinnedSignersPath)
        t.eq(pinHash(), "")
        t.eq(verifyManifest(dir + "/m.json", sig: dir + "/m.json.sig", tag: "v1.5.0"), Refusal(reason: "no signers are pinned", kind: "signature"))
        writeFile(pinnedSignersPath, "x")
        t.eq(pinHash(), "2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881")
    }

    t.test("pyRealpath follows a dangling link to where it points, and a loop does not hang") {
        let d = t.scratch("realpath")
        try? FileManager.default.createSymbolicLink(atPath: d + "/abs", withDestinationPath: d + "/gone/desktop/jebctl")
        t.eq(pyRealpath(d + "/abs"), pyRealpath(d) + "/gone/desktop/jebctl", "an absolute target")
        try? FileManager.default.createDirectory(atPath: d + "/sub", withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(atPath: d + "/sub/rel", withDestinationPath: "../moved/x")
        t.eq(pyRealpath(d + "/sub/rel"), pyRealpath(d) + "/moved/x", "a relative target is read from the link's folder")
        try? FileManager.default.createSymbolicLink(atPath: d + "/via", withDestinationPath: d + "/abs")
        t.eq(pyRealpath(d + "/via"), pyRealpath(d) + "/gone/desktop/jebctl", "a chain of links")
        try? FileManager.default.createSymbolicLink(atPath: d + "/a", withDestinationPath: d + "/b")
        try? FileManager.default.createSymbolicLink(atPath: d + "/b", withDestinationPath: d + "/a")
        t.check(pyRealpath(d + "/a").hasPrefix(pyRealpath(d)), "a loop returns")
    }
    t.test("pinCanVerify: only a pinned key that the shipped file lists for jeb-release can check new releases") {
        let cur = "jeb-release namespaces=\"git,jeb-release\" \(K)", backup = "jeb-release-backup namespaces=\"git,jeb-release\" \(K2)"
        let shipped = [cur, backup]
        t.check(!pinCanVerify(pinLines: ["me namespaces=\"git\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOldOldOldOldOldOldOldOldOldOldOldOldOldOldOld"], shippedLines: shipped), "an old key for git only")
        t.check(!pinCanVerify(pinLines: ["me namespaces=\"git,jeb-release\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOldOldOldOldOldOldOldOldOldOldOldOldOldOldOld"], shippedLines: shipped), "an old key, even with jeb-release")
        t.check(pinCanVerify(pinLines: [cur], shippedLines: shipped), "the current jeb-release key")
        t.check(pinCanVerify(pinLines: [backup], shippedLines: shipped), "only the backup key")
        t.check(!pinCanVerify(pinLines: ["me namespaces=\"git\" \(K)"], shippedLines: shipped), "the right key but not for jeb-release")
        t.check(!pinCanVerify(pinLines: [cur], shippedLines: []), "nothing shipped")
        t.check(!pinCanVerify(pinLines: [], shippedLines: shipped), "nothing pinned")
    }
}
