//
//  NetworkMonitorView.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

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

    @State private var sceneLoadError: String?

    let sceneType: SceneType

    // MARK: - Body

    var body: some View {
        Group {
            if showingAppSceneSheet {
                SceneConfigSheet(
                    scene: $editingAppScene,
                    isEditing: editingAppScene != nil,
                    onCancel: {
                        showingAppSceneSheet = false
                        windowCoordinator.resetContentSize()
                    },
                    onSave: { newScene in
                        var updated = appScenes
                        if let index = updated.firstIndex(where: { $0.id == newScene.id }) {
                            updated[index] = newScene
                        } else {
                            updated.append(newScene)
                        }
                        try persistAppScenes(updated)
                    }
                )
            } else if showingDNSSceneSheet {
                DNSSceneConfigSheet(
                    scene: editingDNSScene,
                    onCancel: {
                        showingDNSSceneSheet = false
                        windowCoordinator.resetContentSize()
                    },
                    onSave: { newScene in
                        var updated = dnsScenes
                        if let index = updated.firstIndex(where: { $0.id == newScene.id }) {
                            updated[index] = newScene
                        } else {
                            updated.append(newScene)
                        }
                        try persistDNSScenes(updated)
                    }
                )
            } else {
                overview
            }
        }
        .onAppear {
            windowCoordinator.resetContentSize()
            loadScenes()
            refreshCurrentDNS()
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

    private var overview: some View {
        KairosScrollView {
            VStack(alignment: .leading, spacing: 20) {
                currentNetworkGroupBox

                if let sceneLoadError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sceneLoadError).foregroundStyle(.red).textSelection(.enabled)
                        Button("重试", action: loadScenes)
                    }
                } else {
                    sceneList
                }
            }
            .padding(DesignSystem.Spacing.standard)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PopoverNavigationBar {
                Button("添加", systemImage: "plus") {
                    if sceneType == .appControl {
                        editingAppScene = nil
                        showingAppSceneSheet = true
                    } else {
                        editingDNSScene = nil
                        showingDNSSceneSheet = true
                    }
                }
                .labelStyle(.iconOnly)
                .help("添加")
                .buttonBorderShape(.circle)
                .disabled(sceneLoadError != nil)
            }
        }
    }

    // MARK: - GroupBox 1: 网络概要

    /// 当前网络信息卡片
    private var currentNetworkGroupBox: some View {
        OverviewCard {
            HStack(alignment: .top, spacing: 12) {
                networkMetric(title: "网络名称", value: currentNetworkName, symbol: "network")
                Divider().padding(.vertical, 4)
                networkMetric(title: "网关 IP", value: networkMonitor.currentRouterIP, symbol: "point.3.connected.trianglepath.dotted")
                Divider().padding(.vertical, 4)
                if sceneType == .appControl {
                    networkMetric(title: "网关 MAC", value: networkMonitor.currentRouterMAC, symbol: "cable.connector")
                } else {
                    networkMetric(title: "DNS", value: currentDNSDescription, symbol: "server.rack")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func networkMetric(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
                Text(L10n.string(title))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentNetworkName: String {
        guard !networkMonitor.activeNetworks.isEmpty else { return "-" }
        return networkMonitor.activeNetworks.map(\.displayName).joined(separator: " · ")
    }

    private var currentDNSDescription: String {
        let servers = [dnsManager.currentPrimaryDNS, dnsManager.currentSecondaryDNS]
            .filter { $0 != "-" }
        return servers.isEmpty ? "-" : servers.joined(separator: " · ")
    }

    // MARK: - 场景列表

    /// 场景列表（根据选择显示不同类型）
    private var sceneList: some View {
        Group {
            if sceneType == .appControl {
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
                    ForEach(appScenes) { scene in
                        SceneCard(
                            scene: Binding(get: { scene }, set: { updatedScene in
                                let updated = appScenes.map { $0.id == updatedScene.id ? updatedScene : $0 }
                                saveWithFeedback { try persistAppScenes(updated) }
                            }),
                            isMatched: scene.isEnabled && networkMonitor.matchedScenes.contains { $0.id == scene.id },
                            onEdit: {
                                editingAppScene = scene
                                showingAppSceneSheet = true
                            },
                            onDelete: {
                                saveWithFeedback { try persistAppScenes(appScenes.filter { $0.id != scene.id }) }
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
                    ForEach(dnsScenes) { scene in
                        DNSSceneCard(
                            scene: Binding(get: { scene }, set: { updatedScene in
                                let updated = dnsScenes.map { $0.id == updatedScene.id ? updatedScene : $0 }
                                saveWithFeedback { try persistDNSScenes(updated) }
                            }),
                            isMatched: scene.isEnabled && networkMonitor.currentMatchedDNSScene?.id == scene.id,
                            onEdit: {
                                editingDNSScene = scene
                                showingDNSSceneSheet = true
                            },
                            onDelete: {
                                saveWithFeedback { try persistDNSScenes(dnsScenes.filter { $0.id != scene.id }) }
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
        [GridItem(.flexible())]
    }

    /// Read both lists before publishing either one to automation.
    private func loadScenes() {
        do {
            let loadedApps = try SceneStorage.loadScenes()
            let loadedDNS = try DNSSceneStorage.shared.loadScenes()
            appScenes = loadedApps
            dnsScenes = loadedDNS
            sceneLoadError = nil
            networkMonitor.startMonitoring(scenes: loadedApps, dnsScenes: loadedDNS)
            networkMonitor.updateScenes(loadedApps)
            networkMonitor.updateDNSScenes(loadedDNS)
        } catch {
            sceneLoadError = error.localizedDescription
        }
    }

    private func persistAppScenes(_ updated: [NetworkScene]) throws {
        try SceneStorage.saveScenes(updated)
        appScenes = updated
        networkMonitor.updateScenes(updated)
    }

    private func persistDNSScenes(_ updated: [DNSScene]) throws {
        try DNSSceneStorage.shared.saveScenes(updated)
        dnsScenes = updated
        networkMonitor.updateDNSScenes(updated)
    }

    private func saveWithFeedback(_ save: () throws -> Void) {
        do { try save() } catch { Toast.error(error.localizedDescription) }
    }

    /// 刷新当前DNS配置
    private func refreshCurrentDNS() {
        guard let firstNetwork = networkMonitor.activeNetworks.first else {
            return
        }
        dnsManager.getCurrentDNS(interface: firstNetwork.displayName) { _ in }
    }
}
