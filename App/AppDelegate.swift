//
//  AppDelegate.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/31.
//

import AppKit
import SwiftUI

/// Owns app-scoped services and the retained menu-bar interface.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    /// App-scoped Sparkle controller. The privileged Helper remains independently managed.
    private let applicationUpdater = ApplicationUpdateController.shared

    /// Shared services live as long as the retained menu-bar interface.
    private let networkMonitor = NetworkMonitor()
    private let mihomoViewModel = MihomoViewModel()
    private let settingsViewModel = SettingsViewModel()
    private let networkToolsViewModel = NetworkToolsViewModel()

    private var statusBarController: StatusBarController?

    private func startNetworkMonitoring() {
        Task { @MainActor in
            do {
                let scenes = try SceneStorage.loadScenes()
                let dnsScenes = try DNSSceneStorage.shared.loadScenes()
                networkMonitor.startMonitoring(scenes: scenes, dnsScenes: dnsScenes)
            } catch {
                AppLogger.error("加载场景失败，网络自动化未启动", error: error)
                Toast.error(error.localizedDescription)
            }
        }
    }

    // MARK: - Application Lifecycle

    /// 应用启动完成
    ///
    /// - Parameter notification: 启动通知
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.info("应用启动完成")
        NSApp.setActivationPolicy(.accessory)
        let statusBarController = StatusBarController(
            onShowTab: { tab in
                if let tab {
                    WindowCoordinator.shared.showMainWindow(tab: tab)
                } else {
                    WindowCoordinator.shared.toggleMainWindow()
                }
            },
            onHide: { WindowCoordinator.shared.hideMainWindow() },
            onQuit: { [weak self] in
                self?.requestExplicitQuit()
            }
        )
        self.statusBarController = statusBarController
        let content = ContentView()
            .environment(networkMonitor)
            .environment(mihomoViewModel)
            .environment(settingsViewModel)
            .environment(networkToolsViewModel)
            .environment(WindowCoordinator.shared)
        WindowCoordinator.shared.configurePopover(
            contentViewController: PopoverContentViewController(rootView: content),
            anchor: statusBarController.button
        )
        startNetworkMonitoring()
        _ = applicationUpdater
        DNSManager.shared.validateHelperIfNeeded()

        // 必须在主线程同步配置，确保代理提早设置完毕
        NotificationManager.shared.configure()

        Task { @MainActor in
            // 请求通知权限
            let granted = await NotificationManager.shared.requestAuthorization()
            if granted {
                AppLogger.info("通知权限请求成功")
            } else {
                AppLogger.warning("通知权限请求被拒绝")
            }
        }

        // 检测是否为开机自启动
        if wasLaunchedAsLoginItem() {
            AppLogger.info("应用通过开机自启动启动，保持菜单栏界面收起")
            // Login launch starts services without opening the interface.
            WindowCoordinator.shared.requestHide()
        } else {
            AppLogger.info("应用手动启动，展开菜单栏界面")
            // The popover and its retained content are ready before this request.
            WindowCoordinator.shared.requestShow(tab: 0)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowCoordinator.shared.showMainWindow()
        return false
    }

    /// 最后一个窗口关闭时是否退出应用
    ///
    /// - Parameter sender: NSApplication 实例
    /// - Returns: false - 不退出应用，只隐藏窗口
    ///
    /// 这是核心逻辑：关闭窗口时，应用继续在菜单栏运行
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        AppLogger.info("最后一个窗口已关闭，隐藏窗口但不退出应用")
        return false
    }

    /// 应用即将退出
    ///
    /// - Parameter notification: 退出通知
    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.info("应用即将退出")
        ApplicationRelaunchController.shared.relaunchIfRequested()
    }

    // MARK: - Private Methods

    /// 检测应用是否通过开机自启动启动
    ///
    /// - Returns: true 表示开机自启动，false 表示手动启动
    ///
    /// 技术实现：
    /// - 通过 Apple Event 检测启动来源
    /// - kAEOpenApplication + keyAELaunchedAsLogInItem 表示开机自启动
    private func wasLaunchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }

        let isLoginItem = event.eventID == kAEOpenApplication &&
                         event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem

        return isLoginItem
    }

    private func requestExplicitQuit() {
        NSApp.terminate(nil)
    }
}
