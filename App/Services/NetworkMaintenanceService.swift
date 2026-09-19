//
//  NetworkMaintenanceService.swift
//  Kairos
//
//  Created by SlippinDylan on 2026/01/04.
//

import Foundation
import CoreWLAN

/// 网络维护服务
///
/// ## 职责
/// - 提供系统级网络维护工具（DNS缓存清理、网络接口重置等）
/// - 优先使用 Swift 原生 API，最小化外部命令依赖
/// - 将需要 root 权限的固定命令交给 SMAppService LaunchDaemon
///
/// ## 设计说明
/// - **最小 shell 原则**: 只在无原生 API 时使用 shell
/// - **原生 API 优先**:
///   - WiFi 控制 → CoreWLAN.framework
///   - 文件操作 → FileManager
///   - 网络接口刷新 → Helper 中的 SystemConfiguration.framework
/// - **必要的 shell**:
///   - DNS 缓存清理（无公开 API）
///   - ARP 清理（sysctl 过于复杂）
///   - purge（无公开 API）
///
/// ## 架构优势
/// - 类型安全，编译时检查
/// - 错误处理精细
/// - 无进程 fork 开销
/// - 符合 Apple 开发规范
final class NetworkMaintenanceService {

    // MARK: - Error Types

    enum MaintenanceError: LocalizedError {
        case wifiInterfaceNotFound
        case wifiControlFailed(String)
        case wifiRecoveryFailed(operation: String, recovery: String)
        case helperUnavailable

        var errorDescription: String? {
            switch self {
            case .wifiInterfaceNotFound:
                return L10n.string("未找到 WiFi 网卡")
            case .wifiControlFailed(let message):
                return L10n.format("WiFi 控制失败: %@", message)
            case .wifiRecoveryFailed(let operation, let recovery):
                return L10n.format("网络维护失败且 WiFi 恢复失败。维护错误: %@；恢复错误: %@", operation, recovery)
            case .helperUnavailable:
                return L10n.string("DNS Helper 未启用，请先在设置中注册并批准 Helper")
            }
        }
    }

    // MARK: - Initialization

    nonisolated init() {
        // 无状态服务，无需初始化
    }

    // MARK: - Public Methods - Deep Clean

    /// 深度清理
    ///
    /// ## 实现说明（方案 C）
    /// 1. ✅ [Swift] 记录 WiFi 状态，并在开启时暂时关闭
    /// 2. ⚠️ [Helper] 刷新 DNS 缓存（无公开 API）
    /// 3. ⚠️ [Helper] 清除 ARP 缓存
    /// 4. ✅ [Swift] 等待网络维护完成
    /// 5. ✅ [Swift] 恢复 WiFi 原始状态
    /// 6. ✅ [Helper] SystemConfiguration 请求 DHCP 立即刷新
    /// 7. ✅ [Swift] FileManager 清理浏览器缓存
    /// 8. ⚠️ [Helper] 刷新 DNS 并清理非活跃内存
    ///
    /// - Throws: MaintenanceError
    nonisolated func deepClean() async throws {
        AppLogger.info("⚠️ 开始深度清理")

        let helperAvailable = await MainActor.run {
            DNSManager.shared.checkHelperStatus()
            return DNSManager.shared.isHelperInstalled
        }
        guard helperAvailable else {
            throw MaintenanceError.helperUnavailable
        }

        let wifiState = try await prepareWiFiForMaintenance()

        do {
            AppLogger.debug("步骤 2/8: 通过 Helper 清理 DNS 缓存")
            try await DNSManager.shared.flushDNSCacheForMaintenance()

            AppLogger.debug("步骤 3/8: 通过 Helper 清除 ARP 缓存")
            try await DNSManager.shared.clearARPCache()
            RouterInfoService.shared.clearMACCache()

            AppLogger.debug("步骤 4/8: 等待 2 秒")
            try await Task.sleep(nanoseconds: 2_000_000_000)
        } catch {
            let operationError = error
            do {
                try await restoreWiFiIfNeeded(wifiState)
            } catch {
                throw MaintenanceError.wifiRecoveryFailed(
                    operation: operationError.localizedDescription,
                    recovery: error.localizedDescription
                )
            }
            throw operationError
        }

        AppLogger.debug("步骤 5/8: 恢复 WiFi 原始状态（CoreWLAN）")
        try await restoreWiFiIfNeeded(wifiState)

        if wifiState.wasPoweredOn {
            AppLogger.debug("步骤 6/8: 通过 Helper 刷新网络接口")
            try await DNSManager.shared.refreshNetworkInterface(wifiState.interfaceName)
        } else {
            AppLogger.debug("步骤 6/8: WiFi 原本已关闭，跳过网络接口刷新")
        }

        // 7. ✅ [Swift] 清理浏览器缓存（FileManager）
        AppLogger.debug("步骤 7/8: 清理浏览器缓存（FileManager）")
        await clearBrowserCaches()

        // 8. ⚠️ [Shell] 再次刷新 DNS + 清理系统缓存（无原生 API）
        AppLogger.debug("步骤 8/8: 通过 Helper 执行最终清理")
        try await DNSManager.shared.flushDNSCacheForMaintenance()
        try await DNSManager.shared.purgeInactiveMemory()

        AppLogger.info("✅ 深度清理完成")
    }

