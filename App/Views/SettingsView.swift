//
//  SettingsView.swift
//  Kairos
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
    @Environment(SettingsViewModel.self) private var settingsViewModel
    @State private var dnsManager = DNSManager.shared
    @State private var permissionManager = PermissionManager.shared
    @State private var apiKeyManager = APIKeyManager.shared
    @State private var loginItemManager = LoginItemManager.shared
    @State private var languageController = ApplicationLanguageController.shared
    @State private var logSettings = LogSettings.shared

    // 导出/导入状态
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showImportConfirmAlert = false
    @State private var importedData: KairosExportData?
    @State private var showLanguageRestartAlert = false

    var body: some View {
        KairosScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                settingsGroup("通用") {
                    generalSettingsSection
                }

                Divider()

                settingsGroup("settings.pane.services") {
                    mihomoSettingsSection
                }

                Divider()

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.small) {
                        Text("IP 质量数据源")
                            .font(.title3.weight(.semibold))
                            .fixedSize()
                            .accessibilityAddTraits(.isHeader)
                        Text("配置第三方数据源凭据；未配置时使用免费版或跳过付费源")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    apiKeySettingsSection
                }

                Divider()

                settingsGroup("settings.pane.data") {
                    exportImportSection
                }

                Divider()

                settingsGroup("权限") {
                    permissionsSection
                }

                Divider()

                settingsGroup("日志") {
                    loggingSection
                }
            }
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.standard)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PopoverNavigationBar {
                if settingsViewModel.hasChanges {
                    Button("保存配置", systemImage: "checkmark", action: saveSettings)
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.circle)
                        .help("保存配置")
                        .disabled(!settingsViewModel.canSaveConfiguration || mihomoViewModel.isLoading || mihomoViewModel.isDownloading || isImporting || isExporting)
                }
            }
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
        .alert("language.restart.title", isPresented: $showLanguageRestartAlert) {
            Button("language.restart.now") {
                ApplicationRelaunchController.shared.requestRelaunch()
            }
            Button("language.restart.later", role: .cancel) {}
        } message: {
            Text("language.restart.message")
        }
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text(L10n.string(title))
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    // MARK: - Login Launch Settings Section

    private var generalSettingsSection: some View {
        GroupBox {
            VStack(spacing: 0) {
                HStack(spacing: DesignSystem.Spacing.standard) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.extraSmall) {
                        Text("登录时自动启动")
                            .font(.body)
                        Text("登录系统后自动运行 Kairos")
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
                    .controlSize(.mini)
                }
                .padding(DesignSystem.Spacing.small)

                Divider()

                HStack(alignment: .center, spacing: DesignSystem.Spacing.standard) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.extraSmall) {
                        Text("language.setting.title")
                            .font(.body)
                        Text("language.setting.description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("language.setting.title", selection: Binding(
                        get: { languageController.selectedLanguage },
                        set: { language in
                            if languageController.setSelectedLanguage(language) {
                                showLanguageRestartAlert = true
                            }
                        }
                    )) {
                        ForEach(ApplicationLanguage.allCases, id: \.self) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.regular)
                    .fixedSize()
                }
                .padding(DesignSystem.Spacing.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Mihomo Settings

    @ViewBuilder
    private var mihomoSettingsSection: some View {
        switch settingsViewModel.mihomo {
        case .success(let draft):
            mihomoSettingsFields(config: Binding(get: { draft }, set: { settingsViewModel.mihomo = .success($0) }))
        case .failure(let error):
            GroupBox {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Text(error.localizedDescription).foregroundStyle(.red).textSelection(.enabled)
                    Button("重试") {
                        settingsViewModel.retryConfigurationLoad()
                        mihomoViewModel.loadConfig()
                        mihomoViewModel.refreshStatus()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignSystem.Spacing.small)
            }
        }
    }

    private func mihomoSettingsFields(config: Binding<MihomoConfig>) -> some View {
        return GroupBox {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.standard) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Text("Mihomo 应用路径")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ClearableSettingsField(placeholder: "输入 Mihomo 应用路径", text: config.appBundlePath)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Text("内核文件路径")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ClearableSettingsField(placeholder: "输入内核文件路径", text: config.kernelPath)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Text("GitHub Releases URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            if let url = URL(string: config.wrappedValue.githubReleasesURL),
                               url.scheme == "https" || url.scheme == "http" {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label("访问", systemImage: "arrow.up.forward.square")
                                .font(.caption2)
                        }
                        .buttonStyle(.link)
                    }
                    ClearableSettingsField(placeholder: "输入 GitHub Releases URL", text: config.githubReleasesURL)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Text("内核文件名模板")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ClearableSettingsField(placeholder: "例如：mihomo-darwin-arm64-alpha-smart", text: config.kernelFilenameTemplate)
                }
            }
            .padding(DesignSystem.Spacing.small)
            .disabled(mihomoViewModel.isLoading || mihomoViewModel.isDownloading)
        }
    }

    private func saveSettings() {
        do {
            try settingsViewModel.save()
            mihomoViewModel.loadConfig()
            mihomoViewModel.refreshStatus()
            Toast.success(L10n.string("配置已保存"))
        } catch {
            Toast.error(error.localizedDescription)
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
                    .controlSize(.regular)
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
                    .controlSize(.regular)
                    .disabled(isImporting || isExporting)
                }
            }
            .padding(DesignSystem.Spacing.small)
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
                    Toast.success(L10n.format("配置已导出到: %@", url.lastPathComponent))

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

    private func applyImportedData(_ data: KairosExportData) {
        do {
            try SettingsImportService.apply(data)
        } catch {
            Toast.error(error.localizedDescription)
            return
        }

        mihomoViewModel.loadConfig()
        mihomoViewModel.refreshStatus()
        settingsViewModel.reload()

        // A successful import can recover a startup blocked by unreadable scene files.
        networkMonitor.startMonitoring(scenes: data.appControlScenes, dnsScenes: data.dnsControlScenes)
        networkMonitor.updateScenes(data.appControlScenes)
        networkMonitor.updateDNSScenes(data.dnsControlScenes)

        // 清理状态
        importedData = nil

        // 显示成功提示
        Toast.success(L10n.format(
            "已导入 %lld 个场景和 %lld 个 DNS 场景",
            data.appControlScenes.count,
            data.dnsControlScenes.count
        ))

        AppLogger.info("✅ 配置导入完成")
    }

    // MARK: - API Key Settings Section

    private var apiKeySettingsSection: some View {
        @Bindable var settings = settingsViewModel
        return GroupBox {
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
                        value: $settings.apiKeys.ipinfoToken,
                        helpURL: "https://ipinfo.io/signup"
                    )

                    // ipapi.is
                    APIKeyInputRow(
                        label: "ipapi.is",
                        placeholder: "API Key",
                        value: $settings.apiKeys.ipapiKey,
                        helpURL: "https://ipapi.is/"
                    )

                    // DB-IP
                    APIKeyInputRow(
                        label: "DB-IP",
                        placeholder: "API Key",
                        value: $settings.apiKeys.dbipKey,
                        helpURL: "https://db-ip.com/api/"
                    )

                    // IPWHOIS
                    APIKeyInputRow(
                        label: "IPWHOIS",
                        placeholder: "API Key",
                        value: $settings.apiKeys.ipwhoisKey,
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
                        value: $settings.apiKeys.abuseipdbKey,
                        helpURL: "https://www.abuseipdb.com/api"
                    )

                    // IP2Location
                    APIKeyInputRow(
                        label: "IP2Location",
                        placeholder: "API Key",
                        value: $settings.apiKeys.ip2locationKey,
                        helpURL: "https://www.ip2location.io/"
                    )

                    // ipregistry
                    APIKeyInputRow(
                        label: "ipregistry",
                        placeholder: "API Key",
                        value: $settings.apiKeys.ipregistryKey,
                        helpURL: "https://ipregistry.co/"
                    )
                }


            }
            .padding(DesignSystem.Spacing.small)
        }
    }

    private var loggingSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.standard) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.extraSmall) {
                        Text("日志等级")
                        Text("仅记录所选等级及以上的日志，修改后立即生效。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("日志等级", selection: $logSettings.minimumLevel) {
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Text(level.displayName.trimmingCharacters(in: .whitespaces)).tag(level)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.regular)
                    .fixedSize()
                }

                Divider()

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        Text("当前日志文件（打开文件夹后将选中此文件，可使用文本编辑器查看）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(LogStore.shared.logFileURL.lastPathComponent)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Button("打开日志文件", systemImage: "folder") {
                        let url = LogStore.shared.logFileURL
                        if FileManager.default.fileExists(atPath: url.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } else if !NSWorkspace.shared.open(url.deletingLastPathComponent()) {
                            Toast.error(L10n.string("无法打开日志文件夹"))
                        }
                    }
                    .buttonStyle(.glass)
                    .fixedSize()
                }
            }
            .padding(DesignSystem.Spacing.small)
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

                    HStack(alignment: .center, spacing: DesignSystem.Spacing.medium) {
                        Image(systemName: permission.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(Color(permission.statusColor))
                            .font(.system(size: 14))

                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.extraSmall) {
                            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.small) {
                                Text(permission.type.displayName)
                                    .font(.system(size: 14, weight: .medium))
                                Text(permission.statusText)
                                    .font(.caption)
                                    .foregroundStyle(Color(permission.statusColor))
                                    .fixedSize()
                            }
                            Text(permission.isGranted ? permission.type.description : permission.type.guideText)
                                .font(.caption)
                                .foregroundStyle(permission.isGranted ? Color.secondary : Color.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        switch permission.type {
                        case .accessibility:
                            if !permission.isGranted && permission.isRequired {
                                Button("打开设置") {
                                    permissionManager.openAccessibilitySettings()
                                }
                                .buttonStyle(.glassProminent)
                                .controlSize(.regular)
                                .fixedSize()
                            }
                        case .helperTool:
                            HelperActionButton(
                                dnsManager: dnsManager,
                                networkMonitor: networkMonitor,
                                isInstalled: permission.isGranted
                            )
                            .fixedSize()
                        }
                    }
                }
            }
            .padding(DesignSystem.Spacing.small)
        }
    }
}

