//
//  SettingsView.swift
//  Enodia
//
//  Created by SlippinDylan on 2025/12/25.
//
//  ## 2026/01/07 重构
//  - 统一 API Key 管理
//  - 有免费 API 的数据源：未配置时用免费 API，配置后用付费 API
//  - 纯付费数据源：未配置时跳过
//  - 移除状态指示器图标
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(MihomoViewModel.self) private var mihomoViewModel
    @State private var dnsManager = DNSManager.shared
    @State private var permissionManager = PermissionManager.shared
    @State private var apiKeyManager = APIKeyManager.shared
    @State private var loginItemManager = LoginItemManager.shared

    // 导出/导入状态
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showImportConfirmAlert = false
    @State private var importedData: EnodiaExportData?

    var body: some View {
        EnodiaScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 通用设置
                generalSettingsSection

                // Mihomo 关联应用
                mihomoHostAppSection

                // IP 质量检测 API 配置
                apiKeySettingsSection

                // 配置导出/导入
                exportImportSection

                // 权限状态
                permissionsSection
            }
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .onAppear {
            permissionManager.refresh()
        }
        // 确认导入弹窗（需要用户操作）
        .alert("确认导入", isPresented: $showImportConfirmAlert) {
            Button("取消", role: .cancel) {
                importedData = nil
            }
            Button("导入") {
                if let data = importedData {
                    applyImportedData(data)
                }
            }
        } message: {
            if let data = importedData {
                Text("将导入 \(data.appControlScenes.count) 个应用控制场景、\(data.dnsControlScenes.count) 个 DNS 控制场景、API Key 配置以及 Mihomo 内核配置。\n\n此操作将覆盖现有配置，是否继续？")
            }
        }
    }

    // MARK: - Login Launch Settings Section

    private var generalSettingsSection: some View {
        GroupBox {
            HStack(spacing: DesignSystem.Spacing.standard) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.extraSmall) {
                    Text("登录时自动启动")
                        .font(.body)
                    Text("登录系统后自动运行 Enodia")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { loginItemManager.isEnabled },
                    set: { newValue in
                        do {
                            if newValue {
                                try loginItemManager.enable()
                            } else {
                                try loginItemManager.disable()
                            }
                        } catch {
                            AppLogger.error("更改开机自启状态失败", error: error)
                            loginItemManager.refreshStatus()
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.standard)
        } label: {
            SectionHeader(
                title: "通用",
                icon: "gearshape",
                iconColor: .gray,
                description: "应用基本行为"
            )
        }
    }

    // MARK: - Mihomo Host App Section

    private var mihomoHostAppSection: some View {
        GroupBox {
            HStack(spacing: DesignSystem.Spacing.standard) {
                Image(systemName: mihomoViewModel.config.hasAssociatedApp ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(mihomoViewModel.config.hasAssociatedApp ? .green : .secondary)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.extraSmall) {
                    Text(mihomoViewModel.config.hasAssociatedApp ? mihomoViewModel.config.appDisplayName : "未关联应用")
                        .font(.body)
                        .fontWeight(.medium)
                    Text(
                        mihomoViewModel.config.hasAssociatedApp
                            ? mihomoViewModel.config.appBundleIdentifier
                            : "选择正在使用的 Clash/Mihomo 客户端"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: DesignSystem.Spacing.small) {
                    if mihomoViewModel.config.hasAssociatedApp {
                        Button("取消关联") {
                            mihomoViewModel.clearHostApp()
                        }
                        .buttonStyle(.glass)
                        .disabled(mihomoViewModel.isSelectingHostApp)
                    }

                    Button(mihomoViewModel.config.hasAssociatedApp ? "更换应用…" : "选择应用…") {
                        mihomoViewModel.selectHostApp()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(mihomoViewModel.isSelectingHostApp)
                }
            }
            .padding(DesignSystem.Spacing.standard)
        } label: {
            SectionHeader(
                title: "Mihomo 关联应用",
                icon: "cube.fill",
                iconColor: .purple,
                description: "内核替换功能依赖的宿主应用"
            )
        }
    }

    // MARK: - Export/Import Section

    private var exportImportSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                HStack(spacing: DesignSystem.Spacing.standard) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.extraSmall) {
                        Text("导入配置")
                            .font(.body)
                        Text("从备份文件覆盖当前应用设置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        performImport()
                    } label: {
                        if isImporting {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 60)
                        } else {
                            Text("导入配置")
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(isImporting || isExporting)
                }

                Divider()

                HStack(spacing: DesignSystem.Spacing.standard) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.extraSmall) {
                        Text("导出配置")
                            .font(.body)
                        Text("将场景、DNS、API Key 和 Mihomo 设置保存为文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        performExport()
                    } label: {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 60)
                        } else {
                            Text("导出配置")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isImporting || isExporting)
                }
            }
            .padding(DesignSystem.Spacing.standard)
        } label: {
            SectionHeader(
                title: "配置管理",
                icon: "square.and.arrow.up.on.square",
                iconColor: .purple,
                description: "导出和导入应用配置"
            )
        }
    }

    // MARK: - Export/Import Actions

    private func performExport() {
        isExporting = true

        Task {
            let result = await SettingsExportService.shared.exportSettings()

            await MainActor.run {
                isExporting = false

                switch result {
                case .success(let url):
                    Toast.success("配置已导出到: \(url.lastPathComponent)")

                case .cancelled:
                    break

                case .failure(let error):
                    Toast.error(error.localizedDescription)
                }
            }
        }
    }

    private func performImport() {
        isImporting = true

        Task {
            let result = await SettingsExportService.shared.importSettings()

            await MainActor.run {
                isImporting = false

                switch result {
                case .success(let data):
                    // 先保存数据，显示确认弹窗
                    importedData = data
                    showImportConfirmAlert = true

                case .cancelled:
                    break

                case .failure(let error):
                    Toast.error(error.localizedDescription)
                }
            }
        }
    }

    private func applyImportedData(_ data: EnodiaExportData) {
        // 应用应用控制场景
        SceneStorage.saveScenes(data.appControlScenes)

        // 应用 DNS 控制场景
        DNSSceneStorage.shared.saveScenes(data.dnsControlScenes)

        // 应用 API Keys
        data.apiKeys.apply(to: apiKeyManager)

        // 应用 Mihomo 配置
        MihomoConfigService().saveConfig(data.mihomoConfig)
        mihomoViewModel.loadConfig()
        mihomoViewModel.refreshStatus()

        // 刷新 NetworkMonitor 中的场景
        networkMonitor.updateScenes(data.appControlScenes)
        networkMonitor.updateDNSScenes(data.dnsControlScenes)

        // 清理状态
        importedData = nil

        // 显示成功提示
        Toast.success("已导入 \(data.appControlScenes.count) 个场景和 \(data.dnsControlScenes.count) 个 DNS 场景")

        AppLogger.info("✅ 配置导入完成")
    }

    // MARK: - API Key Settings Section

    private var apiKeySettingsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                // 有免费 API 的数据源（配置后使用付费版）
                VStack(alignment: .leading, spacing: 12) {
                    Text("支持免费访问")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    // IPinfo
                    APIKeyInputRow(
                        label: "IPinfo",
                        placeholder: "Token",
                        value: $apiKeyManager.ipinfoToken,
                        helpURL: "https://ipinfo.io/signup"
                    )

                    // ipapi.is
                    APIKeyInputRow(
                        label: "ipapi.is",
                        placeholder: "API Key",
                        value: $apiKeyManager.ipapiKey,
                        helpURL: "https://ipapi.is/"
                    )

                    // DB-IP
                    APIKeyInputRow(
                        label: "DB-IP",
                        placeholder: "API Key",
                        value: $apiKeyManager.dbipKey,
                        helpURL: "https://db-ip.com/api/"
                    )

                    // IPWHOIS
                    APIKeyInputRow(
                        label: "IPWHOIS",
                        placeholder: "API Key",
                        value: $apiKeyManager.ipwhoisKey,
                        helpURL: "https://ipwhois.io/documentation"
                    )
                }

                Divider()

                // 纯付费数据源
                VStack(alignment: .leading, spacing: 12) {
                    Text("付费数据源")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    // AbuseIPDB
                    APIKeyInputRow(
                        label: "AbuseIPDB",
                        placeholder: "API Key",
                        value: $apiKeyManager.abuseipdbKey,
                        helpURL: "https://www.abuseipdb.com/api"
                    )

                    // IP2Location
                    APIKeyInputRow(
                        label: "IP2Location",
                        placeholder: "API Key",
                        value: $apiKeyManager.ip2locationKey,
                        helpURL: "https://www.ip2location.io/"
                    )

                    // ipregistry
                    APIKeyInputRow(
                        label: "ipregistry",
                        placeholder: "API Key",
                        value: $apiKeyManager.ipregistryKey,
                        helpURL: "https://ipregistry.co/"
                    )
                }
            }
            .padding(DesignSystem.Spacing.standard)
        } label: {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.standard) {
                SectionHeader(
                    title: "IP 质量数据源",
                    icon: "network",
                    iconColor: .blue,
                    description: "配置第三方数据源凭据；未配置时使用免费版或跳过付费源"
                )

                Spacer()

                HStack(spacing: DesignSystem.Spacing.small) {
                    Button("清除全部") {
                        apiKeyManager.clearAllAPIKeys()
                    }
                    .buttonStyle(.glass)
                    .disabled(!apiKeyManager.hasAnyAPIKey)

                    Button("保存配置") {
                        apiKeyManager.saveAPIKeys()
                    }
                    .buttonStyle(.glassProminent)
                }
                .padding(.bottom, DesignSystem.Spacing.small)
            }
        }
    }

    // MARK: - Permissions Section

    private var permissionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                ForEach(Array(permissionManager.permissions.enumerated()), id: \.element.type.displayName) { index, permission in
                    if index > 0 {
                        Divider()
                    }

                    HStack(spacing: DesignSystem.Spacing.medium) {
                        Image(systemName: permission.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(Color(permission.statusColor))
                            .font(.system(size: 14))

                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.extraSmall) {
                            Text(permission.type.displayName)
                                .font(.system(size: 14, weight: .medium))
                            Text(permission.isGranted ? permission.type.description : permission.type.guideText)
                                .font(.caption)
                                .foregroundStyle(permission.isGranted ? Color.secondary : Color.orange)
                        }

                        Spacer()

                        Text(permission.statusText)
                            .font(.caption)
                            .foregroundStyle(Color(permission.statusColor))

                        switch permission.type {
                        case .accessibility:
                            if !permission.isGranted && permission.isRequired {
                                Button("打开设置") {
                                    permissionManager.openAccessibilitySettings()
                                }
                                .buttonStyle(.glassProminent)
                                .controlSize(.small)
                            }
                        case .helperTool:
                            HelperActionButton(
                                dnsManager: dnsManager,
                                networkMonitor: networkMonitor,
                                isInstalled: permission.isGranted
                            )
                        }
                    }
                }
            }
            .padding(DesignSystem.Spacing.standard)
        } label: {
            SectionHeader(
                title: "权限",
                icon: "lock.shield",
                iconColor: permissionManager.allRequiredGranted ? .green : .orange,
                description: "Enodia 所需的系统权限"
            )
        }
    }
}

