// Fetch: releases over plain HTTPS, no API or sign-in (desktop/jebhome.py's release_base, fetch, latest_tag, feed_tags).
// GET with redirects followed but never downgraded from https, bodies refused past a cap (a bundle: its signed size),
// streamed downloads through dest.part. A file:// base (the tests' release tree laid out like GitHub) is read straight
// from disk: its errors name the path, where the Python named an empty host (deviation #1 in the goldens README).
import Foundation

/// A download that failed, in plain words. status: the HTTP code (404: no such release or asset), nil for the network.
/// tooBig: more bytes than the cap (for a bundle: than its signed size): the asset is wrong, not the network.
struct FetchError: Error, CustomStringConvertible {
    let message: String
    let status: Int?
    let tooBig: Bool
    init(_ message: String, status: Int? = nil, tooBig: Bool = false) {
        self.message = message; self.status = status; self.tooBig = tooBig
    }
    static func big(_ message: String) -> FetchError { FetchError(message, tooBig: true) }
    var description: String { message }
}

/// Where releases are read: https://github.com/<repo>/releases, or $JEB_RELEASE_BASE (tests: a server laid out like GitHub).
func releaseBase(_ repo: String) -> String {
    var b = envVar("JEB_RELEASE_BASE").flatMap { $0.isEmpty ? nil : $0 } ?? "https://github.com/\(repo)/releases"
    while b.hasSuffix("/") { b.removeLast() }
    return b
}

