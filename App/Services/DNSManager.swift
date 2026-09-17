//
//  DNSManager.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/26.
//

import Foundation
import Observation
import Security
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
    private var helperConnection: NSXPCConnection?

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

        guard let helperCodeSigningRequirement = Self.peerCodeSigningRequirement(
            identifier: helperIdentifier
        ) else {
            AppLogger.error("无法读取当前 App 的签名团队，拒绝连接 Helper")
            completion(nil)
            return
        }

        let connection = NSXPCConnection(machServiceName: helperIdentifier, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: DNSHelperProtocol.self)
        connection.setCodeSigningRequirement(helperCodeSigningRequirement)
        connection.invalidationHandler = { [weak self, weak connection] in
            Task { @MainActor [weak self] in
                guard let connection else { return }
                self?.clearHelperConnection(ifCurrent: connection)
            }
        }
        connection.interruptionHandler = { [weak self, weak connection] in
            Task { @MainActor [weak self] in
                guard let connection else { return }
                self?.clearHelperConnection(ifCurrent: connection)
            }
        }

        helperConnection = connection
        connection.resume()
        completion(connection)
    }

    private static func peerCodeSigningRequirement(identifier: String) -> String? {
        guard let teamIdentifier = currentTeamIdentifier() else { return nil }
        return "identifier \"\(identifier)\" and anchor apple generic "
            + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    private static func currentTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var signingInformation: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &signingInformation) == errSecSuccess,
              let information = signingInformation as? [String: Any],
              let teamIdentifier = information[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamIdentifier.isEmpty else {
            return nil
        }
        return teamIdentifier
    }

    private func invalidateHelperConnection() {
        helperConnection?.invalidate()
        helperConnection = nil
    }

    private func invalidateHelperConnection(ifCurrent connection: NSXPCConnection) {
        guard helperConnection === connection else { return }
        invalidateHelperConnection()
    }

    private func clearHelperConnection(ifCurrent connection: NSXPCConnection) {
        guard helperConnection === connection else { return }
        helperConnection = nil
    }

    private func performHelperRequest<Response: Sendable>(
        operation: String,
        timeoutNanoseconds: UInt64 = 10_000_000_000,
        invoke: @escaping (DNSHelperProtocol, @escaping (Response) -> Void) -> Void,
        completion: @escaping (Result<Response, Error>) -> Void
    ) {
        let request = HelperRequest(completion: completion)

        connectToHelper { [weak self, request, invoke] connection in
            guard let connection else {
                request.finish(.failure(HelperServiceError.unavailable))
                return
            }

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self, weak connection] error in
                Task { @MainActor [weak self] in
                    request.finish(
                        .failure(HelperServiceError.xpcRequestFailed(error.localizedDescription))
                    )
                    guard let connection else { return }
                    self?.invalidateHelperConnection(ifCurrent: connection)
                }
            }) as? DNSHelperProtocol else {
                request.finish(.failure(HelperServiceError.unavailable))
                self?.invalidateHelperConnection(ifCurrent: connection)
                return
            }

            request.timeoutTask = Task { @MainActor [weak self, weak request] in
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                } catch {
                    return
                }
                request?.finish(
                    .failure(
                        HelperServiceError.requestTimedOut(operation)
                    )
                )
                self?.invalidateHelperConnection(ifCurrent: connection)
            }

            invoke(proxy) { response in
                Task { @MainActor in
                    request.finish(.success(response))
                }
            }
        }
    }

    func checkHelperHealth(completion: @escaping (Result<String, Error>) -> Void) {
        performHelperRequest(
            operation: "健康检查",
            timeoutNanoseconds: 5_000_000_000,
            invoke: { proxy, reply in
                proxy.getVersion(reply: reply)
            },
            completion: completion
        )
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

        performHelperRequest(
            operation: "设置 DNS",
            invoke: { proxy, reply in
                proxy.setDNS(
                    interface: interface,
                    primaryDNS: primaryDNS,
                    secondaryDNS: secondaryDNS
                ) { success, error in
                    reply((success, error))
                }
            }
        ) { [weak self] result in
            switch result {
            case .success(let (success, error)):
                if success {
                    self?.getCurrentDNS(interface: interface) { _ in }
                }
                completion(success, error)
            case .failure(let error):
                completion(false, error.localizedDescription)
            }
        }
    }

    func clearDNS(interface: String, completion: @escaping (Bool, String?) -> Void) {
        guard isHelperInstalled else {
            completion(false, "Helper 未安装")
            return
        }

        performHelperRequest(
            operation: "清除 DNS",
            invoke: { proxy, reply in
                proxy.clearDNS(interface: interface) { success, error in
                    reply((success, error))
                }
            }
        ) { [weak self] result in
            switch result {
            case .success(let (success, error)):
                if success {
                    self?.getCurrentDNS(interface: interface) { _ in }
                }
                completion(success, error)
            case .failure(let error):
                completion(false, error.localizedDescription)
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
        performHelperRequest(
            operation: "刷新 DNS 缓存",
            invoke: { proxy, reply in
                proxy.flushDNSCache(reply: reply)
            }
        ) { result in
            switch result {
            case .success(true):
                break
            case .success(false):
                AppLogger.error("DNS 缓存刷新失败")
            case .failure(let error):
                AppLogger.error("DNS 缓存刷新失败", error: error)
            }
        }
    }

    func flushDNSCacheForMaintenance() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            performHelperRequest(
                operation: "刷新 DNS 缓存",
                invoke: { proxy, reply in
                    proxy.flushDNSCache(reply: reply)
                }
            ) { result in
                switch result {
                case .success(let success):
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HelperServiceError.operationFailed("DNS cache flush"))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func clearARPCache() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            performHelperRequest(
                operation: "清除 ARP 缓存",
                invoke: { proxy, reply in
                    proxy.clearARPCache { success, message in
                        reply((success, message))
                    }
                }
            ) { result in
                switch result {
                case .success(let (success, message)):
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(
                            throwing: HelperServiceError.operationFailed(message ?? "ARP cache clear")
                        )
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func refreshNetworkInterface(_ interface: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            performHelperRequest(
                operation: "刷新网络接口",
                invoke: { proxy, reply in
                    proxy.refreshNetworkInterface(interface: interface) { success, message in
                        reply((success, message))
                    }
                }
            ) { result in
                switch result {
                case .success(let (success, message)):
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(
                            throwing: HelperServiceError.operationFailed(message ?? "network interface refresh")
                        )
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func purgeInactiveMemory() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            performHelperRequest(
                operation: "清理非活跃内存",
                timeoutNanoseconds: 30_000_000_000,
                invoke: { proxy, reply in
                    proxy.purgeInactiveMemory { success, message in
                        reply((success, message))
                    }
                }
            ) { result in
                switch result {
                case .success(let (success, message)):
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(
                            throwing: HelperServiceError.operationFailed(message ?? "memory purge")
                        )
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
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
    case xpcRequestFailed(String)
    case requestTimedOut(String)
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
        case .xpcRequestFailed(let message):
            return "Helper 通信失败：\(message)"
        case .requestTimedOut(let operation):
            return "Helper \(operation)超时，操作结果未知"
        case .operationFailed(let message):
            return "Helper 操作失败：\(message)"
        }
    }
}

@MainActor
private final class HelperRequest<Response: Sendable> {
    var timeoutTask: Task<Void, Never>?

    private var isFinished = false
    private let completion: (Result<Response, Error>) -> Void

    init(completion: @escaping (Result<Response, Error>) -> Void) {
        self.completion = completion
    }

    func finish(_ result: Result<Response, Error>) {
        guard !isFinished else { return }
        isFinished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        completion(result)
    }
}
