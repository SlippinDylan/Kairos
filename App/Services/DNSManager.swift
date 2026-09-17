//
//  DNSManager.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/26.
//

import Foundation
import Observation
import ServiceManagement
import SystemConfiguration

/// Manages the SMAppService LaunchDaemon and DNS operations exposed over XPC.
@MainActor
@Observable
final class DNSManager {
    static let shared = DNSManager()

    var currentPrimaryDNS: String = "-"
    var currentSecondaryDNS: String = "-"
    var isHelperInstalled = false

    private let helperIdentifier = "studio.slippindylan.BrewKit.Kairos.helper"
    private let daemonPlistName = "studio.slippindylan.BrewKit.Kairos.helper.plist"
    private let helperCodeSigningRequirement = "identifier \"studio.slippindylan.BrewKit.Kairos.helper\" and anchor apple generic and certificate leaf[subject.CN] = \"Apple Development: slippindylan@sent.com (K7623V57QS)\" and certificate 1[field.1.2.840.113635.100.6.2.1] exists"
    private var helperConnection: NSXPCConnection?
    private var helperHealthCheckID: UUID?

    private var helperService: SMAppService {
        .daemon(plistName: daemonPlistName)
    }

    var helperRequiresApproval: Bool {
        helperService.status == .requiresApproval
    }

    private init() {
        checkHelperStatus()
    }

    // MARK: - Helper Service

    func checkHelperStatus() {
        let status = helperService.status
        isHelperInstalled = status == .enabled
        AppLogger.debug("Helper service status: \(status.rawValue)")
    }

