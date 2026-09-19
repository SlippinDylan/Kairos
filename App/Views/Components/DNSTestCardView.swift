//
//  DNSTestCardView.swift
//  Kairos
//
//  Created by SlippinDylan on 2026/01/06.
//  Migrated from DNSTestView for NetworkToolsView integration
//

import SwiftUI

/// DNS 测试卡片组件（紧凑布局）
///
/// ## 设计说明
/// - 从 DNSTestView 提取，适配卡片内部布局
/// - 去掉全屏居中的 GeometryReader
/// - 保持三段式状态机：Input → Testing → Result
/// - 复用 DNSTestViewModel.shared 单例
struct DNSTestCardView: View {
    enum Mode {
        case compact
        case result
    }

    // MARK: - State

    @State private var viewModel = DNSTestViewModel.shared
    let mode: Mode
    let onResultAvailable: () -> Void
    let onShowResult: () -> Void
    let onRetest: () -> Void

    init(
        mode: Mode = .compact,
        onResultAvailable: @escaping () -> Void = {},
        onShowResult: @escaping () -> Void = {},
        onRetest: @escaping () -> Void = {}
    ) {
        self.mode = mode
        self.onResultAvailable = onResultAvailable
        self.onShowResult = onShowResult
        self.onRetest = onRetest
    }

    // MARK: - Body

    var body: some View {
        Group {
            if mode == .result {
                resultView
            } else {
                compactCard
            }
        }
        .onChange(of: viewModel.state) { _, state in
            if mode == .compact, state == .result {
                onResultAvailable()
            }
        }
    }

    private var compactCard: some View {
        Group {
            switch viewModel.state {
            case .input:
                inputView
            case .testing:
                testingView
            case .result:
                completedView
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            ProgressCardBackground(
                progress: viewModel.state == .testing
                    ? viewModel.currentProgress?.overallProgress ?? 0
                    : nil
            )
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.state)
    }

    private var completedView: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Spacer()

            Button("查看结果", action: onShowResult)
                .buttonStyle(.glass)

            Button("重新测试") {
                viewModel.resetTest()
            }
            .buttonStyle(.glassProminent)

            Spacer()
        }
        .frame(height: 64)
    }

    // MARK: - State A: Input View

    /// 输入状态视图（紧凑布局，适配卡片）
    private var inputView: some View {
        CapsuleActionTextField(
            placeholder: "例如: 223.5.5.5",
            text: $viewModel.dnsServer,
            actionTitle: "测试",
            loadingTitle: nil,
            isLoading: false,
            isActionDisabled: viewModel.dnsServer.trimmingCharacters(in: .whitespaces).isEmpty,
            onClear: {},
            action: viewModel.startTest
        )
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .frame(height: 64)
    }

    // MARK: - State B: Testing View

    /// 测试状态视图（进度背景 + 当前进度提示 + 取消按钮）
    private var testingView: some View {
        ZStack {
            if let progress = viewModel.currentProgress {
                Text("\(progress.description) · \(Int(progress.overallProgress * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
            } else {
                Text("准备中...")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }

            HStack {
                Spacer()

                Button {
                    viewModel.cancelTest()
                } label: {
                    Text("取消")
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .help("取消测试")
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.large)
        .frame(height: 64)
    }

    // MARK: - State C: Result View

    /// 结果状态视图（统计卡片 + 表格 + 重新测试按钮）
    private var resultView: some View {
        VStack(spacing: 16) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("测试结果")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text("DNS 服务器: \(viewModel.dnsServer)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 重新测试按钮
                Button {
                    viewModel.resetTest()
                    onRetest()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("重新测试")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
            }

            // 平均统计卡片
            if let stats = viewModel.overallStatistics {
                HStack(spacing: 12) {
                    // 平均耗时
                    CompactStatisticCard(
                        title: "平均耗时",
                        value: String(format: "%.2f", stats.averageTime),
                        unit: "ms",
                        color: colorForTime(stats.averageTime)
                    )

                    // 最快
                    CompactStatisticCard(
                        title: "最快",
                        value: "\(stats.minTime)",
                        unit: "ms",
                        color: .green
                    )

                    // 最慢
                    CompactStatisticCard(
                        title: "最慢",
                        value: "\(stats.maxTime)",
                        unit: "ms",
                        color: .red
                    )

                    // 成功率
                    CompactStatisticCard(
                        title: "成功率",
                        value: String(format: "%.0f", stats.successRate * 100),
                        unit: "%",
                        color: stats.successRate >= 0.8 ? .green : .orange
                    )
                }
            }

            // 结果表格
            VStack(spacing: 0) {
                if viewModel.results.isEmpty {
                    // 空状态
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                        Text("测试失败，未获取到任何结果")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 200)
                } else {
                    // 表格视图
                    Table(viewModel.results) {
                        TableColumn("域名", value: \.domain)
                            .width(min: 150, ideal: 200, max: 300)

                        TableColumn("平均耗时") { result in
                            HStack(spacing: 4) {
                                Text(result.formattedAverageTime)
                                    .foregroundStyle(colorForTime(result.averageTime))
                                Text("ms")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .width(min: 80, ideal: 100)

                        TableColumn("最快") { result in
                            HStack(spacing: 4) {
                                Text("\(result.minTime)")
                                    .foregroundStyle(.green)
                                Text("ms")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .width(min: 70, ideal: 80)

                        TableColumn("最慢") { result in
                            HStack(spacing: 4) {
                                Text("\(result.maxTime)")
                                    .foregroundStyle(.red)
                                Text("ms")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .width(min: 70, ideal: 80)

                        TableColumn("成功率") { result in
                            HStack(spacing: 4) {
                                Text(String(format: "%.0f%%", result.successRate * 100))
                                    .foregroundStyle(result.successRate >= 0.8 ? .green : .orange)
                            }
                        }
                        .width(min: 70, ideal: 80)
                    }
                    .frame(height: 300)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    // MARK: - Helper Methods

    /// 根据耗时返回颜色（遵循性能指标）
    ///
    /// - 0-30ms: 绿色（优秀）
    /// - 30-80ms: 黄色（良好）
    /// - 80ms+: 红色（较慢）
    private func colorForTime(_ time: Double) -> Color {
        if time < 30 {
            return .green
        } else if time < 80 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - CompactStatisticCard Component

/// 紧凑统计数据卡片组件（用于卡片内部）
struct CompactStatisticCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(L10n.string(title))
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                Text(L10n.string(unit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}
