import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = ScanModel()
    @State private var selectedTab = 0
    @State private var exportURL: URL?

    private let background = Color(red: 0.045, green: 0.075, blue: 0.12)
    private let surface = Color(red: 0.085, green: 0.13, blue: 0.19)
    private let accent = Color(red: 0.38, green: 0.87, blue: 0.81)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    statusCard
                    settingsCard
                    actionsCard
                    resultsSection
                }
                .padding(16)
            }
            .background(background.ignoresSafeArea())
            .navigationTitle("CloudFlare Scan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { prepareExport() } label: {
                        Label("导出 CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.speedResults.isEmpty)
                }
            }
            .tint(accent)
            .preferredColorScheme(.dark)
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

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: model.running ? "waveform.path" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
                Text(model.running ? "任务进行中" : "扫描控制台")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(accent)
                Spacer()
                if model.running { ProgressView().tint(accent) }
            }
            Text(model.status)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            if model.total > 0 {
                ProgressView(value: Double(model.completed), total: Double(model.total))
                    .tint(accent)
                HStack {
                    Text("\(model.completed.formatted()) / \(model.total.formatted())")
                        .monospacedDigit()
                    Spacer()
                    Text(model.stage.isEmpty ? "已完成" : model.stage)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("扫描参数", icon: "slider.horizontal.3")
            Picker("TLS 端口", selection: $model.port) {
                ForEach([443, 2053, 2083, 2087, 2096, 8443], id: \.self) { port in
                    Text("\(port)").tag(UInt16(port))
                }
            }
            Divider()
            Stepper("并发连接  \(model.concurrency)", value: $model.concurrency, in: 1...100)
            Stepper("延迟上限  \(model.delayLimit) ms", value: $model.delayLimit, in: 1...2000, step: 10)
            Stepper("测速数量  \(model.speedCount)", value: $model.speedCount, in: 1...50)
        }
        .padding(20)
        .background(surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("开始扫描", icon: "antenna.radiowaves.left.and.right")
            HStack(spacing: 10) {
                Button { selectedTab = 0; model.scan(.ipv4) } label: {
                    Label("IPv4 扫描", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.running)
                Button { selectedTab = 0; model.scan(.ipv6) } label: {
                    Text("IPv6 扫描").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.running)
            }
            if model.running {
                Button(role: .destructive) { model.stop() } label: {
                    Label("停止当前任务", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Divider()
            TextField("地区码，例如 HKG", text: $model.regionCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                Button("地区测速") { selectedTab = 1; model.testSpeed(regionOnly: true) }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .disabled(model.running || model.results.isEmpty)
                Button("完全测速") { selectedTab = 1; model.testSpeed(regionOnly: false) }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .disabled(model.running || model.results.isEmpty)
            }
            Text("测速每个地址最多下载 50 MB，请留意移动数据用量。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("结果", icon: "list.bullet.rectangle")
                Spacer()
                Text("\(selectedTab == 0 ? model.results.count : model.speedResults.count) 条")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(accent)
            }
            Picker("结果", selection: $selectedTab) {
                Text("扫描结果").tag(0)
                Text("测速结果").tag(1)
            }
            .pickerStyle(.segmented)
            if selectedTab == 0 {
                if model.results.isEmpty { emptyResults }
                ForEach(model.results) { item in resultRow(item, showSpeed: false) }
            } else {
                if model.speedResults.isEmpty { emptyResults }
                ForEach(model.speedResults) { item in resultRow(item, showSpeed: true) }
            }
        }
        .padding(.bottom, 24)
    }

    private var emptyResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "network.slash").font(.largeTitle).foregroundStyle(accent)
            Text("暂无结果").font(.headline)
            Text(selectedTab == 0 ? "开始扫描后，已验证的地址会显示在这里" : "先扫描地址，再运行地区或完全测速")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.white)
    }

    private func resultRow(_ item: ScanResult, showSpeed: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.ip)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(model.coloNames[item.colo] ?? item.colo)
                    Text(item.colo).foregroundStyle(accent)
                    Text("\(item.delay) ms")
                    if showSpeed, let speed = item.speed {
                        Text(String(format: "%.2f MB/s", speed)).foregroundStyle(accent)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Button { UIPasteboard.general.string = item.ip } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 36, height: 40)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("复制 IP \(item.ip)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 16))
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
