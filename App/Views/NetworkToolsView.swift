//
//  NetworkToolsView.swift
//  Kairos
//
//  Created by SlippinDylan on 2026/01/04.
//

import SwiftUI

/// 网络工具视图
///
/// ## 功能
/// - DNS 深度清理：一键执行网络缓存清理、接口重置等维护操作
/// - IP 查询：查询 IP 地址的详细信息
struct NetworkToolsView: View {
    @State private var viewModel = NetworkToolsViewModel()
    @State private var ipQueryViewModel = IPQueryViewModel.shared
    @State private var ipQualityViewModel = IPQualityViewModel.shared
    @State private var ipAddress = ""
    @State private var presentedResult: NetworkToolResult?
    @State private var hostWindowSize = CGSize(width: 1080, height: 720)

    var body: some View {
        KairosScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // DNS 深度清理卡片
                GroupBox {
                    HStack(spacing: 16) {
                        // 左侧说明
                        VStack(alignment: .leading, spacing: 12) {
                            // 说明文本
                            Text("清理 DNS 缓存、重置网络接口、清除 ARP 缓存、重置 WiFi、清理浏览器缓存")
                                .font(.body)
                                .foregroundStyle(.secondary)

                            // 警告文本
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                Text("执行时将中断网络连接 2-5 秒")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }

                            // 上次执行时间
                            if let lastTime = viewModel.lastExecutionTime {
                                HStack {
                                    Image(systemName: "clock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("上次执行：\(lastTime, style: .date) \(lastTime, style: .time)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // 右侧按钮（垂直居中）
                        Button {
                            viewModel.showConfirmation = true
                        } label: {
                            if viewModel.isExecuting {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("执行中...")
                                }
                            } else {
                                Text("执行深度清理")
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(viewModel.isExecuting)
                    }
                    .padding()
                } label: {
                    SectionHeader(title: "DNS 深度清理", icon: "wrench.and.screwdriver.fill", iconColor: .blue)
                }

                // IP 查询卡片（包含输入框和结果）
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    SectionHeader(title: "IP 查询", icon: "network", iconColor: .purple)

                    HStack(spacing: DesignSystem.Spacing.small) {
                        CapsuleActionTextField(
                            placeholder: "输入 IP 地址",
                            text: $ipAddress,
                            actionTitle: "查询",
                            loadingTitle: "查询中...",
                            isLoading: ipQueryViewModel.isLoading,
                            isActionDisabled: ipQueryViewModel.isLoading
                                || ipAddress.trimmingCharacters(in: .whitespaces).isEmpty,
                            onClear: {
                                ipQueryViewModel.reset()
                            },
                            action: {
                                Task {
                                    await ipQueryViewModel.queryIP(ipAddress)
                                    if ipQueryViewModel.result != nil {
                                        presentedResult = .ipQuery
                                    }
                                }
                            }
                        )

                        if ipQueryViewModel.result != nil {
                            Button("查看结果") {
                                presentedResult = .ipQuery
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .frame(height: 64)
                    .background {
                        ProgressCardBackground(progress: nil)
                    }
                }

                // DNS 测试卡片
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    SectionHeader(
                        title: "DNS 测试",
                        icon: "network.badge.shield.half.filled",
                        iconColor: .green
                    )

                    DNSTestCardView(
                        onResultAvailable: { presentedResult = .dnsTest },
                        onShowResult: { presentedResult = .dnsTest }
                    )
                }

                // IP 质量卡片
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    SectionHeader(
                        title: "IP 质量",
                        icon: "shield.checkered",
                        iconColor: .orange
                    )

                    IPQualityNetworkToolCard(
                        onResultAvailable: { presentedResult = .ipQuality },
                        onShowResult: { presentedResult = .ipQuality }
                    )
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.top, DesignSystem.Spacing.standard)
        }
        .navigationTitle(L10n.string("网络工具"))
        .navigationSubtitle(L10n.string("page.networkTools.description"))
        .background {
            WindowAccessor { window in
                let size = window.contentLayoutRect.size
                Task { @MainActor in
                    if hostWindowSize != size {
                        hostWindowSize = size
                    }
                }
            }
        }
        .sheet(item: $presentedResult) { result in
            NetworkToolResultSheet(
                title: result.title,
                subtitle: result == .ipQuality ? ipQualityResultDateText : nil,
                hostWindowSize: hostWindowSize,
                onRetest: result == .ipQuality ? {
                    ipQualityViewModel.resetDetection()
                    presentedResult = nil
                } : nil
            ) {
                switch result {
                case .ipQuery:
                    if let queryResult = ipQueryViewModel.result {
                        IPQueryResultContent(result: queryResult)
                    }
                case .dnsTest:
                    DNSTestCardView(
                        mode: .result,
                        onRetest: {
                            presentedResult = nil
                        }
                    )
                case .ipQuality:
                    if let qualityResult = ipQualityViewModel.result {
                        IPQualityCardCompletedView(result: qualityResult)
                    }
                }
            }
        }
        // 确认弹窗（需要用户操作）
        .alert("确认执行深度清理？", isPresented: $viewModel.showConfirmation) {
            Button("取消", role: .cancel) { }
            Button("执行") {
                Task {
                    await viewModel.executeDeepClean()
                }
            }
        } message: {
            Text("""
            此操作将执行：
            • 清理 DNS 缓存
            • 重置网络接口
            • 清除 ARP 缓存
            • 重置 WiFi
            • 清理浏览器缓存（Chrome、Firefox）
            • 清理系统缓存

            ⚠️ 将中断网络连接 2-5 秒
            """)
        }
    }

    private var ipQualityResultDateText: String? {
        ipQualityViewModel.result?.detectedAt.formatted(
            .dateTime
            .year()
            .month(.twoDigits)
            .day(.twoDigits)
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
        )
    }
}

private enum NetworkToolResult: String, Identifiable {
    case ipQuery
    case dnsTest
    case ipQuality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ipQuery: L10n.string("IP 查询结果")
        case .dnsTest: L10n.string("DNS 测试结果")
        case .ipQuality: L10n.string("IP 质量检测结果")
        }
    }
}

private struct NetworkToolResultSheet<Content: View>: View {
    let title: String
    let subtitle: String?
    let hostWindowSize: CGSize
    let onRetest: (() -> Void)?
    private let content: Content

    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        subtitle: String? = nil,
        hostWindowSize: CGSize,
        onRetest: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.hostWindowSize = hostWindowSize
        self.onRetest = onRetest
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(DesignSystem.Spacing.standard)

