//
//  ContentView.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

struct ContentView: View {
    // MARK: - Environment Objects

    /// 网络监控服务（从 KairosApp 注入）
    ///
    /// ## 架构说明
    /// - 使用 @Environment 接收从 KairosApp 注入的实例
    /// - 不再在此创建 NetworkMonitor（避免重复实例）
    /// - 整个应用共享同一个 NetworkMonitor 实例
    @Environment(NetworkMonitor.self) var networkMonitor

    /// 窗口协调器（从 KairosApp 注入）
    ///
    /// ## 架构说明
    /// - 使用 @Environment 接收从 KairosApp 注入的实例
    /// - 管理窗口状态和 Tab 切换
    /// - 替代原 AppCoordinator，解决 P1-2 架构问题
    @Environment(WindowCoordinator.self) var windowCoordinator

    // MARK: - Global Coordinator

    /// 绑定全局状态协调器
    /// 从菜单栏点击时，WindowCoordinator.selectedTab 会更新，驱动此处的 Tab 切换
    private var selectedTab: Binding<Int> {
        Binding(
            get: { windowCoordinator.selectedTab },
            set: { windowCoordinator.selectedTab = $0 }
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            NavigationSidebar(selectedTab: selectedTab)
                .navigationSplitViewColumnWidth(min: 210, ideal: 210, max: 210)
        } detail: {
            GeometryReader { proxy in
                selectedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(
                        .top,
                        usesWindowToolbar
                            ? 0
                            : DesignSystem.Spacing.small - proxy.safeAreaInsets.top
                    )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minHeight: 720)
        .buttonBorderShape(.capsule)
        .toolbar(removing: .title)
        .toolbar(removing: .sidebarToggle)
        .toolbarBackgroundVisibility(
            usesWindowToolbar ? .visible : .hidden,
            for: .windowToolbar
        )
        .overlay(alignment: .top) {
            // 全局 Toast 提示（在 Toolbar 下方显示）
            ToastOverlay()
                .padding(.top, 8)
        }
        .overlay {
            // 退出确认提示（居中显示）
            QuitConfirmationOverlay()
        }
        .onAppear {
            // ✅ 设置窗口 identifier（用于 MenuBarView 查找窗口）
            // 必须在窗口创建后设置，所以放在 onAppear 中
            if let window = NSApp.keyWindow {
                window.identifier = NSUserInterfaceItemIdentifier("main")
                AppLogger.debug("主窗口 identifier 已设置: main")
            } else {
                AppLogger.warning("未找到 keyWindow，尝试从所有窗口查找")
                // 备用方案：查找所有窗口中最后创建的窗口
                if let window = NSApp.windows.last {
                    window.identifier = NSUserInterfaceItemIdentifier("main")
                    AppLogger.debug("主窗口 identifier 已设置（通过 windows.last）: main")
                }
            }
        }
    }

    private var usesWindowToolbar: Bool {
        switch selectedTab.wrappedValue {
        case 3, 5:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab.wrappedValue {
        case 0:
            NetworkMonitorView()
        case 1:
            NetworkToolsView()
        case 2:
            MihomoView()
        case 3:
            LogView()
        case 4:
            SettingsView()
        case 5:
            AboutView()
        default:
            NetworkMonitorView()
        }
    }
}

#Preview {
    ContentView()
        .environment(NetworkMonitor())
        .environment(MihomoViewModel())
        .environment(WindowCoordinator.forPreview())
}
