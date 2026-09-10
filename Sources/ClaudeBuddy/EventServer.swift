import Foundation
import Network

/// Minimal HTTP/1.1 listener on 127.0.0.1 that accepts Claude Code `type: "http"` hook POSTs.
/// Every request gets `200 {}` back immediately; the body is handed to `onEvent`.
final class EventServer {
    static let defaultPort: UInt16 = 4789

    private let listener: NWListener
    private let queue = DispatchQueue(label: "claude-buddy.http")
    private let onEvent: (_ path: String, _ body: Data) -> Void

    init(port: UInt16 = EventServer.defaultPort, onEvent: @escaping (_ path: String, _ body: Data) -> Void) throws {
        self.onEvent = onEvent
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.stateUpdateHandler = { state in
            if case .failed(let err) = state { NSLog("ClaudeBuddy: listener failed: \(err)") }
        }
        listener.start(queue: queue)
    }

    private func accept(_ conn: NWConnection) {
        var buffer = Data()
        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
                guard let self else { conn.cancel(); return }
                if let data { buffer.append(data) }
                if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let header = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
                    let length = self.contentLength(in: header)
                    let bodyStart = headerEnd.upperBound
                    if buffer.count - bodyStart >= length {
                        let body = buffer.subdata(in: bodyStart..<(bodyStart + length))
                        let path = header.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                        if header.hasPrefix("POST"), !body.isEmpty { self.onEvent(path, body) }
                        self.respond(conn, ok: true)
                        return
                    }
                }
                if isComplete || error != nil { conn.cancel(); return }
                readMore()
            }
        }
        conn.start(queue: queue)
        readMore()
    }

    private func contentLength(in header: String) -> Int {
        for line in header.split(separator: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                return Int(lower.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private func respond(_ conn: NWConnection, ok: Bool) {
        let body = "{}"
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in conn.cancel() })
    }
}