// MARK: - Helper Action Button

/// Helper 操作按钮组件
///
/// ## 功能
/// - 根据安装状态显示「安装 Helper」或「卸载 Helper」按钮
/// - 在已安装状态下检查 Helper 版本和 XPC 连接
/// - 显示操作进度和结果反馈
/// - 操作成功后自动刷新权限状态
/// - 安装成功后触发 DNS 场景匹配
private struct HelperActionButton: View {
    let dnsManager: DNSManager
    let networkMonitor: NetworkMonitor
    let isInstalled: Bool

    @State private var operation: Operation?

    private enum Operation {
        case install
        case healthCheck
        case uninstall
    }

    var body: some View {
        Group {
            if isInstalled {
                HStack(spacing: DesignSystem.Spacing.small) {
                    Button {
                        checkHelperHealth()
                    } label: {
                        actionLabel("检查 Helper", isActive: operation == .healthCheck)
                    }
                    .buttonStyle(.glass)

                    Button(role: .destructive) {
                        uninstallHelper()
                    } label: {
                        actionLabel("卸载 Helper", isActive: operation == .uninstall)
                    }
                    .buttonStyle(.glass)
                }
            } else {
                Button {
                    installHelper()
                } label: {
                    actionLabel("安装 Helper", isActive: operation == .install)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .controlSize(.regular)
        .disabled(operation != nil)
    }

    @ViewBuilder
    private func actionLabel(_ title: String, isActive: Bool) -> some View {
        if isActive {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 8)
        } else {
            Text(L10n.string(title))
        }
    }

    private func installHelper() {
        operation = .install
        dnsManager.installHelper { success, error in
            DispatchQueue.main.async {
                operation = nil

                if success {
                    Toast.success(L10n.string("DNS Helper 已成功安装"))
                    // 触发 DNS 场景匹配，确保已开启的场景立即生效
                    networkMonitor.refreshDNSSceneMatching()
                } else if dnsManager.helperRequiresApproval {
                    Toast.info(L10n.string("Helper 已注册，请在系统设置的登录项中批准"))
                } else {
                    let message = error?.localizedDescription ?? L10n.string("安装失败，请重试")
                    Toast.error(message)
                }

                // 刷新权限状态
                PermissionManager.shared.refresh()
            }
        }
    }

    private func checkHelperHealth() {
        operation = .healthCheck
        dnsManager.checkHelperHealth { result in
            DispatchQueue.main.async {
                operation = nil

                switch result {
                case .success(let version):
                    Toast.success(L10n.format("Helper 连接正常，版本：%@", version))
                case .failure(let error):
                    Toast.error(error.localizedDescription)
                }

                PermissionManager.shared.refresh()
            }
        }
    }

    private func uninstallHelper() {
        operation = .uninstall
        dnsManager.uninstallHelper { success, error in
            DispatchQueue.main.async {
                operation = nil

                if success {
                    Toast.success(L10n.string("DNS Helper 已成功卸载"))
                } else {
                    let message = error?.localizedDescription ?? L10n.string("卸载失败，请重试")
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
    @State private var isSecure = true

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            HStack(spacing: DesignSystem.Spacing.extraSmall) {
                Text(L10n.string(label))
                    .font(.system(size: 13))
                    .lineLimit(1)

                Button {
                    if let url = URL(string: helpURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.blue)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("获取 API Key"))
                .help("获取 API Key")
            }
            .frame(width: 120, alignment: .leading)

            ClearableSettingsField(placeholder: placeholder, text: $value, isSecure: isSecure)
                .accessibilityLabel(L10n.string(label))

            Button {
                isSecure.toggle()
            } label: {
                Image(systemName: isSecure ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .frame(width: DesignSystem.Input.actionHeight, height: DesignSystem.Input.actionHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSecure ? Text("显示") : Text("隐藏"))
            .help(isSecure ? L10n.string("显示") : L10n.string("隐藏"))
        }
    }
}

private struct ClearableSettingsField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(L10n.string(placeholder), text: $text)
            } else {
                TextField(L10n.string(placeholder), text: $text)
            }
        }
        .padding(.trailing, DesignSystem.Input.actionHeight)
        .kairosTextField()
        .overlay(alignment: .trailing) {
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: DesignSystem.Input.actionHeight, height: DesignSystem.Input.actionHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("清空"))
                .help("清空")
                .padding(.trailing, DesignSystem.Spacing.extraSmall)
            }
        }
    }
}
