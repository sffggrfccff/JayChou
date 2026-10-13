import Foundation
import Network
import Security

final class NetworkProbe {
    private let queue = DispatchQueue(label: "CloudFlareScan.network", attributes: .concurrent)

    func tcpDelay(ip: String, port: UInt16) async throws -> Int {
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        defer { connection.cancel() }
        let start = ProcessInfo.processInfo.systemUptime
        try await waitUntilReady(connection, timeout: 1.5)
        return max(1, Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
    }

    func colo(ip: String) async -> String {
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: 80, using: .tcp)
        defer { connection.cancel() }
        let deadline = DispatchWorkItem { connection.cancel() }
        queue.asyncAfter(deadline: .now() + 4, execute: deadline)
        defer { deadline.cancel() }
        do {
            try await waitUntilReady(connection, timeout: 2)
            try await send("GET /cdn-cgi/trace HTTP/1.1\r\nHost: speed.cloudflare.com\r\nConnection: close\r\n\r\n", over: connection)
            var response = Data()
            while response.count < 16_384 {
                let chunk = try await receive(on: connection)
                if chunk.isEmpty { break }
                response.append(chunk)
            }
            let text = String(decoding: response, as: UTF8.self)
            guard text.hasPrefix("HTTP/1.1 200") || text.hasPrefix("HTTP/1.0 200") else { return "N/A" }
            guard let line = text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("colo=") }) else {
                return "N/A"
            }
            return String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        } catch {
            return "N/A"
        }
    }

    func downloadSpeed(ip: String, port: UInt16, bytes: Int = 52_428_800) async throws -> Double {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, "speed.cloudflare.com")
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        defer { connection.cancel() }
        try await waitUntilReady(connection, timeout: 5)
        let deadline = DispatchWorkItem { connection.cancel() }
        queue.asyncAfter(deadline: .now() + 45, execute: deadline)
        defer { deadline.cancel() }
        try await send("GET /__down?bytes=\(bytes) HTTP/1.1\r\nHost: speed.cloudflare.com\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n", over: connection)

        let started = ProcessInfo.processInfo.systemUptime
        var headers = Data()
        var bodyBytes = 0
        var headerFinished = false
        let boundary = Data("\r\n\r\n".utf8)
        while bodyBytes < bytes {
            try Task.checkCancellation()
            if ProcessInfo.processInfo.systemUptime - started > 45 { throw ScanError.timedOut }
            let chunk = try await receive(on: connection)
            if chunk.isEmpty { break }
            if !headerFinished {
                headers.append(chunk)
                guard let range = headers.range(of: boundary) else {
                    if headers.count > 64_000 { throw ScanError.invalidResponse }
                    continue
                }
                let head = String(decoding: headers[..<range.lowerBound], as: UTF8.self)
                guard head.hasPrefix("HTTP/1.1 200") || head.hasPrefix("HTTP/1.0 200") else {
                    throw ScanError.invalidResponse
                }
                guard !head.lowercased().contains("transfer-encoding: chunked") else {
                    throw ScanError.invalidResponse
                }
                bodyBytes += headers.count - range.upperBound
                headerFinished = true
                headers.removeAll(keepingCapacity: false)
            } else {
                bodyBytes += chunk.count
            }
        }
        guard headerFinished, bodyBytes >= bytes else { throw ScanError.invalidResponse }
        let seconds = max(0.001, ProcessInfo.processInfo.systemUptime - started)
        return Double(min(bodyBytes, bytes)) / 1_048_576 / seconds
    }

    private func waitUntilReady(_ connection: NWConnection, timeout: TimeInterval) async throws {
        let gate = NSLock()
        var resumed = false
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                func finish(_ result: Result<Void, Error>) {
                    gate.lock()
                    defer { gate.unlock() }
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(with: result)
                }
                let deadline = DispatchWorkItem {
                    finish(.failure(ScanError.timedOut))
                    connection.cancel()
                }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: deadline.cancel(); finish(.success(()))
                    case .failed(let error): deadline.cancel(); finish(.failure(error))
                    case .cancelled: deadline.cancel(); finish(.failure(CancellationError()))
                    default: break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout, execute: deadline)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    private func send(_ text: String, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(text.utf8), completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    private func receive(on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, !data.isEmpty { continuation.resume(returning: data) }
                else if complete { continuation.resume(returning: Data()) }
                else { continuation.resume(throwing: ScanError.disconnected) }
            }
        }
    }
}
