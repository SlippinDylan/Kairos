//
//  MenuBarView.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/31.
//

import SwiftUI

/// 菜单栏视图
///
/// 设计规范：
/// - 符合 macOS 26 Liquid Glass 设计语言
/// - 使用 SF Symbols 图标（优先符号而非文字）
/// - 退出支持 Cmd+Q 快捷键
///
/// 菜单结构：
/// - 功能菜单项（3个）
/// - 退出按钮
///
/// ## 架构职责（重构版）
/// - 响应 WindowCoordinator 的状态变化，执行窗口操作
/// - 实现窗口单例模式（防止创建多个窗口）
/// - 管理窗口的显示/隐藏逻辑
struct MenuBarView: View {
    // MARK: - Environment

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(WindowCoordinator.self) private var windowCoordinator

    var body: some View {
        VStack(spacing: 0) {
            functionalMenuItems

            Divider()
                .padding(.vertical, 4)

            quitButton
        }
        .padding(8)
        .frame(minWidth: 220)
        .onAppear {
            // ✅ 关键修复：检查并处理应用启动时的待处理窗口请求
            // 解决 AppDelegate.applicationDidFinishLaunching 在 MenuBarView 挂载前调用 requestShow 的时序问题
            if windowCoordinator.hasPendingShowRequest {
                AppLogger.info("MenuBarView.onAppear: 检测到待处理的窗口请求，执行显示")
                handleShowWindow()
            }
        }
        .onChange(of: windowCoordinator.shouldShowWindow) { _, shouldShow in
            if shouldShow {
                handleShowWindow()
            }
        }
        .onChange(of: windowCoordinator.shouldHideWindow) { _, shouldHide in
            if shouldHide {
                handleHideWindow()
            }
        }
    }

    // MARK: - Functional Menu Items

    /// 功能菜单项（3个功能入口）
    private var functionalMenuItems: some View {
        Group {
            MenuButton(
                title: "网络控制",
                systemImage: "globe",
                tab: 0
            )

            MenuButton(
                title: "网络工具",
                systemImage: "wrench.and.screwdriver",
                tab: 1
            )

            MenuButton(
                title: "Mihomo",
                systemImage: "shippingbox",
                tab: 2
            )
        }
    }

    // MARK: - Quit Button

    /// 退出按钮（直接退出）
    private var quitButton: some View {
        Button {
            AppLogger.info("用户从菜单栏退出应用")
            NSApp.terminate(nil)
        } label: {
            Label("退出", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    // MARK: - Window Management

    /// 处理显示窗口请求
    ///
    /// ## 实现说明
    /// 1. 查找已存在的主窗口
    /// 2. 如果存在 → 前置窗口并切换 Tab
    /// 3. 如果不存在 → 创建新窗口（首次调用）
    /// 4. 重置触发标志
    private func handleShowWindow() {
        AppLogger.debug("MenuBarView 处理显示窗口请求")

        // 1. 查找已存在的主窗口
        if let existingWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            // 2. 窗口已存在 → 前置窗口
            AppLogger.info("主窗口已存在，前置到最前面")
            existingWindow.makeKeyAndOrderFront(nil)
        } else {
            // 3. 窗口不存在 → 创建新窗口
            AppLogger.info("主窗口不存在，创建新窗口")
            openWindow(id: "main")
        }

        // 4. 重置触发标志
        windowCoordinator.resetFlags()
    }

    /// 处理隐藏窗口请求
    ///
    /// ## 实现说明
    /// 1. 关闭主窗口（通过 dismissWindow）
    /// 2. 重置触发标志
    private func handleHideWindow() {
        AppLogger.debug("MenuBarView 处理隐藏窗口请求")

        // 1. 关闭主窗口
        dismissWindow(id: "main")

        // 2. 重置触发标志
        windowCoordinator.resetFlags()
    }
}

// MARK: - Menu Button

/// 菜单按钮组件
///
/// 职责：
/// - 显示功能入口
/// - 处理点击事件：请求显示窗口并切换 Tab
private struct MenuButton: View {
    let title: String
    let systemImage: String
    let tab: Int

    @Environment(WindowCoordinator.self) private var windowCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            AppLogger.info("菜单栏点击：\(title)")

            // 直接使用 AppKit 唤醒，消除状态驱动带来的延迟
            NSApp.activate(ignoringOtherApps: true)

            if let existingWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                existingWindow.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "main")
            }

            windowCoordinator.switchTab(tab)
        } label: {
            Label(L10n.string(title), systemImage: systemImage)
        }
    }
}

// MARK: - Preview

#Preview {
    MenuBarView()
        .environment(WindowCoordinator.shared)
}
