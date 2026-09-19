//
//  NetworkMonitorView.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

/// 网络控制视图（重构版）
///
/// ## 架构说明
/// - GroupBox 1: 网络概要 - 展示网络名称、网关 IP、网关 MAC 和 DNS
/// - GroupBox 2: 应用控制 - 展示应用控制的当前状态（匹配场景、控制应用）
/// - GroupBox 3: DNS控制 - 展示DNS控制的当前状态（匹配场景、DNS）
/// - Picker + 添加场景按钮（不在GroupBox内）
/// - 场景列表 - 根据Picker选择显示应用控制或DNS控制场景列表
///
/// ## 数据流
/// - 应用控制场景：NetworkScene -> SceneStorage -> NetworkMonitor.updateScenes()
/// - DNS控制场景：DNSScene -> DNSSceneStorage -> NetworkMonitor.updateDNSScenes()
struct NetworkMonitorView: View {
    // MARK: - Environment

    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(WindowCoordinator.self) private var windowCoordinator

    // MARK: - State

    /// 场景类型枚举
    enum SceneType {
        case appControl   // 应用控制
        case dnsControl   // DNS控制
    }

    // 应用控制场景
    @State private var appScenes: [NetworkScene] = []
    @State private var showingAppSceneSheet = false
    @State private var editingAppScene: NetworkScene?

    // DNS控制场景
    @State private var dnsScenes: [DNSScene] = []
    @State private var dnsManager = DNSManager.shared
    @State private var showingDNSSceneSheet = false
    @State private var editingDNSScene: DNSScene?
    @State private var showHelperNotInstalledAlert = false

    // 场景类型选择
    @State private var selectedSceneType: SceneType = .appControl

    // MARK: - Body

