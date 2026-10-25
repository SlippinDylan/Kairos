import SwiftUI

struct NetworkToolsView: View {
    @Environment(MihomoViewModel.self) private var mihomo
    @Environment(WindowCoordinator.self) private var windowCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(NetworkToolsViewModel.self) private var maintenance
    @State private var ipQuery = IPQueryViewModel.shared
    @State private var dnsTest = DNSTestViewModel.shared
    @State private var ipQuality = IPQualityViewModel.shared
    @State private var presentedTool: NetworkTool?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    private var showsIPQualityResult: Bool {
        presentedTool == .ipQuality && !ipQuality.isLoading && ipQuality.result != nil
    }

    var body: some View {
        Group {
            if let tool = presentedTool {
                toolDetail(tool)
            } else {
                toolsGrid
                    .safeAreaInset(edge: .top, spacing: 0) {
                        PopoverNavigationBar {
                            Button {
                                mihomo.refreshStatus()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .symbolEffect(.rotate, options: .repeating, isActive: mihomo.isRefreshing && !reduceMotion)
                            }
                            .buttonBorderShape(.circle)
                            .disabled(mihomo.isRefreshing)
                            .accessibilityLabel(Text("刷新内核状态"))
                            .help("刷新内核状态")
                        }
                    }
            }
        }
        .onAppear {
            if presentedTool == nil {
                windowCoordinator.resetContentSize()
            }
        }
    }

    private var toolsGrid: some View {
        KairosScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                Text("系统维护")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                LazyVGrid(columns: columns, spacing: 12) {
                    toolCard(.dnsCleanup)
                    Color.clear.accessibilityHidden(true)
                    Color.clear.accessibilityHidden(true)
                    ForEach(KernelTool.allCases) { tool in
                        toolCard(.kernel(tool))
                    }
                }

                Divider()

                Text("网络检测")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                LazyVGrid(columns: columns, spacing: 12) {
                    toolCard(.ipQuery)
                    toolCard(.dnsTest)
                    toolCard(.ipQuality)
                }
            }
            .padding(DesignSystem.Spacing.standard)
        }
    }

    private func toolDetail(_ tool: NetworkTool) -> some View {
        NetworkToolSheet(
            title: tool.title,
            hostWindowSize: CGSize(width: toolContentWidth, height: DesignSystem.Window.minimumHeight),
            preventsClosing: preventsClosing(tool),
            fitsContent: tool == .ipQuery || tool == .dnsTest || tool == .ipQuality,
            padsContent: tool != .ipQuality,
            balancesHeader: balancesHeader(for: tool),
            maximumContentHeight: windowCoordinator.maximumContentHeight,
            progress: progress(for: tool),
            onCancel: cancellation(for: tool),
            onClose: {
                presentedTool = nil
                windowCoordinator.resetContentSize()
            },
            onSizeChange: { size in
                guard presentedTool == tool else { return }
                windowCoordinator.setContentSize(size)
            }
        ) {
            switch tool {
            case .dnsCleanup:
                DNSCleanupToolDetail(viewModel: maintenance)
            case .kernel(let operation):
                KernelToolDetail(tool: operation)
            case .ipQuery:
                IPQueryToolDetail()
            case .dnsTest:
                DNSToolDetail()
            case .ipQuality:
                IPQualityNetworkToolCard()
            }
        }
    }

    private func balancesHeader(for tool: NetworkTool) -> Bool {
        switch tool {
        case .ipQuery:
            ipQuery.result == nil
        case .dnsTest:
            dnsTest.state != .result
        case .ipQuality:
            ipQuality.isLoading || ipQuality.result == nil
        case .dnsCleanup, .kernel:
            false
        }
    }

    private func cancellation(for tool: NetworkTool) -> (() -> Void)? {
        if tool == .dnsTest, dnsTest.state == .testing {
            return dnsTest.cancelTest
        }
        if tool == .ipQuality, ipQuality.isLoading {
            return ipQuality.cancelDetection
        }
        return nil
    }

    private func progress(for tool: NetworkTool) -> Double? {
        if tool == .dnsTest, dnsTest.state == .testing {
            return dnsTest.currentProgress?.overallProgress ?? 0
        }
        if tool == .ipQuality, ipQuality.isLoading { return ipQuality.currentProgress }
        return nil
    }

    private var toolContentWidth: CGFloat {
        let width: CGFloat
        if showsIPQualityResult {
            width = IPQualityCardCompletedView.minimumTableWidth + DesignSystem.Spacing.standard * 4
        } else if presentedTool == .dnsTest, dnsTest.state == .result {
            width = DNSToolDetail.resultWidth + DesignSystem.Spacing.standard * 4
        } else {
            width = DesignSystem.Window.width
        }
        // Read the observable limit so display changes remeasure the explicit detail width.
        return min(width, windowCoordinator.maximumContentWidth ?? width)
    }

    private func toolCard(_ tool: NetworkTool) -> some View {
        NetworkToolCard(title: tool.title, icon: tool.icon, color: tool.color, status: status(for: tool)) {
            presentedTool = tool
        }
    }

    private func status(for tool: NetworkTool) -> String {
        switch tool {
        case .dnsCleanup:
            return L10n.string(maintenance.isExecuting ? "执行中..." : "清理网络缓存")
        case .kernel(let operation):
            return operation.status(in: mihomo)
        case .ipQuery:
            return L10n.string(ipQuery.isLoading ? "查询中..." : ipQuery.result != nil ? "查看结果" : "查询 IP 信息")
        case .dnsTest:
            return L10n.string(dnsTest.state == .testing ? "测试中..." : dnsTest.state == .result ? "查看结果" : "测试解析速度")
        case .ipQuality:
            return L10n.string(ipQuality.isLoading ? "检测中" : ipQuality.result != nil ? "查看结果" : "检测当前网络")
        }
    }

    private func preventsClosing(_ tool: NetworkTool) -> Bool {
        switch tool {
        case .dnsCleanup: maintenance.isExecuting
        case .kernel: mihomo.isLoading || mihomo.isDownloading
        case .ipQuery, .dnsTest, .ipQuality: false
        }
    }
}