    func installHelper(completion: @escaping (Bool, Error?) -> Void) {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/\(helperIdentifier)")
        let plistURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons/\(daemonPlistName)")

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            finishHelperOperation(
                .failure(HelperServiceError.missingBundledHelper(helperURL.path)),
                completion: completion
            )
            return
        }

        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            finishHelperOperation(
                .failure(HelperServiceError.missingLaunchDaemonPlist(plistURL.path)),
                completion: completion
            )
            return
        }

        invalidateHelperConnection()

        do {
            let service = helperService
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                finishHelperOperation(.failure(HelperServiceError.requiresApproval), completion: completion)
                return
            }
            if service.status == .enabled {
                try service.unregister()
            }
            try service.register()

            switch service.status {
            case .enabled:
                finishHelperOperation(.success(()), completion: completion)
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
                finishHelperOperation(.failure(HelperServiceError.requiresApproval), completion: completion)
            case .notRegistered, .notFound:
                finishHelperOperation(
                    .failure(HelperServiceError.registrationDidNotEnableService),
                    completion: completion
                )
            @unknown default:
                finishHelperOperation(.failure(HelperServiceError.unknownStatus), completion: completion)
            }
        } catch {
            if helperService.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                finishHelperOperation(.failure(HelperServiceError.requiresApproval), completion: completion)
                return
            }
            checkHelperStatus()
            completion(false, error)
        }
    }

    func uninstallHelper(completion: @escaping (Bool, Error?) -> Void) {
        invalidateHelperConnection()

        do {
            let service = helperService
            if service.status != .notRegistered {
                try service.unregister()
            }
            finishHelperOperation(.success(()), completion: completion)
        } catch {
            checkHelperStatus()
            completion(false, error)
        }
    }

    private func finishHelperOperation(
        _ result: Result<Void, Error>,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        checkHelperStatus()
        PermissionManager.shared.refresh()

        switch result {
        case .success:
            completion(true, nil)
        case .failure(let error):
            completion(false, error)
        }
    }

    // MARK: - Helper Connection

    private func connectToHelper(completion: @escaping (NSXPCConnection?) -> Void) {
        guard helperService.status == .enabled else {
            isHelperInstalled = false
            completion(nil)
            return
        }

        if let helperConnection {
            completion(helperConnection)
            return
        }

        let connection = NSXPCConnection(machServiceName: helperIdentifier, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: DNSHelperProtocol.self)
        connection.setCodeSigningRequirement(helperCodeSigningRequirement)
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.helperConnection = nil
            }
        }
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.helperConnection = nil
            }
        }

        helperConnection = connection
        connection.resume()
        completion(connection)
    }

    private func invalidateHelperConnection() {
        helperConnection?.invalidate()
        helperConnection = nil
    }

    func checkHelperHealth(completion: @escaping (Result<String, Error>) -> Void) {
        let checkID = UUID()
        helperHealthCheckID = checkID

        connectToHelper { [weak self] connection in
            guard let self else { return }
            guard let connection else {
                finishHelperHealthCheck(
                    checkID,
                    result: .failure(HelperServiceError.unavailable),
                    completion: completion
                )
                return
            }

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    invalidateHelperConnection()
                    finishHelperHealthCheck(
                        checkID,
                        result: .failure(error),
                        completion: completion
                    )
                }
            }) as? DNSHelperProtocol else {
                finishHelperHealthCheck(
                    checkID,
                    result: .failure(HelperServiceError.unavailable),
                    completion: completion
                )
                return
            }

            proxy.getVersion { [weak self] version in
                Task { @MainActor [weak self] in
                    self?.finishHelperHealthCheck(
                        checkID,
                        result: .success(version),
                        completion: completion
                    )
                }
            }
        }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.finishHelperHealthCheck(
                checkID,
                result: .failure(HelperServiceError.healthCheckTimedOut),
                completion: completion
            )
        }
    }

    private func finishHelperHealthCheck(
        _ checkID: UUID,
        result: Result<String, Error>,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard helperHealthCheckID == checkID else { return }
        helperHealthCheckID = nil
        completion(result)
    }

    private func getHelperProxy(completion: @escaping (DNSHelperProtocol?) -> Void) {
        connectToHelper { connection in
            guard let connection else {
                completion(nil)
                return
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                AppLogger.error("Helper XPC request failed", error: error)
            } as? DNSHelperProtocol
            completion(proxy)
        }
    }

    // MARK: - DNS Operations

    func setDNS(
        interface: String,
        primaryDNS: String,
        secondaryDNS: String?,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard isHelperInstalled else {
            completion(false, "Helper 未安装")
            return
        }

        getHelperProxy { [weak self] proxy in
            guard let self else {
                completion(false, "DNSManager 已释放")
                return
            }
            guard let proxy else {
                completion(false, "无法连接到 Helper")
                return
            }

            proxy.setDNS(
                interface: interface,
                primaryDNS: primaryDNS,
                secondaryDNS: secondaryDNS
            ) { success, error in
                if success {
                    Task { @MainActor in
                        self.getCurrentDNS(interface: interface) { _ in }
                    }
                }
                completion(success, error)
            }
        }
    }

    func clearDNS(interface: String, completion: @escaping (Bool, String?) -> Void) {
        guard isHelperInstalled else {
            completion(false, "Helper 未安装")
            return
        }

        getHelperProxy { [weak self] proxy in
            guard let self else {
                completion(false, "DNSManager 已释放")
                return
            }
            guard let proxy else {
                completion(false, "无法连接到 Helper")
                return
            }

            proxy.clearDNS(interface: interface) { success, error in
                if success {
                    Task { @MainActor in
                        self.getCurrentDNS(interface: interface) { _ in }
                    }
                }
                completion(success, error)
            }
        }
    }

    func getCurrentDNS(interface: String, completion: @escaping ([String]) -> Void) {
        AppLogger.debug("获取当前 DNS 配置 - 接口: \(interface)")

        guard let store = SCDynamicStoreCreate(nil, "Kairos" as CFString, nil, nil),
              let dictionary = SCDynamicStoreCopyValue(
                store,
                "State:/Network/Global/DNS" as CFString
              ) as? [String: Any],
              let servers = dictionary["ServerAddresses"] as? [String] else {
            currentPrimaryDNS = "-"
            currentSecondaryDNS = "-"
            completion([])
            return
        }

        currentPrimaryDNS = servers.first ?? "-"
        currentSecondaryDNS = servers.count > 1 ? servers[1] : "-"
        completion(servers)
    }

    func flushDNSCache() {
        getHelperProxy { proxy in
            proxy?.flushDNSCache { success in
                if !success {
                    AppLogger.error("DNS 缓存刷新失败")
                }
            }
        }
    }

    func flushDNSCacheForMaintenance() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            getHelperProxy { proxy in
                guard let proxy else {
                    continuation.resume(throwing: HelperServiceError.unavailable)
                    return
                }
                proxy.flushDNSCache { success in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HelperServiceError.operationFailed("DNS cache flush"))
                    }
                }
            }
        }
    }

    func clearARPCache() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            getHelperProxy { proxy in
                guard let proxy else {
                    continuation.resume(throwing: HelperServiceError.unavailable)
                    return
                }
                proxy.clearARPCache { success, message in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(
                            throwing: HelperServiceError.operationFailed(message ?? "ARP cache clear")
                        )
                    }
                }
            }
        }
    }

    func purgeInactiveMemory() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            getHelperProxy { proxy in
                guard let proxy else {
                    continuation.resume(throwing: HelperServiceError.unavailable)
                    return
                }
                proxy.purgeInactiveMemory { success, message in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(
                            throwing: HelperServiceError.operationFailed(message ?? "memory purge")
                        )
                    }
                }
            }
        }
    }
}

private enum HelperServiceError: LocalizedError {
    case missingBundledHelper(String)
    case missingLaunchDaemonPlist(String)
    case requiresApproval
    case registrationDidNotEnableService
    case unknownStatus
    case unavailable
    case healthCheckTimedOut
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledHelper(let path):
            return "Bundle 内缺少 Helper：\(path)"
        case .missingLaunchDaemonPlist(let path):
            return "Bundle 内缺少 LaunchDaemon plist：\(path)"
        case .requiresApproval:
            return "Helper 已注册，请在系统设置的登录项中批准"
        case .registrationDidNotEnableService:
            return "Helper 注册完成，但服务尚未启用"
        case .unknownStatus:
            return "Helper 返回未知的服务状态"
        case .unavailable:
            return "Helper 未启用或无法连接"
        case .healthCheckTimedOut:
            return "Helper 健康检查超时"
        case .operationFailed(let message):
            return "Helper 操作失败：\(message)"
        }
    }
}