    // MARK: - Private Methods - WiFi Control (CoreWLAN)

    /// 关闭 WiFi（使用 CoreWLAN.framework）
    ///
    /// ## 实现说明
    /// - 使用 CWWiFiClient 获取 WiFi 接口
    /// - 调用 setPower(false) 关闭
    ///
    /// - Throws: MaintenanceError.wifiInterfaceNotFound, MaintenanceError.wifiControlFailed
    private struct WiFiState: Sendable {
        let interfaceName: String
        let wasPoweredOn: Bool
    }

    private nonisolated func prepareWiFiForMaintenance() async throws -> WiFiState {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let client = CWWiFiClient.shared()

                guard let interface = client.interface(),
                      let interfaceName = interface.interfaceName else {
                    continuation.resume(throwing: MaintenanceError.wifiInterfaceNotFound)
                    return
                }

                let wasPoweredOn = interface.powerOn()
                guard wasPoweredOn else {
                    AppLogger.debug("WiFi 原本已关闭: \(interfaceName)")
                    continuation.resume(
                        returning: WiFiState(interfaceName: interfaceName, wasPoweredOn: false)
                    )
                    return
                }

                do {
                    try interface.setPower(false)
                    AppLogger.debug("WiFi 已关闭: \(interfaceName)")
                    continuation.resume(
                        returning: WiFiState(interfaceName: interfaceName, wasPoweredOn: true)
                    )
                } catch {
                    continuation.resume(throwing: MaintenanceError.wifiControlFailed(error.localizedDescription))
                }
            }
        }
    }

    /// 开启 WiFi（使用 CoreWLAN.framework）
    ///
    /// - Throws: MaintenanceError.wifiInterfaceNotFound, MaintenanceError.wifiControlFailed
    private nonisolated func restoreWiFiIfNeeded(_ state: WiFiState) async throws {
        guard state.wasPoweredOn else { return }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let client = CWWiFiClient.shared()

                guard let interface = client.interface(withName: state.interfaceName) else {
                    continuation.resume(throwing: MaintenanceError.wifiInterfaceNotFound)
                    return
                }

                do {
                    try interface.setPower(true)
                    AppLogger.debug("WiFi 已恢复: \(state.interfaceName)")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: MaintenanceError.wifiControlFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Private Methods - Browser Cache (FileManager)

    /// 清理浏览器缓存（使用 FileManager）
    ///
    /// ## 实现说明
    /// - Chrome 缓存路径: ~/Library/Caches/Google/Chrome/Default/Cache
    /// - Firefox 缓存路径: ~/Library/Caches/Firefox/Profiles/*/cache2
    ///
    /// ## 优势
    /// - 完全原生，无需 shell
    /// - 精细的错误处理
    /// - 线程安全
    private nonisolated func clearBrowserCaches() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let fileManager = FileManager.default

                // 清理 Chrome 缓存
                let chromeCachePath = fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Caches/Google/Chrome/Default/Cache")
                if fileManager.fileExists(atPath: chromeCachePath.path) {
                    do {
                        try fileManager.removeItem(at: chromeCachePath)
                        AppLogger.debug("✅ Chrome 缓存已清理")
                    } catch {
                        AppLogger.warning("Chrome 缓存清理失败: \(error.localizedDescription)")
                    }
                }

                // 清理 Firefox 缓存
                let firefoxCachePath = fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Caches/Firefox/Profiles")
                if fileManager.fileExists(atPath: firefoxCachePath.path) {
                    if let enumerator = fileManager.enumerator(at: firefoxCachePath, includingPropertiesForKeys: nil) {
                        for case let fileURL as URL in enumerator {
                            if fileURL.lastPathComponent == "cache2" {
                                do {
                                    try fileManager.removeItem(at: fileURL)
                                    AppLogger.debug("✅ Firefox 缓存已清理: \(fileURL.path)")
                                } catch {
                                    AppLogger.warning("Firefox 缓存清理失败: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                }

                continuation.resume()
            }
        }
    }

}