            Divider()

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.large)
            }

            Divider()

            HStack {
                Spacer()

                if let onRetest {
                    Button("重新检测") {
                        onRetest()
                        dismiss()
                    }
                    .buttonStyle(.glass)
                }

                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.glassProminent)
            }
            .padding(DesignSystem.Spacing.standard)
        }
        .frame(
            width: hostWindowSize.width * 0.7,
            height: hostWindowSize.height * 0.8
        )
    }
}

private struct IPQueryResultContent: View {
    let result: IPQueryResult

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            InfoRow(label: "自治系统号", value: result.asn)
            InfoRow(label: "IP类型", value: result.ipType)
            InfoRow(label: "组织", value: result.organization)
            InfoRow(label: "时区", value: result.timezone)
            InfoRow(label: "使用地", value: result.location.usageLocation)
            InfoRow(label: "注册地", value: result.registrationCountry)
            InfoRow(label: "城市", value: result.location.cityDisplay)
            InfoRow(label: "坐标", value: result.coordinates.displayString)

            Divider()

            MapView(latitude: result.latitude, longitude: result.longitude)
                .frame(minHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        }
    }
}

// MARK: - ViewModel

/// 网络工具 ViewModel
@MainActor
@Observable
final class NetworkToolsViewModel {
    // MARK: - State

    /// 深度清理执行中
    var isExecuting = false

    /// 显示确认弹窗
    var showConfirmation = false

    /// 上次执行时间
    var lastExecutionTime: Date?

    // MARK: - Dependencies

    private let service = NetworkMaintenanceService()

    // MARK: - Public Methods

    /// 执行深度清理
    func executeDeepClean() async {
        isExecuting = true
        defer { isExecuting = false }

        do {
            try await service.deepClean()
            lastExecutionTime = Date()
            Toast.success(L10n.string("深度清理完成"))
            AppLogger.info("✅ 深度清理成功")
        } catch {
            Toast.error(error.localizedDescription)
            AppLogger.error("深度清理失败", error: error)
        }
    }
}
