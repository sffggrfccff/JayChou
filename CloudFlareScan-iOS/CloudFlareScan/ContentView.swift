import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = ScanModel()
    @State private var selectedTab = 0
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("扫描设置") {
                    Picker("端口", selection: $model.port) {
                        ForEach([443, 2053, 2083, 2087, 2096, 8443], id: \.self) { port in
                            Text("\(port)").tag(UInt16(port))
                        }
                    }
                    Stepper("并发 \(model.concurrency)", value: $model.concurrency, in: 1...100)
                    Stepper("延迟上限 \(model.delayLimit) ms", value: $model.delayLimit, in: 1...2000, step: 10)
                    Stepper("测速数量 \(model.speedCount)", value: $model.speedCount, in: 1...50)
                }

                Section("任务") {
                    HStack {
                        Button("IPv4 扫描") { selectedTab = 0; model.scan(.ipv4) }
                            .disabled(model.running)
                        Spacer()
                        Button("IPv6 扫描") { selectedTab = 0; model.scan(.ipv6) }
                            .disabled(model.running)
                        Spacer()
                        Button("停止", role: .destructive) { model.stop() }
                            .disabled(!model.running)
                    }
                    TextField("地区码，例如 HKG", text: $model.regionCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    HStack {
                        Button("地区测速") { selectedTab = 1; model.testSpeed(regionOnly: true) }
                            .disabled(model.running || model.results.isEmpty)
                        Spacer()
                        Button("完全测速") { selectedTab = 1; model.testSpeed(regionOnly: false) }
                            .disabled(model.running || model.results.isEmpty)
                    }
                }

                Section {
                    HStack {
                        Text(model.status)
                        Spacer()
                        if model.running { ProgressView() }
                    }
                    if model.total > 0 {
                        ProgressView(value: Double(model.completed), total: Double(model.total))
                        Text("\(model.completed) / \(model.total) · \(model.stage)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("结果", selection: $selectedTab) {
                        Text("扫描结果").tag(0)
                        Text("测速结果").tag(1)
                    }
                    .pickerStyle(.segmented)
                    if selectedTab == 0 {
                        ForEach(model.results) { item in
                            resultRow(item, showSpeed: false)
                        }
                    } else {
                        ForEach(model.speedResults) { item in
                            resultRow(item, showSpeed: true)
                        }
                    }
                    if (selectedTab == 0 ? model.results.isEmpty : model.speedResults.isEmpty) {
                        Text("暂无结果").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("结果")
                } footer: {
                    if selectedTab == 1 {
                        Text("速度单位：MB/s。测速会消耗移动数据，每个地址最多 50 MB。")
                    }
                }
            }
            .navigationTitle("CloudFlare Scan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { prepareExport() } label: {
                        Label("导出 CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.speedResults.isEmpty)
                }
            }
            .onChange(of: model.speedResults.count) { _ in exportURL = nil }
            .sheet(isPresented: Binding(
                get: { exportURL != nil },
                set: { if !$0 { exportURL = nil } }
            )) {
                if let exportURL { ShareSheet(url: exportURL) }
            }
            .alert("提示", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private func resultRow(_ item: ScanResult, showSpeed: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.ip).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    .lineLimit(2).minimumScaleFactor(0.8)
                HStack(spacing: 10) {
                    Text(model.coloNames[item.colo] ?? item.colo)
                    Text("\(item.delay) ms")
                    if showSpeed, let speed = item.speed {
                        Text(String(format: "%.2f MB/s", speed))
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                UIPasteboard.general.string = item.ip
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("复制 IP")
        }
    }

    private func prepareExport() {
        do { exportURL = try model.exportCSV() }
        catch { model.errorMessage = error.localizedDescription }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
