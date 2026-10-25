//
//  MihomoView.swift
//  Kairos
//

import SwiftUI

extension KernelTool {
    var title: String {
        switch self {
        case .backup: L10n.string("备份 Mihomo 内核")
        case .restore: L10n.string("恢复 Mihomo 内核")
        case .replace: L10n.string("替换 Mihomo 内核")
        }
    }

    var icon: String {
        switch self {
        case .backup: "tray.and.arrow.down.fill"
        case .restore: "arrow.uturn.backward.circle.fill"
        case .replace: "arrow.triangle.2.circlepath"
        }
    }

    @MainActor
    func status(in model: MihomoViewModel) -> String {
        if model.activeTool == self { return L10n.string("处理中") }
        guard let config = model.config else { return L10n.string("Mihomo 配置读取失败") }
        if config.kernelPath.isEmpty { return L10n.string("尚未选择内核文件") }
        guard let status = model.kernelStatus else { return L10n.string("检测中") }
        switch self {
        case .backup:
            if !status.kernelExists { return L10n.string("内核文件不存在") }
            return status.backupExists ? L10n.string("内核已备份") : L10n.string("内核未备份")
        case .restore:
            return status.backupExists ? L10n.string("内核已备份") : L10n.string("备份文件不存在")
        case .replace:
            if !status.kernelExists { return L10n.string("内核文件不存在") }
            switch model.hostAppInstallStatus {
            case .notConfigured: return L10n.string("未关联")
            case .unknown: return L10n.string("检测中")
            case .notInstalled:
                return L10n.format("未检测到 %@", config.appDisplayName)
            case .installed:
                return L10n.format(model.isHostAppRunning ? "%@ 运行中" : "%@ 未运行", config.appDisplayName)
            }
        }
    }
}

struct KernelToolDetail: View {
    let tool: KernelTool
    @Environment(MihomoViewModel.self) private var viewModel

    private var isBusy: Bool { viewModel.isLoading || viewModel.isDownloading }

    private var canPerform: Bool {
        guard !isBusy, !viewModel.isRefreshing, let config = viewModel.config, !config.kernelPath.isEmpty,
              let status = viewModel.kernelStatus else { return false }
        switch tool {
        case .backup: return status.kernelExists && !status.backupExists
        case .restore: return status.backupExists
        case .replace: return status.kernelExists
        }
    }

    private var explanation: LocalizedStringKey {
        switch tool {
        case .backup: "保存当前内核副本，供后续恢复使用"
        case .restore: "使用已备份的文件恢复当前内核"
        case .replace: "从 GitHub 下载最新预发布版本并替换当前内核"
        }
    }

    var body: some View {
        Group {
            if let config = viewModel.config {
                loadedContent(config)
            } else if let error = viewModel.configurationError {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    Button("重试", action: viewModel.refreshStatus)
                }
            }
        }
        .onAppear { viewModel.refreshStatus() }
    }

    private func loadedContent(_ config: MihomoConfig) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.standard) {
            Text(explanation)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    HStack {
                        Text("关联应用")
                        Spacer()
                        Text(hostAppStatus(config: config))
                            .foregroundStyle(.secondary)
                    }
                    if config.hasAssociatedApp {
                        Text(config.appBundlePath)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        HStack {
                            Text("运行状态")
                            Spacer()
                            Text(runningStatus)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        Text("内核文件路径")
                        Text(config.kernelPath.isEmpty ? L10n.string("尚未选择内核文件") : config.kernelPath)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                        Text(viewModel.kernelStatus?.statusDescription ?? L10n.string("检测中"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if tool != .replace, let status = viewModel.kernelStatus, status.backupExists {
                        Divider()
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                            Text("备份文件")
                            Text(status.backupPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    if tool == .replace {
                        Divider()
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                            Text("GitHub Releases URL")
                            Text(config.githubReleasesURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text("内核文件名模板")
                            Text(config.kernelFilenameTemplate)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.small)
            }

            if config.kernelPath.isEmpty {
                Text("请前往设置的服务组配置内核文件路径")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if viewModel.isHostAppRunning {
                Text("操作前会请求退出关联应用，完成后可重新启动应用")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if viewModel.activeTool == tool {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(viewModel.isDownloading ? viewModel.downloadStatusText : L10n.string("处理中"))
                        .font(.callout)
                }
                if viewModel.isDownloading, let progress = viewModel.downloadProgress {
                    ProgressView(value: progress)
                }
            }

            if let result = viewModel.operationResult(for: tool) {
                Label(result.message, systemImage: result.isError ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(result.isError ? Color.orange : Color.green)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button(tool.title) {
                    switch tool {
                    case .backup: viewModel.backupKernel()
                    case .restore: viewModel.restoreKernel()
                    case .replace: viewModel.replaceKernel()
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(!canPerform)
            }
        }
    }

    private func hostAppStatus(config: MihomoConfig) -> String {
        switch viewModel.hostAppInstallStatus {
        case .notConfigured: return L10n.string("未关联")
        case .notInstalled: return L10n.string("未检测到该应用")
        case .installed: return config.appDisplayName + " · " + L10n.string("已安装")
        case .unknown: return L10n.string("检测中")
        }
    }

    private var runningStatus: String {
        switch viewModel.hostAppInstallStatus {
        case .unknown: return L10n.string("检测中")
        case .notConfigured: return L10n.string("未关联")
        case .notInstalled, .installed:
            return viewModel.isHostAppRunning ? L10n.string("运行中") : L10n.string("未运行")
        }
    }
}
