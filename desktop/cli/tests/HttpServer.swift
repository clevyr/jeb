// A one-connection-at-a-time HTTP/1.0 server on 127.0.0.1 for the Fetch tests: each route answers a fixed status,
// headers and body (a redirect, a 404, a body without Content-Length), so the real URLSession path is exercised, not
// only the file:// read. Plain BSD sockets on a Thread; nothing here is shipped.
import Foundation

final class HttpServer {
    struct Route { var status: Int; var headers: [(String, String)]; var body: Data }
    var routes: [String: Route] = [:]
    private(set) var port: UInt16 = 0
    private var fd: Int32 = -1

    var base: String { "http://127.0.0.1:\(port)" }

    func start() throws {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(fd, 16) == 0 else { throw PosixError(op: "bind", path: "127.0.0.1", code: errno) }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        port = UInt16(bigEndian: addr.sin_port)
        let t = Thread { [self] in self.loop() }
        t.start()
    }

    func stop() { if fd >= 0 { close(fd); fd = -1 } }

    private func loop() {
        while true {
            let c = accept(fd, nil, nil)
            if c < 0 { return }
            serve(c)
            close(c)
        }
    }

    private func serve(_ c: Int32) {
        var req = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while !req.contains(0x0a) || String(decoding: req, as: UTF8.self).range(of: "\r\n\r\n") == nil {
            let n = read(c, &buf, buf.count)
            if n <= 0 { break }
            req.append(buf, count: n)
            if req.count > 1 << 16 { break }
        }
        let line = String(decoding: req, as: UTF8.self).split(separator: "\r\n", maxSplits: 1).first ?? ""
        let path = line.split(separator: " ").count > 1 ? String(line.split(separator: " ")[1]) : "/"
        let r = routes[path] ?? Route(status: 404, headers: [("Content-Length", "9")], body: Data("not found".utf8))
        let reason = r.status == 200 ? "OK" : r.status == 302 ? "Found" : r.status == 404 ? "Not Found" : "Status"
        var head = "HTTP/1.0 \(r.status) \(reason)\r\n"
        for (k, v) in r.headers { head += "\(k): \(v)\r\n" }
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(r.body)
        _ = out.withUnsafeBytes { p -> Int in
            var off = 0
            while off < p.count {
                let n = write(c, p.baseAddress! + off, p.count - off)
                if n <= 0 { break }
                off += n
            }
            return off
        }
    }

    func text(_ path: String, _ body: String, contentLength: Bool = true) {
        let d = Data(body.utf8)
        routes[path] = Route(status: 200, headers: contentLength ? [("Content-Length", String(d.count))] : [], body: d)
    }

    func redirect(_ path: String, to location: String) {
        routes[path] = Route(status: 302, headers: [("Location", location), ("Content-Length", "0")], body: Data())
    }
}