private enum NetworkTool: Hashable, Identifiable {
    case dnsCleanup
    case kernel(KernelTool)
    case ipQuery
    case dnsTest
    case ipQuality

    var id: Self { self }

    var title: String {
        switch self {
        case .dnsCleanup: L10n.string("DNS 清理")
        case .kernel(let operation): operation.title
        case .ipQuery: L10n.string("IP 查询")
        case .dnsTest: L10n.string("DNS 测试")
        case .ipQuality: L10n.string("IP 质量")
        }
    }

    var icon: String {
        switch self {
        case .dnsCleanup: "wrench.and.screwdriver.fill"
        case .kernel(let operation): operation.icon
        case .ipQuery: "network"
        case .dnsTest: "network.badge.shield.half.filled"
        case .ipQuality: "shield.checkered"
        }
    }

    var color: Color {
        switch self {
        case .dnsCleanup: .blue
        case .kernel: .purple
        case .ipQuery: .purple
        case .dnsTest: .green
        case .ipQuality: .orange
        }
    }
}

private struct NetworkToolCard: View {
    let title: String
    let icon: String
    let color: Color
    let status: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isHovered ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .help(title + " · " + status)
    }
}


struct IPQueryResultContent: View {
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
            InfoRow(label: "坐标", value: result.coordinates?.displayString ?? "—")

            if let coordinates = result.coordinates {
                Divider()
                MapView(latitude: coordinates.latitude, longitude: coordinates.longitude)
                    .frame(minHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            }
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

    var errorMessage: String?

    /// 上次执行时间
    var lastExecutionTime: Date?

    // MARK: - Dependencies

    private let service = NetworkMaintenanceService()

    // MARK: - Public Methods

    /// 执行深度清理
    func executeDeepClean() async {
        guard !isExecuting else { return }
        isExecuting = true
        errorMessage = nil
        defer { isExecuting = false }

        do {
            try await service.deepClean()
            lastExecutionTime = Date()
            Toast.success(L10n.string("深度清理完成"))
            AppLogger.info("✅ 深度清理成功")
        } catch {
            errorMessage = error.localizedDescription
            Toast.error(error.localizedDescription)
            AppLogger.error("深度清理失败", error: error)
        }
    }
}