    var body: some View {
        KairosScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // GroupBox 1: 网络概要
                currentNetworkGroupBox

                automationStatusCard

                // Picker + 添加场景按钮（不在GroupBox内）
                sceneTypeSelector

                // 场景列表（每个场景独立显示为卡片）
                sceneList
            }
            .padding(DesignSystem.Spacing.standard)
        }
        .navigationTitle(L10n.string("网络控制"))
        .navigationSubtitle(L10n.string("page.networkControl.description"))
        .sheet(isPresented: $showingAppSceneSheet) {
            SceneConfigSheet(
                scene: $editingAppScene,
                isEditing: editingAppScene != nil,
                onSave: { newScene in
                    if let index = appScenes.firstIndex(where: { $0.id == newScene.id }) {
                        appScenes[index] = newScene
                    } else {
                        appScenes.append(newScene)
                    }
                    networkMonitor.updateScenes(appScenes)
                }
            )
        }
        .sheet(isPresented: $showingDNSSceneSheet) {
            DNSSceneConfigSheet(
                scene: editingDNSScene,
                onSave: { newScene in
                    if let index = dnsScenes.firstIndex(where: { $0.id == newScene.id }) {
                        dnsScenes[index] = newScene
                    } else {
                        dnsScenes.append(newScene)
                    }
                    saveDNSScenes()
                }
            )
        }
        .onAppear {
            loadScenes()
            refreshCurrentDNS()
        }
        .onChange(of: appScenes) { _, _ in
            SceneStorage.saveScenes(appScenes)
            networkMonitor.updateScenes(appScenes)
        }
        .onChange(of: dnsScenes) { _, _ in
            saveDNSScenes()
        }
        .alert("Helper 未安装", isPresented: $showHelperNotInstalledAlert) {
            Button("前往设置") {
                windowCoordinator.selectedTab = 4
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("DNS 管理功能需要安装 Helper Tool，请前往设置页面安装。")
        }
    }

    // MARK: - GroupBox 1: 网络概要

    /// 当前网络信息卡片
    private var currentNetworkGroupBox: some View {
        OverviewCard {
            HStack(spacing: 0) {
                OverviewMetric(
                    title: "网络名称",
                    value: currentNetworkName,
                    icon: .symbol("wifi", .blue)
                )

                OverviewMetricDivider()

                OverviewMetric(
                    title: "网关 IP",
                    value: networkMonitor.currentRouterIP,
                    icon: .symbol("network", .blue)
                )

                OverviewMetricDivider()

                OverviewMetric(
                    title: "网关 MAC",
                    value: networkMonitor.currentRouterMAC,
                    icon: .symbol("point.3.connected.trianglepath.dotted", .blue)
                )

                OverviewMetricDivider()

                OverviewMetric(
                    title: "DNS",
                    value: currentDNSDescription,
                    icon: .symbol("server.rack", hasCurrentDNS ? .green : .secondary)
                )
            }
        }
    }

    private var currentNetworkName: String {
        guard !networkMonitor.activeNetworks.isEmpty else { return "-" }
        return networkMonitor.activeNetworks.map(\.displayName).joined(separator: " · ")
    }

    private var hasCurrentDNS: Bool {
        dnsManager.currentPrimaryDNS != "-" || dnsManager.currentSecondaryDNS != "-"
    }

    private var currentDNSDescription: String {
        let servers = [dnsManager.currentPrimaryDNS, dnsManager.currentSecondaryDNS]
            .filter { $0 != "-" }
        return servers.isEmpty ? "-" : servers.joined(separator: " · ")
    }

    // MARK: - Automation Status

    private var automationStatusCard: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 0) {
                automationStatusColumn(
                    title: "应用控制",
                    icon: "app.fill",
                    color: .blue
                ) {
                    appControlStatusContent
                }

                Divider()
                    .padding(.horizontal, DesignSystem.Spacing.standard)

                automationStatusColumn(
                    title: "DNS 控制",
                    icon: "server.rack",
                    color: .green
                ) {
                    dnsControlStatusContent
                }
            }
            .padding(DesignSystem.Spacing.standard)
        }
    }

    private func automationStatusColumn<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            SectionHeader(title: title, icon: icon, iconColor: color)

            Divider()

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var appControlStatusContent: some View {
        VStack(alignment: .leading, spacing: 12) {
                // 匹配场景
                HStack {
                    Text("匹配场景")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if networkMonitor.matchedScenes.isEmpty {
                        Text("-")
                            .fontWeight(.medium)
                    } else {
                        HStack(spacing: 6) {
                            ForEach(networkMonitor.matchedScenes) { scene in
                                Text(scene.name)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.purple.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                            }
                        }
                    }
                }
                .frame(height: 32)

                Divider()

                // 控制应用
                HStack(alignment: .top) {
                    Text("控制应用")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if allControlApps.isEmpty {
                        Text("-")
                            .fontWeight(.medium)
                    } else {
                        HStack(spacing: 6) {
                            ForEach(allControlApps, id: \.self) { app in
                                HStack(spacing: 3) {
                                    if let icon = getAppIcon(appName: app) {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Image(systemName: "app.fill")
                                            .foregroundStyle(.blue)
                                    }
                                    Text(app)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                            }
                        }
                    }
                }
                .frame(height: 32)
        }
    }

    private var dnsControlStatusContent: some View {
        VStack(alignment: .leading, spacing: 12) {
                // 匹配场景（移到上面）
                HStack {
                    Text("匹配场景")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let matchedScene = currentMatchedDNSScene {
                        Text(matchedScene.name)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.purple.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                    } else {
                        Text("-")
                            .fontWeight(.medium)
                    }
                }
                .frame(height: 32)

                Divider()

                // DNS（显示匹配场景配置的 DNS，而非系统当前 DNS）
                HStack {
                    Text("DNS")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let matchedScene = currentMatchedDNSScene {
                        HStack(spacing: 6) {
                            // 主 DNS
                            HStack(spacing: 4) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.green)
                                Text(matchedScene.primaryDNS)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))

                            // 备用 DNS
                            if !matchedScene.secondaryDNS.isEmpty {
                                Text(matchedScene.secondaryDNS)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.green.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                            }
                        }
                    } else {
                        Text("-")
                            .fontWeight(.medium)
                    }
                }
                .frame(height: 32)
        }
    }

    // MARK: - Scene Type Selector (不在GroupBox内)

    /// 场景类型选择器（Picker + 添加场景按钮）
    private var sceneTypeSelector: some View {
        HStack {
            Picker("", selection: $selectedSceneType) {
                Text("应用控制").tag(SceneType.appControl)
                Text("DNS控制").tag(SceneType.dnsControl)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            Button("添加场景") {
                if selectedSceneType == .appControl {
                    editingAppScene = nil
                    showingAppSceneSheet = true
                } else {
                    editingDNSScene = nil
                    showingDNSSceneSheet = true
                }
            }
            .buttonStyle(.glassProminent)
        }
    }

    // MARK: - 场景列表

    /// 场景列表（根据选择显示不同类型）
    private var sceneList: some View {
        Group {
            if selectedSceneType == .appControl {
                appSceneList
            } else {
                dnsSceneList
            }
        }
    }

    /// 应用控制场景列表
    private var appSceneList: some View {
        Group {
            if appScenes.isEmpty {
                Text("暂无配置的场景")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: sceneGridColumns, spacing: 12) {
                    ForEach($appScenes) { $scene in
                        SceneCard(
                            scene: $scene,
                            onEdit: {
                                editingAppScene = scene
                                showingAppSceneSheet = true
                            },
                            onDelete: {
                                appScenes.removeAll { $0.id == scene.id }
                            }
                        )
                    }
                }
            }
        }
    }

    /// DNS控制场景列表
    private var dnsSceneList: some View {
        Group {
            if dnsScenes.isEmpty {
                Text("暂无配置的场景")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: sceneGridColumns, spacing: 12) {
                    ForEach($dnsScenes) { $scene in
                        DNSSceneCard(
                            scene: $scene,
                            onEdit: {
                                editingDNSScene = scene
                                showingDNSSceneSheet = true
                            },
                            onDelete: {
                                dnsScenes.removeAll { $0.id == scene.id }
                                saveDNSScenes()
                            },
                            onHelperNotInstalled: {
                                showHelperNotInstalledAlert = true
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Helper Methods

    private var sceneGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: DesignSystem.Spacing.medium),
            GridItem(.flexible())
        ]
    }

    /// 计算所有匹配场景的控制应用（去重）
    private var allControlApps: [String] {
        var apps: [String] = []
        for scene in networkMonitor.matchedScenes {
            for app in scene.controlApps {
                if !apps.contains(app) {
                    apps.append(app)
                }
            }
        }
        return apps
    }

    /// 当前匹配的DNS场景
    private var currentMatchedDNSScene: DNSScene? {
        dnsScenes.first { scene in
            scene.isEnabled &&
            scene.routerIP == networkMonitor.currentRouterIP &&
            scene.routerMAC.lowercased() == networkMonitor.currentRouterMAC.lowercased()
        }
    }

    /// 获取应用图标
    private func getAppIcon(appName: String) -> NSImage? {
        let workspace = NSWorkspace.shared
        let appPath = workspace.urlForApplication(withBundleIdentifier: "com.apple.\(appName)") ??
                      workspace.urlForApplication(withBundleIdentifier: appName) ??
                      URL(fileURLWithPath: "/Applications/\(appName).app")

        return workspace.icon(forFile: appPath.path)
    }

    /// 加载所有场景
    private func loadScenes() {
        // 加载应用控制场景
        appScenes = SceneStorage.loadScenes()
        networkMonitor.updateScenes(appScenes)

        // 加载DNS控制场景
        dnsScenes = DNSSceneStorage.shared.loadScenes()
        networkMonitor.updateDNSScenes(dnsScenes)
    }

    /// 保存DNS场景
    private func saveDNSScenes() {
        DNSSceneStorage.shared.saveScenes(dnsScenes)
        networkMonitor.updateDNSScenes(dnsScenes)
    }

    /// 刷新当前DNS配置
    private func refreshCurrentDNS() {
        guard let firstNetwork = networkMonitor.activeNetworks.first else {
            return
        }
        dnsManager.getCurrentDNS(interface: firstNetwork.displayName) { _ in }
    }
}
