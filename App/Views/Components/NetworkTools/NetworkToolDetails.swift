import SwiftUI

struct DNSCleanupToolDetail: View {
    @Bindable var viewModel: NetworkToolsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("清理 DNS 缓存、重置网络接口、清除 ARP 缓存、重置 WiFi、清理浏览器缓存")
                .foregroundStyle(.secondary)
            Label("执行时将中断网络连接 2-5 秒", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text("浏览器清理范围为 Chrome 和 Firefox，并包含系统缓存清理。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.isExecuting {
                ProgressView("执行中...")
                    .controlSize(.small)
            } else {
                Button("执行深度清理") {
                    Task { await viewModel.executeDeepClean() }
                }
                .buttonStyle(.glassProminent)
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            if let lastTime = viewModel.lastExecutionTime {
                Text("上次执行：\(lastTime, style: .date) \(lastTime, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct IPQueryToolInput: View {
    @State private var viewModel = IPQueryViewModel.shared

    private var hasDetails: Bool { viewModel.result != nil || viewModel.errorMessage != nil }

    var body: some View {
        ActionTextField(
            placeholder: "输入 IP 地址",
            text: $viewModel.ipAddress,
            actionTitle: "查询",
            loadingTitle: "查询中...",
            isLoading: viewModel.isLoading,
            isActionDisabled: viewModel.isLoading || viewModel.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClear: viewModel.reset,
            action: {
                Task { await viewModel.queryIP(viewModel.ipAddress) }
            }
        )
        .onChange(of: viewModel.ipAddress) { _, _ in
            if !viewModel.isLoading { viewModel.reset() }
        }
        .padding(.horizontal, DesignSystem.Spacing.standard * 2)
        .padding(.top, 22)
        .padding(.bottom, hasDetails ? DesignSystem.Spacing.standard : 22)
    }
}

struct IPQueryToolDetail: View {
    @State private var viewModel = IPQueryViewModel.shared

    var body: some View {
        if viewModel.result != nil || viewModel.errorMessage != nil {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.standard) {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if let result = viewModel.result {
                    IPQueryResultContent(result: result)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.bottom, 22)
        }
    }
}

struct DNSToolDetail: View {
    static let resultWidth: CGFloat = 620
    @State private var viewModel = DNSTestViewModel.shared

    var body: some View {
        Group {
            if viewModel.state == .testing {
                VStack(spacing: 4) {
                    Text(viewModel.dnsServer)
                        .font(.headline.monospaced())
                        .foregroundStyle(.white)
                    if let progress = viewModel.currentProgress {
                        Text(L10n.format("第 %lld/%lld 个域名 · 第 %lld/10 轮", progress.completedDomains + 1, progress.totalDomains, progress.currentRound))
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.72))
                            .monospacedDigit()
                    } else {
                        Text("准备中...").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: DesignSystem.Input.height)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ActionTextField(
                        placeholder: "例如: 223.5.5.5",
                        text: $viewModel.dnsServer,
                        actionTitle: "测试",
                        loadingTitle: nil,
                        isLoading: false,
                        isActionDisabled: viewModel.dnsServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        onClear: viewModel.resetTest,
                        action: viewModel.startTest
                    )
                    .onChange(of: viewModel.dnsServer) { _, _ in
                        if viewModel.state == .result { viewModel.resetTest() }
                    }
                    if viewModel.state == .result {
                        ScrollView(.horizontal) {
                            DNSTestCardView(mode: .result)
                                .frame(width: Self.resultWidth)
                        }
                    }
                }
            }
        }
    }
}
