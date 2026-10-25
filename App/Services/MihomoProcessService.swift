//
//  MihomoProcessService.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation
import AppKit

/// Mihomo 关联应用的进程服务
///
/// ## 设计说明
/// 不写死任何具体客户端的 bundle identifier，所有方法都接收调用方
/// 传入的 `bundleIdentifier`/`displayName`（来自 `MihomoConfig` 中用户
/// 关联的应用）。若两者均为空（尚未关联应用），则视为"无法判断运行状态"，
/// 直接放行，不阻塞内核操作。
class MihomoProcessService {
    private let runningApplications: () -> [NSRunningApplication]
    private let notificationCenter: NotificationCenter

    init(
        runningApplications: @escaping () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications },
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.runningApplications = runningApplications
        self.notificationCenter = notificationCenter
    }

    // MARK: - 进程检测

    /// 检查关联应用是否正在运行
    /// - Parameters:
    ///   - bundleIdentifier: 关联应用的 Bundle Identifier
    ///   - displayName: 关联应用的显示名称
    /// - Returns: true 表示正在运行，false 表示未运行或尚未关联应用
    func isHostAppRunning(bundleIdentifier: String, displayName: String) -> Bool {
        guard !bundleIdentifier.isEmpty || !displayName.isEmpty else {
            return false
        }

        AppLogger.debug("检查关联应用运行状态: \(displayName)")
        let isRunning = !findRunningHostApps(bundleIdentifier: bundleIdentifier, displayName: displayName).isEmpty

        if isRunning {
            AppLogger.info("关联应用正在运行: \(displayName)")
        } else {
            AppLogger.debug("关联应用未运行: \(displayName)")
        }

        return isRunning
    }


    // MARK: - 应用控制

    /// 请求用户退出关联应用
    ///
    /// 使用 async/await 模式替代阻塞式 `runModal()`
    ///
    /// - Parameters:
    ///   - bundleIdentifier: 关联应用的 Bundle Identifier
    ///   - displayName: 关联应用的显示名称
    /// - Returns: 用户选择的操作（退出或取消）
    func requestQuitHostApp(bundleIdentifier: String, displayName: String) async throws -> Bool {
        AppLogger.info("弹出对话框请求退出关联应用: \(displayName)")

        let alert = NSAlert()
        alert.messageText = L10n.format("%@ 正在运行", displayName)
        alert.informativeText = L10n.format("执行此操作需要先退出 %@，是否继续？", displayName)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.format("退出 %@", displayName))
        alert.addButton(withTitle: L10n.string("取消"))

        // 使用 withCheckedContinuation 将 runModal 包装为 async
        // 注意：runModal 会阻塞当前线程，但在 MainActor 上下文中是安全的
        let response = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let result = alert.runModal()
                continuation.resume(returning: result)
            }
        }

        if response == .alertFirstButtonReturn {
            // 用户选择退出
            AppLogger.info("用户选择退出关联应用: \(displayName)")
            try quitHostApps(bundleIdentifier: bundleIdentifier, displayName: displayName)
            return true
        } else {
            // 用户取消
            AppLogger.info("用户取消退出关联应用: \(displayName)")
            return false
        }
    }

    // A successful request is not termination; the wait below must confirm every instance exits.
    func quitHostApps(bundleIdentifier: String, displayName: String) throws {
        for app in findRunningHostApps(bundleIdentifier: bundleIdentifier, displayName: displayName) {
            guard app.terminate() || app.isTerminated else {
                throw MihomoError.hostAppIsRunning(displayName)
            }
        }
    }

    // MARK: - 事件驱动等待

    /// 等待关联应用退出，使用应用终止通知替代轮询
    /// - Parameters:
    ///   - bundleIdentifier: 关联应用的 Bundle Identifier
    ///   - displayName: 关联应用的显示名称
    ///   - maxWaitTime: 最大等待时间（秒）
    /// - Throws: MihomoError.appQuitTimeout
    func waitForHostAppToQuit(
        bundleIdentifier: String,
        displayName: String,
        maxWaitTime: TimeInterval = 10.0
    ) async throws {
        guard !findRunningHostApps(bundleIdentifier: bundleIdentifier, displayName: displayName).isEmpty else {
            return
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.awaitTerminationNotification(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName
                )
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(maxWaitTime * 1_000_000_000))
                throw MihomoError.appQuitTimeout
            }

            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func awaitTerminationNotification(
        bundleIdentifier: String,
        displayName: String
    ) async throws {
        let workspaceNotificationCenter = notificationCenter
        let waitState = MihomoTerminationWaitState(notificationCenter: workspaceNotificationCenter)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waitState.registerContinuation(continuation)

                let observer = workspaceNotificationCenter.addObserver(
                    forName: NSWorkspace.didTerminateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    guard self.findRunningHostApps(bundleIdentifier: bundleIdentifier, displayName: displayName).isEmpty else {
                        return
                    }

                    AppLogger.info("检测到关联应用已退出: \(displayName)")
                    waitState.finish(.success(()))
                }
                waitState.registerObserver(observer)

                if self.findRunningHostApps(bundleIdentifier: bundleIdentifier, displayName: displayName).isEmpty {
                    waitState.finish(.success(()))
                }
            }
        } onCancel: {
            waitState.finish(.failure(CancellationError()))
        }
    }

    // MARK: - Private Helpers

    private func findRunningHostApps(
        bundleIdentifier: String,
        displayName: String
    ) -> [NSRunningApplication] {
        runningApplications().filter { app in
            !app.isTerminated && Self.matchesHostApp(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                runningBundleIdentifier: app.bundleIdentifier,
                runningDisplayName: app.localizedName
            )
        }
    }

    static func matchesHostApp(
        bundleIdentifier: String,
        displayName: String,
        runningBundleIdentifier: String?,
        runningDisplayName: String?
    ) -> Bool {
        bundleIdentifier.isEmpty
            ? (!displayName.isEmpty && runningDisplayName == displayName)
            : runningBundleIdentifier == bundleIdentifier
    }
}