// MARK: - Helper Action Button

/// Helper 操作按钮组件
///
/// ## 功能
/// - 根据安装状态显示「安装 Helper」或「卸载 Helper」按钮
/// - 显示操作进度和结果反馈
/// - 操作成功后自动刷新权限状态
/// - 安装成功后触发 DNS 场景匹配
private struct HelperActionButton: View {
    let dnsManager: DNSManager
    let networkMonitor: NetworkMonitor
    let isInstalled: Bool

    @State private var isProcessing: Bool = false

    var body: some View {
        Group {
            if isInstalled {
                Button(role: .destructive) {
                    uninstallHelper()
                } label: {
                    buttonLabel
                }
                .buttonStyle(.glass)
            } else {
                Button {
                    installHelper()
                } label: {
                    buttonLabel
                }
                .buttonStyle(.glassProminent)
            }
        }
        .controlSize(.small)
        .disabled(isProcessing)
    }

    @ViewBuilder
    private var buttonLabel: some View {
        if isProcessing {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 8)
        } else {
            Text(isInstalled ? "卸载 Helper" : "安装 Helper")
        }
    }

    private func installHelper() {
        isProcessing = true
        dnsManager.installHelper { success, error in
            DispatchQueue.main.async {
                isProcessing = false

                if success {
                    Toast.success("DNS Helper 已成功安装")
                    // 触发 DNS 场景匹配，确保已开启的场景立即生效
                    networkMonitor.refreshDNSSceneMatching()
                } else {
                    let message = error?.localizedDescription ?? "安装失败，请重试"
                    Toast.error(message)
                }

                // 刷新权限状态
                PermissionManager.shared.refresh()
            }
        }
    }

    private func uninstallHelper() {
        isProcessing = true
        dnsManager.uninstallHelper { success, error in
            DispatchQueue.main.async {
                isProcessing = false

                if success {
                    Toast.success("DNS Helper 已成功卸载")
                } else {
                    let message = error?.localizedDescription ?? "卸载失败，请重试"
                    Toast.error(message)
                }

                // 刷新权限状态
                PermissionManager.shared.refresh()
            }
        }
    }
}

// MARK: - API Key Input Row

private struct APIKeyInputRow: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    let helpURL: String
    @State private var isSecure: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            // 标签
            Text(label)
                .font(.system(size: 13))
                .frame(width: 100, alignment: .leading)

            // 输入框容器
            HStack(spacing: 0) {
                // 输入框
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $value)
                    } else {
                        TextField(placeholder, text: $value)
                    }
                }
                .textFieldStyle(.plain)
                .padding(.leading, 10)
                .padding(.vertical, 6)

                // 眼睛按钮
                Button {
                    isSecure.toggle()
                } label: {
                    Image(systemName: isSecure ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .help(isSecure ? "显示" : "隐藏")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )

            // 帮助链接
            Button {
                if let url = URL(string: helpURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.blue)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("获取 API Key")
        }
    }
}
