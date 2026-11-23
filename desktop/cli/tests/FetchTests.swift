// Fetch: the release tree as a file:// base (the goldens' layout), then the same functions against a local HTTP server
// for what a file cannot do: a redirect, a 404 and a body with no Content-Length.
import Foundation

func fetchTests(_ t: Tester) {
    let rel = t.scratch("fetch") + "/rel"
    writeFile(rel + "/latest", "v1.6.0")
    writeFile(rel + "/tag/v1.6.0", "page")
    writeFile(rel + ".atom", #"<feed><entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.6.0"/></entry><entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.5.0"/></entry><entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.4.0"/></entry><entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.6.0"/></entry><entry><link href="https://github.com/clevyr/jeb/releases/tag/v1.2"/></entry></feed>"#)
    let base = "file://" + rel
    let dl = t.scratch("fetch-dl") + "/dl"

    t.test("release base and tag helpers") {
        setEnvVar("JEB_RELEASE_BASE", nil)
        t.eq(releaseBase("x/y"), "https://github.com/x/y/releases")
        setEnvVar("JEB_RELEASE_BASE", base + "/")
        t.eq(releaseBase("x/y"), base)
        setEnvVar("JEB_RELEASE_BASE", "")
        t.eq(releaseBase("x/y"), "https://github.com/x/y/releases")
        for (tag, ok) in [("v1.2.0", true), ("v0.0.0", true), ("v1.2", false), ("v01.2.3", false), ("v1.2.0-rc1", false), ("1.2.0", false)] { t.eq(isReleaseTag(tag), ok, tag) }
        t.eq(urlName("https://h/a/b/"), "b"); t.eq(urlHost("https://h/a"), "h"); t.eq(urlHost("file:///x"), "")
        t.eq(filePath(ofUrl: "file:///a%20b/c"), "/a b/c"); t.eq(filePath(ofUrl: "file://localhost/a"), "/a"); t.eq(filePath(ofUrl: "https://x/"), nil)
    }
    t.test("file:// latest_tag from a bare body, feed_tags deduped and filtered") {
        t.eq(try latestTag(base), "v1.6.0")
        t.eq(feedTags(base), ["v1.6.0", "v1.5.0", "v1.4.0"])
        t.eq(feedTags(base + "-none"), [])
        writeFile(rel + "/latest", "not a tag")
        t.eq((try? latestTag(base)) == nil, true)
        writeFile(rel + "/latest", "v1.6.0")
    }
    t.test("file:// fetch: body, missing names the path (deviation #1), TooBig by size") {
        t.eq(String(decoding: try fetch(base + "/latest", limit: 100), as: UTF8.self), "v1.6.0")
        do { _ = try fetch(base + "/nope", limit: 10); t.fail("no error") } catch let e as FetchError {
            t.eq(e.message, "could not read \(rel)/nope (No such file or directory)"); t.eq(e.status, nil); t.eq(e.tooBig, false)
        }
        do { _ = try fetch(base + "/latest", limit: 2); t.fail("no error") } catch let e as FetchError {
            t.eq(e.message, "latest is larger than 2 bytes"); t.eq(e.tooBig, true)
        }
    }
    t.test("file:// save: .part at 0600 renamed over dest; nothing survives a failure") {
        t.eq(try save(base + "/latest", to: dl, limit: 100), "file://" + rel + "/latest")
        t.eq(readFile(dl), "v1.6.0"); t.eq(fileMode(dl), "0o600")
        t.check(!lexists(dl + ".part"), ".part left behind")
        for (url, limit, msg) in [(base + "/latest", 2, "latest is larger than 2 bytes"), (base + "/nope", 10, "could not read \(rel)/nope (No such file or directory)")] {
            do { try save(url, to: dl + "2", limit: limit); t.fail("no error for \(url)") } catch let e as FetchError { t.eq(e.message, msg) }
            t.check(!lexists(dl + "2.part") && !lexists(dl + "2"), "files left behind for \(url)")
        }
    }

    let srv = HttpServer()
    do { try srv.start() } catch { t.test("http server") { throw error }; return }
    defer { srv.stop() }
    srv.redirect("/latest", to: srv.base + "/tag/v1.6.0")
    srv.text("/tag/v1.6.0", "<html>release page</html>")
    srv.text("/rel.atom", #"<a href="/releases/tag/v1.5.0"></a><a href="/releases/tag/v1.5.0"></a>"#)
    srv.text("/big", String(repeating: "x", count: 5000), contentLength: false)
    srv.text("/sized", String(repeating: "y", count: 50))
    srv.text("/empty", "")

    t.test("http latest_tag follows the redirect to /tag/<tag>") {
        t.eq(try latestTag(srv.base), "v1.6.0")
        t.eq(feedTags(srv.base + "/rel"), ["v1.5.0"])
    }
    t.test("http 404: '<name> not found (HTTP 404)' with status 404; latest_tag reworded") {
        do { _ = try fetch(srv.base + "/nope"); t.fail("no error") } catch let e as FetchError { t.eq(e.message, "nope not found (HTTP 404)"); t.eq(e.status, 404) }
        do { _ = try latestTag(srv.base + "/none"); t.fail("no error") } catch let e as FetchError {
            t.eq(e.message, "no published release at \(srv.base)/none (HTTP 404; is the repository public?)"); t.eq(e.status, 404)
        }
    }
    t.test("http TooBig: by Content-Length, and mid-stream without one; no .part survives") {
        do { _ = try fetch(srv.base + "/sized", limit: 10); t.fail("no error") } catch let e as FetchError { t.eq(e.message, "sized is larger than 10 bytes"); t.eq(e.tooBig, true) }
        do { _ = try fetch(srv.base + "/big", limit: 100); t.fail("no error") } catch let e as FetchError { t.eq(e.message, "big is larger than 100 bytes"); t.eq(e.tooBig, true) }
        let d = dl + "-http"
        do { try save(srv.base + "/big", to: d, limit: 100); t.fail("no error") } catch let e as FetchError { t.eq(e.message, "\(urlName(d)) is larger than 100 bytes"); t.eq(e.tooBig, true) }
        t.check(!lexists(d + ".part") && !lexists(d), "files left behind")
        t.eq(try save(srv.base + "/sized", to: d, limit: 50), srv.base + "/sized")
        t.eq(readFile(d)?.count, 50)
        t.eq(try fetch(srv.base + "/empty").count, 0)
    }
    t.test("http: a closed port is 'could not reach <host> (...)' with no status") {
        let port = srv.port; srv.stop()
        do { _ = try fetch("http://127.0.0.1:\(port)/x", timeout: 5, total: 5); t.fail("no error") } catch let e as FetchError {
            t.check(e.message.hasPrefix("could not reach 127.0.0.1:\(port) ("), e.message); t.eq(e.status, nil)
        }
    }
}
