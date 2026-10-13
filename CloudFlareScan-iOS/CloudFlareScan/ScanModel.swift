import Combine
import Foundation

struct ScanResult: Identifiable {
    let ip: String
    let port: UInt16
    let delay: Int
    let colo: String
    var speed: Double?

    var id: String { "\(ip):\(port)" }
}

@MainActor
final class ScanModel: ObservableObject {
    @Published var port: UInt16 = 443
    @Published var concurrency = 50
    @Published var delayLimit = 220
    @Published var speedCount = 10
    @Published var regionCode = ""
    @Published private(set) var results: [ScanResult] = []
    @Published private(set) var speedResults: [ScanResult] = []
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var status = "就绪"
    @Published private(set) var running = false
    @Published private(set) var stage = ""
    @Published var errorMessage: String?

    let coloNames = IPRanges.coloNames()
    private let probe = NetworkProbe()
    private var job: Task<Void, Never>?
    private var runID = UUID()
    private var speedTestType = "完全测速"

    func scan(_ family: IPFamily) {
        stop()
        results = []
        speedResults = []
        completed = 0
        total = 0
        running = true
        stage = "扫描"
        status = "正在生成 \(family.rawValue) 地址"
        let selectedPort = port
        let limit = min(2_000, max(1, delayLimit))
        let batchSize = min(100, max(1, concurrency))
        let currentRun = runID
        job = Task {
            do {
                let ranges = try IPRanges.load(family)
                let addresses = IPRanges.generate(from: ranges, family: family)
                total = addresses.count
                guard total > 0 else { throw ScanError.missingResource(family.rawValue.lowercased()) }
                status = "正在测试 \(total) 个地址"
                for offset in stride(from: 0, to: addresses.count, by: batchSize) {
                    try Task.checkCancellation()
                    guard runID == currentRun else { return }
                    let batch = Array(addresses[offset..<min(offset + batchSize, addresses.count)])
                    var batchResults: [ScanResult] = []
                    await withTaskGroup(of: ScanResult?.self) { group in
                        for ip in batch {
                            group.addTask { [probe] in
                                do {
                                    let delay = try await probe.tcpDelay(ip: ip, port: selectedPort)
                                    guard delay <= limit else { return nil }
                                    let colo = try await probe.colo(ip: ip, port: selectedPort)
                                    return ScanResult(ip: ip, port: selectedPort, delay: delay, colo: colo)
                                } catch { return nil }
                            }
                        }
                        for await found in group {
                            guard runID == currentRun else { continue }
                            if let found { batchResults.append(found) }
                        }
                    }
                    guard runID == currentRun else { return }
                    results.append(contentsOf: batchResults)
                    completed += batch.count
                }
                guard runID == currentRun else { return }
                results.sort { $0.delay < $1.delay }
                status = "\(family.rawValue) 扫描完成 · \(results.count) 个已验证地址"
            } catch is CancellationError {
                status = "已停止"
            } catch {
                status = "扫描失败"
                errorMessage = error.localizedDescription
            }
            guard runID == currentRun else { return }
            running = false
            stage = ""
            job = nil
        }
    }

    func testSpeed(regionOnly: Bool) {
        guard !running else { return }
        let code = regionCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if regionOnly && code.isEmpty {
            errorMessage = "请先输入地区码"
            return
        }
        let candidates = results
            .filter { !regionOnly || $0.colo.uppercased() == code }
            .sorted { $0.delay < $1.delay }
            .prefix(min(50, max(1, speedCount)))
        guard !candidates.isEmpty else {
            errorMessage = regionOnly ? "该地区没有可用地址" : "请先完成扫描"
            return
        }
        speedResults = []
        speedTestType = regionOnly ? "地区测速" : "完全测速"
        completed = 0
        total = candidates.count
        running = true
        stage = "测速"
        status = "正在测速 · 每个地址下载最多 50 MB"
        let currentRun = runID
        job = Task {
            for candidate in candidates {
                if Task.isCancelled || runID != currentRun { break }
                do {
                    var result = candidate
                    result.speed = try await probe.downloadSpeed(ip: candidate.ip, port: candidate.port)
                    guard runID == currentRun else { return }
                    speedResults.append(result)
                    speedResults.sort { ($0.speed ?? 0) > ($1.speed ?? 0) }
                } catch is CancellationError {
                    break
                } catch {
                    // A failed download is excluded from the ranked results.
                }
                guard runID == currentRun else { return }
                completed += 1
                if completed < total {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                }
            }
            guard runID == currentRun else { return }
            status = Task.isCancelled ? "已停止" : "测速完成 · \(speedResults.count) 个有效结果"
            running = false
            stage = ""
            job = nil
        }
    }

    func stop() {
        runID = UUID()
        job?.cancel()
        job = nil
        if running {
            running = false
            stage = ""
            status = "已停止"
            completed = 0
            total = 0
        }
    }

    func exportCSV() throws -> URL {
        guard !speedResults.isEmpty else { throw ScanError.invalidResponse }
        var rows = ["排名,IP地址,地区,延迟(ms),下载速度(MB/s),端口,测速类型"]
        for (index, item) in speedResults.enumerated() {
            let region = coloNames[item.colo] ?? item.colo
            rows.append("\(index + 1),\(item.ip),\(escapeCSV(region)),\(item.delay),\(String(format: "%.2f", item.speed ?? 0)),\(item.port),\(speedTestType)")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CFScanner_\(Int(Date().timeIntervalSince1970)).csv")
        try (rows.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