/// SemVer release tags only (v1.2.0, not v1.2, v01.2.3 or v1.2.0-rc1); pre-release tags are never followed.
func isReleaseTag(_ t: String) -> Bool {
    reMatch(#"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$"#, t) != nil
}

/// The last path component of a URL, the Python's url.rstrip('/').rsplit('/', 1)[-1].
func urlName(_ url: String) -> String {
    var u = url
    while u.hasSuffix("/") { u.removeLast() }
    return u.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? u
}

/// url.split('/')[2]: the host, or "" for a URL without one.
func urlHost(_ url: String) -> String {
    let parts = url.split(separator: "/", omittingEmptySubsequences: false)
    return parts.count > 2 ? String(parts[2]) : ""
}

/// The local path of a file:// URL (the host part, if any, is dropped; percent escapes decoded); nil for other schemes.
func filePath(ofUrl url: String) -> String? {
    guard url.hasPrefix("file://") else { return nil }
    var rest = String(url.dropFirst(7))
    if !rest.hasPrefix("/") { rest = rest.firstIndex(of: "/").map { String(rest[$0...]) } ?? "/" }
    return rest.removingPercentEncoding ?? rest
}

struct FetchResponse {
    let url: URL            // the final URL after redirects
    let length: Int64?      // Content-Length when the server sent one
}

/// The streaming side of one GET: the response first (redirects followed), then every chunk to sink until it returns
/// false, which ends the transfer early and is not an error. Callback errors are rethrown; the Python's _open errors
/// become FetchError (404 named by the asset, other codes by the host, the network by its reason).
private final class Stream: NSObject, URLSessionDataDelegate {
    let onResponse: (FetchResponse) throws -> Void
    let sink: (Data) throws -> Bool
    var failure: Error?
    var status = 0
    var gotResponse = false, stopped = false
    let done = DispatchSemaphore(value: 0)

    init(onResponse: @escaping (FetchResponse) throws -> Void, sink: @escaping (Data) throws -> Bool) {
        self.onResponse = onResponse; self.sink = sink
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest q: URLRequest, completionHandler done: @escaping (URLRequest?) -> Void) {
        // a refused redirect delivers the 3xx itself, which the status check below turns into "HTTP 3xx from <host>"
        done(task.currentRequest?.url?.scheme == "https" && q.url?.scheme != "https" ? nil : q)
    }

    func urlSession(_ s: URLSession, dataTask t: URLSessionDataTask, didReceive r: URLResponse, completionHandler done: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (r as? HTTPURLResponse)?.statusCode ?? 200
        gotResponse = true
        guard status < 300, let u = r.url else { done(.cancel); return }
        do {
            try onResponse(FetchResponse(url: u, length: r.expectedContentLength >= 0 ? r.expectedContentLength : nil))
            done(.allow)
        } catch { failure = error; done(.cancel) }
    }

    func urlSession(_ s: URLSession, dataTask t: URLSessionDataTask, didReceive d: Data) {
        do { if try !sink(d) { stopped = true; t.cancel() } } catch { failure = error; t.cancel() }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) {
        if failure == nil, !stopped, status < 300, let e = e { failure = e }
        done.signal()
    }
}

/// GET url: redirects followed (https never downgraded), the response to onResponse, the body in chunks to sink until
/// it returns false. timeout: per read; total: the whole transfer. A file:// URL is read from disk the same way.
func fetchStream(_ url: String, timeout: Double = 60, total: Double = 900, onResponse: @escaping (FetchResponse) throws -> Void = { _ in }, sink: @escaping (Data) throws -> Bool) throws {
    if let path = filePath(ofUrl: url) {
        try fileStream(path, onResponse: onResponse, sink: sink)
        return
    }
    guard let u = URL(string: url) else { throw FetchError("could not reach \(urlHost(url)) (bad URL)") }
    let st = Stream(onResponse: onResponse, sink: sink)
    let c = URLSessionConfiguration.ephemeral
    c.timeoutIntervalForRequest = timeout
    c.timeoutIntervalForResource = total
    c.httpAdditionalHeaders = ["User-Agent": "jebctl"]
    let s = URLSession(configuration: c, delegate: st, delegateQueue: nil)
    s.dataTask(with: u).resume()
    st.done.wait()
    s.finishTasksAndInvalidate()
    let host = urlHost(url)
    if st.status >= 300 {
        throw st.status == 404 ? FetchError("\(urlName(url)) not found (HTTP 404)", status: 404) : FetchError("HTTP \(st.status) from \(host)", status: st.status)
    }
    if let f = st.failure {
        if let fe = f as? FetchError { throw fe }
        throw FetchError("could not \(st.gotResponse ? "read" : "reach") \(host) (\(f.localizedDescription))")
    }
}

private func fileStream(_ path: String, onResponse: (FetchResponse) throws -> Void, sink: (Data) throws -> Bool) throws {
    var st = stat()
    guard stat(path, &st) == 0, let f = FileHandle(forReadingAtPath: path) else {
        throw FetchError("could not read \(path) (\(String(cString: strerror(errno))))")
    }
    defer { f.closeFile() }
    try onResponse(FetchResponse(url: URL(fileURLWithPath: path), length: Int64(st.st_size)))
    while true {
        let d = f.readData(ofLength: 1 << 20)
        if d.isEmpty { return }
        if try !sink(d) { return }
    }
}

/// GET url and return the body. More than limit bytes raises tooBig; so does a longer Content-Length. FetchError otherwise.
func fetch(_ url: String, limit: Int = 1 << 16, timeout: Double = 60, total: Double = 900) throws -> Data {
    var body = Data()
    let big = FetchError.big("\(urlName(url)) is larger than \(limit) bytes")
    try fetchStream(url, timeout: timeout, total: total, onResponse: { r in if let n = r.length, n > limit { throw big } }) { d in
        body.append(d)
        return body.count <= limit
    }
    if body.count > limit { throw big }
    return body
}

/// GET url streamed to dest.part (0600), renamed over dest last; the final URL is returned. More than limit bytes (or a
/// longer Content-Length) raises tooBig; past total seconds the download fails; dest.part never survives a failure.
@discardableResult
func save(_ url: String, to dest: String, limit: Int, timeout: Double = 60, total: Double = 900) throws -> String {
    let part = dest + ".part", name = urlName(dest)
    let end = Clock.monotonic + total
    var fd: Int32 = -1, got = 0, final = url
    defer { if fd >= 0 { close(fd) } }
    do {
        try fetchStream(url, timeout: timeout, total: total, onResponse: { r in
            if let n = r.length, n > limit { throw FetchError.big("\(urlName(url)) is larger than \(limit) bytes") }
            final = r.url.absoluteString
            fd = open(part, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
            guard fd >= 0 else { throw FetchError("could not read \(urlHost(url)) (\(posixError("open", part)))") }
        }) { d in
            got += d.count
            if got > limit { throw FetchError.big("\(name) is larger than \(limit) bytes") }
            if Clock.monotonic > end { throw FetchError("download of \(name) took longer than \(Int(total)) s") }
            let ok = d.withUnsafeBytes { p -> Bool in
                var off = 0
                while off < p.count {
                    let n = write(fd, p.baseAddress! + off, p.count - off)
                    if n <= 0 { return false }
                    off += n
                }
                return true
            }
            guard ok else { throw FetchError("could not read \(urlHost(url)) (\(posixError("write", part)))") }
            return true
        }
        if fd >= 0 { close(fd); fd = -1 }
        guard rename(part, dest) == 0 else { throw FetchError("could not read \(urlHost(url)) (\(posixError("rename", dest)))") }
    } catch {
        if fd >= 0 { close(fd); fd = -1 }
        unlink(part)
        throw error
    }
    return final
}

/// The newest published tag: /latest redirects to /tag/<tag> (the page is not read); a static test server answers the bare tag.
func latestTag(_ base: String, timeout: Double = 60) throws -> String {
    var final: URL?
    var body = Data()
    do {
        try fetchStream(base + "/latest", timeout: timeout, onResponse: { final = $0.url }) { d in
            body.append(d)
            return body.count < 257
        }
    } catch let e as FetchError {
        throw e.status == 404 ? FetchError("no published release at \(base) (HTTP 404; is the repository public?)", status: 404) : e
    }
    if let p = final?.path, let m = reMatch(#"/tag/(v\d+\.\d+\.\d+)$"#, p) { return m[1] }
    let text = String(decoding: body.prefix(257), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    if text.count <= 256 && isReleaseTag(text) { return text }
    throw FetchError("no published release at \(base)")
}

/// The tags in the releases feed (<base>.atom), newest first; [] when it cannot be read.
func feedTags(_ base: String) -> [String] {
    guard let data = try? fetch(base + ".atom", limit: 1 << 20) else { return [] }
    let text = String(decoding: data, as: UTF8.self)
    var seen = Set<String>(), out: [String] = []
    for m in reFindAll(#"/releases/tag/(v\d+\.\d+\.\d+)""#, text) where isReleaseTag(m[1]) && seen.insert(m[1]).inserted {
        out.append(m[1])
    }
    return out
}
