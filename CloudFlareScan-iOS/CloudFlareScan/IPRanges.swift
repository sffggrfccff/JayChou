import Darwin
import Foundation

enum IPFamily: String, CaseIterable {
    case ipv4 = "IPv4"
    case ipv6 = "IPv6"
}

enum IPRanges {
    static func load(_ family: IPFamily) throws -> [String] {
        let name = family == .ipv4 ? "ipv4" : "ipv6"
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else {
            throw ScanError.missingResource(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
    }

    static func coloNames() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "colo", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return text.split(whereSeparator: \.isNewline).reduce(into: [:]) { names, line in
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                names[String(parts[0]).uppercased()] = String(parts[1])
            }
        }
    }

    static func generate(from ranges: [String], family: IPFamily) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for range in ranges {
            let addresses = family == .ipv4 ? ipv4(from: range) : ipv6(from: range)
            for address in addresses where seen.insert(address).inserted {
                result.append(address)
            }
        }
        return result.shuffled()
    }

    private static func ipv4(from cidr: String) -> [String] {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, parts[1] == "24" else { return [] }
        var address = in_addr()
        guard String(parts[0]).withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else { return [] }
        let host = UInt32.random(in: 0...255)
        let value = (UInt32(bigEndian: address.s_addr) & 0xFFFFFF00) | host
        address.s_addr = value.bigEndian
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else { return [] }
        return [String(cString: buffer)]
    }

    private static func ipv6(from cidr: String) -> [String] {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let prefix = Int(parts[1]), (0...48).contains(prefix) else { return [] }
        var address = in6_addr()
        guard String(parts[0]).withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return [] }
        let base = withUnsafeBytes(of: address) { Array($0) }
        return (0..<10).compactMap { _ in
            var bytes = base
            for bit in prefix..<128 {
                let mask = UInt8(1 << (7 - bit % 8))
                if Bool.random() { bytes[bit / 8] |= mask } else { bytes[bit / 8] &= ~mask }
            }
            var generated = in6_addr()
            withUnsafeMutableBytes(of: &generated) { $0.copyBytes(from: bytes) }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &generated, &buffer, socklen_t(buffer.count)) != nil else { return nil }
            return String(cString: buffer)
        }
    }
}

enum ScanError: LocalizedError {
    case missingResource(String)
    case timedOut
    case disconnected
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingResource(let name): return "缺少内置资源：\(name).txt"
        case .timedOut: return "连接超时"
        case .disconnected: return "连接已断开"
        case .invalidResponse: return "测速服务响应无效"
        }
    }
}
