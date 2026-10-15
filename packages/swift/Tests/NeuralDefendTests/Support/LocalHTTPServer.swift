import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

/// A request received by ``LocalHTTPServer``.
struct RecordedRequest: Sendable {
    let method: String
    let target: String
    let headers: [String: String]
    /// Complete body when it is at most `LocalHTTPServer.recordLimit` bytes, otherwise empty.
    let body: Data
    let bodyLength: Int

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    var path: String { String(target.split(separator: "?", maxSplits: 1).first ?? "") }

    var query: [String: String] {
        guard let components = URLComponents(string: target) else { return [:] }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] { values[item.name] = item.value ?? "" }
        return values
    }

    var bodyText: String { String(decoding: body, as: UTF8.self) }
}

/// How ``LocalHTTPServer`` answers one request.
enum ServerReply: Sendable {
    case respond(status: Int, headers: [String: String], body: Data)
    /// Reads the request, then never answers until the server stops.
    case hang
}

/// A blocking, thread-per-connection HTTP/1.1 server bound to 127.0.0.1 on a random port.
/// Every response closes its connection.
final class LocalHTTPServer: @unchecked Sendable {
    static let recordLimit = 4 << 20

    typealias Handler = @Sendable (_ call: Int, _ request: RecordedRequest) -> ServerReply

    let port: UInt16
    private let listener: Int32
    private let handler: Handler
    private let lock = NSLock()
    private var recorded: [RecordedRequest] = []
    private var stopped = false
    private let done = DispatchSemaphore(value: 0)

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    var requests: [RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    init(handler: @escaping Handler) throws {
        self.handler = handler
        let fd = socket(AF_INET, Int32(socketStream), 0)
        guard fd >= 0 else { throw ServerError.socket("socket") }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        #if canImport(Darwin)
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 64) == 0 else {
            close(fd)
            throw ServerError.socket("bind/listen")
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        self.listener = fd
        self.port = UInt16(bigEndian: actual.sin_port)
        let thread = Thread { [self] in acceptLoop() }
        thread.start()
    }

    /// Returns a port on which nothing is listening.
    static func closedPort() throws -> UInt16 {
        let server = try LocalHTTPServer { _, _ in .hang }
        let port = server.port
        server.stop()
        return port
    }

    func stop() {
        lock.lock()
        let wasStopped = stopped
        stopped = true
        lock.unlock()
        if !wasStopped { done.wait() }
    }

    deinit {
        stop()
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func acceptLoop() {
        while !isStopped {
            var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 50) > 0 else { continue }
            let client = accept(listener, nil, nil)
            guard client >= 0 else { continue }
            #if canImport(Darwin)
                var noSigPipe: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            #endif
            let thread = Thread { [self] in serve(client) }
            thread.start()
        }
        close(listener)
        done.signal()
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        let connection = Connection(fd: fd, isStopped: { [weak self] in self?.isStopped ?? true })
        guard let request = connection.readRequest(recordLimit: Self.recordLimit) else { return }
        lock.lock()
        recorded.append(request)
        let call = recorded.count
        lock.unlock()
        switch handler(call, request) {
        case .hang:
            while !isStopped { usleep(20_000) }
        case .respond(let status, let headers, let body):
            var head = "HTTP/1.1 \(status) \(reasonPhrase(status))\r\n"
            var allHeaders = headers
            allHeaders["Content-Length"] = String(body.count)
            allHeaders["Connection"] = "close"
            for (name, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
                head += "\(name): \(value)\r\n"
            }
            head += "\r\n"
            connection.write(Data(head.utf8) + body)
        }
    }

    enum ServerError: Error {
        case socket(String)
    }
}

#if canImport(Glibc) || canImport(Musl)
    private let socketStream = SOCK_STREAM.rawValue
    private let sendFlags = Int32(MSG_NOSIGNAL)
#else
    private let socketStream = SOCK_STREAM
    private let sendFlags: Int32 = 0
#endif

private func reasonPhrase(_ status: Int) -> String {
    switch status {
    case 100: return "Continue"
    case 200: return "OK"
    case 302: return "Found"
    case 400: return "Bad Request"
    case 401: return "Unauthorized"
    case 403: return "Forbidden"
    case 429: return "Too Many Requests"
    case 500: return "Internal Server Error"
    case 503: return "Service Unavailable"
    default: return "Status"
    }
}

/// Buffered reads and writes on one accepted socket.
private final class Connection {
    let fd: Int32
    let isStopped: () -> Bool
    private var buffer = Data()

    init(fd: Int32, isStopped: @escaping () -> Bool) {
        self.fd = fd
        self.isStopped = isStopped
    }

    func write(_ data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let sent = send(fd, base + offset, raw.count - offset, sendFlags)
                if sent <= 0 { return }
                offset += sent
            }
        }
    }

    /// Reads more bytes into the buffer. Returns `false` at end of stream or on shutdown.
    private func fill() -> Bool {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while !isStopped() {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 50)
            if ready < 0 { return false }
            if ready == 0 { continue }
            let count = recv(fd, &chunk, chunk.count, 0)
            if count <= 0 { return false }
            buffer.append(contentsOf: chunk[0..<count])
            return true
        }
        return false
    }

    private func readLine() -> String? {
        let separator = Data("\r\n".utf8)
        while true {
            if let range = buffer.range(of: separator) {
                let line = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return line
            }
            if !fill() { return nil }
        }
    }

    /// Consumes exactly `count` bytes, keeping at most `limit` of them.
    private func readBody(_ count: Int, limit: Int, into body: inout Data) -> Bool {
        var remaining = count
        while remaining > 0 {
            if buffer.isEmpty && !fill() { return false }
            let take = min(remaining, buffer.count)
            if body.count < limit {
                body.append(buffer.prefix(min(take, limit - body.count)))
            }
            buffer.removeFirst(take)
            remaining -= take
        }
        return true
    }

    func readRequest(recordLimit: Int) -> RecordedRequest? {
        guard let requestLine = readLine() else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        while let line = readLine(), !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        if headers["expect"]?.lowercased() == "100-continue" {
            write(Data("HTTP/1.1 100 Continue\r\n\r\n".utf8))
        }
        var body = Data()
        var length = 0
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            while let sizeLine = readLine() {
                let size = Int(sizeLine.split(separator: ";").first ?? "", radix: 16) ?? 0
                if size == 0 {
                    while let trailer = readLine(), !trailer.isEmpty {}
                    break
                }
                guard readBody(size, limit: recordLimit, into: &body) else { return nil }
                length += size
                _ = readLine()
            }
        } else if let declared = headers["content-length"].flatMap({ Int($0) }) {
            guard readBody(declared, limit: recordLimit, into: &body) else { return nil }
            length = declared
        }
        if length > recordLimit { body = Data() }
        return RecordedRequest(
            method: String(parts[0]),
            target: String(parts[1]),
            headers: headers,
            body: body,
            bodyLength: length
        )
    }
}
