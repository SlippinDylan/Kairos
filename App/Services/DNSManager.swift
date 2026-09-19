//
//  DNSManager.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/26.
//

import CryptoKit
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
    private static let registeredHelperFingerprintKey = "Kairos.RegisteredHelperFingerprint"

    var currentPrimaryDNS: String = "-"
    var currentSecondaryDNS: String = "-"
    var isHelperInstalled = false

    private let helperIdentifier = "studio.slippindylan.BrewKit.Kairos.helper"
    private let daemonPlistName = "studio.slippindylan.BrewKit.Kairos.helper.plist"
    private var helperConnection: NSXPCConnection?
    private var isValidatingHelper = false
    private var hasAttemptedAutomaticRepair = false

    private var helperService: SMAppService {
        .daemon(plistName: daemonPlistName)
    }

    private var bundledHelperURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/\(helperIdentifier)")
    }

    private var bundledDaemonPlistURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons/\(daemonPlistName)")
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
        guard FileManager.default.isExecutableFile(atPath: bundledHelperURL.path) else {
            finishHelperOperation(
                .failure(HelperServiceError.missingBundledHelper(bundledHelperURL.path)),
                completion: completion
            )
            return
        }

        guard FileManager.default.fileExists(atPath: bundledDaemonPlistURL.path) else {
            finishHelperOperation(
                .failure(HelperServiceError.missingLaunchDaemonPlist(bundledDaemonPlistURL.path)),
                completion: completion
            )
            return
        }

        invalidateHelperConnection()

        let service = helperService
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            finishHelperOperation(.failure(HelperServiceError.requiresApproval), completion: completion)
            return
        }
        if service.status == .enabled {
            reregisterHelper(openSystemSettingsOnApproval: true, completion: completion)
            return
        }
        registerHelper(service, openSystemSettingsOnApproval: true, completion: completion)
    }

    func uninstallHelper(completion: @escaping (Bool, Error?) -> Void) {
        invalidateHelperConnection()

        let service = helperService
        guard service.status != .notRegistered else {
            clearRegisteredHelperFingerprint()
            finishHelperOperation(.success(()), completion: completion)
            return
        }

        service.unregister { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    finishHelperOperation(.failure(error), completion: completion)
                    return
                }
                clearRegisteredHelperFingerprint()
                finishHelperOperation(.success(()), completion: completion)
            }
        }
    }

    private func reregisterHelper(
        openSystemSettingsOnApproval: Bool,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        invalidateHelperConnection()
        let service = helperService
        service.unregister { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let currentService = helperService
                if let error, currentService.status != .notRegistered {
                    finishHelperOperation(.failure(error), completion: completion)
                    return
                }
                registerHelper(
                    currentService,
                    openSystemSettingsOnApproval: openSystemSettingsOnApproval,
                    completion: completion
                )
            }
        }
    }

    private func registerHelper(
        _ service: SMAppService,
        openSystemSettingsOnApproval: Bool,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        do {
            try service.register()

            switch service.status {
            case .enabled:
                recordRegisteredHelperFingerprint()
                finishHelperOperation(.success(()), completion: completion)
            case .requiresApproval:
                if openSystemSettingsOnApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
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
            if service.status == .requiresApproval {
                if openSystemSettingsOnApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
                finishHelperOperation(.failure(HelperServiceError.requiresApproval), completion: completion)
                return
            }
            finishHelperOperation(.failure(error), completion: completion)
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

    func validateHelperIfNeeded() {
        guard helperService.status == .enabled, !isValidatingHelper else { return }
        guard let bundledVersion = bundledHelperVersion(),
              let bundledFingerprint = bundledHelperFingerprint() else {
            AppLogger.error("无法读取 Bundle 内 Helper 的版本或指纹")
            return
        }

        guard let registeredFingerprint = UserDefaults.standard.string(
            forKey: Self.registeredHelperFingerprintKey
        ) else {
            attemptAutomaticRepair(reason: "现有 Helper 尚未登记 Bundle 指纹")
            return
        }

        if registeredFingerprint != bundledFingerprint {
            attemptAutomaticRepair(reason: "Bundle 内 Helper executable 或 LaunchDaemon plist 已更新")
            return
        }

        isValidatingHelper = true
        runningHelperVersion { [weak self] result in
            guard let self else { return }
            isValidatingHelper = false

            switch result {
            case .success(let runningVersion) where runningVersion == bundledVersion:
                UserDefaults.standard.set(
                    bundledFingerprint,
                    forKey: Self.registeredHelperFingerprintKey
                )
                AppLogger.info(
                    "Helper 版本验证通过: \(runningVersion.shortVersion) (\(runningVersion.buildVersion))"
                )
            case .success(let runningVersion):
                attemptAutomaticRepair(
                    reason: "Helper 版本不一致: 运行中 \(runningVersion.shortVersion) "
                        + "(\(runningVersion.buildVersion))，Bundle \(bundledVersion.shortVersion) "
                        + "(\(bundledVersion.buildVersion))"
                )
            case .failure(let error):
                attemptAutomaticRepair(reason: "Helper 健康检查失败: \(error.localizedDescription)")
            }
        }
    }

    private func attemptAutomaticRepair(reason: String) {
        guard !hasAttemptedAutomaticRepair else {
            AppLogger.error("Helper 自动修复已尝试，本次不再重试: \(reason)")
            return
        }

        hasAttemptedAutomaticRepair = true
        isValidatingHelper = true
        AppLogger.warning("开始自动重新注册 Helper: \(reason)")

        reregisterHelper(openSystemSettingsOnApproval: false) { [weak self] success, error in
            guard let self else { return }
            isValidatingHelper = false

            if success {
                AppLogger.info("Helper 自动重新注册成功")
            } else {
                AppLogger.error(
                    "Helper 自动重新注册失败",
                    error: error ?? HelperServiceError.registrationDidNotEnableService
                )
            }
        }
    }

    private func runningHelperVersion(
        completion: @escaping (Result<HelperVersion, Error>) -> Void
    ) {
        performHelperRequest(
            operation: "读取 Helper 版本",
            timeoutNanoseconds: 5_000_000_000,
            invoke: { proxy, reply in
                proxy.getVersion(reply: reply)
            }
        ) { [weak self] shortVersionResult in
            guard let self else { return }
            switch shortVersionResult {
            case .failure(let error):
                completion(.failure(error))
            case .success(let shortVersion):
                performHelperRequest(
                    operation: "读取 Helper 构建号",
                    timeoutNanoseconds: 5_000_000_000,
                    invoke: { proxy, reply in
                        proxy.getBuildVersion(reply: reply)
                    }
                ) { buildVersionResult in
                    completion(
                        buildVersionResult.map {
                            HelperVersion(shortVersion: shortVersion, buildVersion: $0)
                        }
                    )
                }
            }
        }
    }

    private func bundledHelperVersion() -> HelperVersion? {
        guard let information = CFBundleCopyInfoDictionaryForURL(
            bundledHelperURL as CFURL
        ) as? [String: Any],
        let shortVersion = Self.versionString(
            information["CFBundleShortVersionString"]
        ),
        let buildVersion = Self.versionString(
            information[kCFBundleVersionKey as String]
        ) else {
            return nil
        }
        return HelperVersion(shortVersion: shortVersion, buildVersion: buildVersion)
    }

    private static func versionString(_ value: Any?) -> String? {
        switch value {
        case let value as String where !value.isEmpty:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private func bundledHelperFingerprint() -> String? {
        guard let helperData = try? Data(contentsOf: bundledHelperURL, options: .mappedIfSafe),
              let plistData = try? Data(contentsOf: bundledDaemonPlistURL, options: .mappedIfSafe) else {
            return nil
        }
        var hasher = SHA256()
        hasher.update(data: helperData)
        hasher.update(data: plistData)
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func recordRegisteredHelperFingerprint() {
        guard let fingerprint = bundledHelperFingerprint() else {
            AppLogger.warning("Helper 已注册，但无法记录 bundled executable 指纹")
            return
        }
        UserDefaults.standard.set(fingerprint, forKey: Self.registeredHelperFingerprintKey)
    }

    private func clearRegisteredHelperFingerprint() {
        UserDefaults.standard.removeObject(forKey: Self.registeredHelperFingerprintKey)
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
        guard NetworkValidator.isValidIP(primaryDNS) else {
            completion(false, L10n.string("主 DNS 地址无效"))
            return
        }
        if let secondaryDNS, !secondaryDNS.isEmpty,
           !NetworkValidator.isValidIP(secondaryDNS) {
            completion(false, L10n.string("备用 DNS 地址无效"))
            return
        }

        guard isHelperInstalled else {
            completion(false, L10n.string("Helper 未安装"))
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
                completion(success, Self.localizedHelperMessage(error))
            case .failure(let error):
                completion(false, error.localizedDescription)
            }
        }
    }

    func clearDNS(interface: String, completion: @escaping (Bool, String?) -> Void) {
        guard isHelperInstalled else {
            completion(false, L10n.string("Helper 未安装"))
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
                completion(success, Self.localizedHelperMessage(error))
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
                            throwing: HelperServiceError.operationFailed(
                                Self.localizedHelperMessage(message) ?? "ARP cache clear"
                            )
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
                            throwing: HelperServiceError.operationFailed(
                                Self.localizedHelperMessage(message) ?? "network interface refresh"
                            )
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
                            throwing: HelperServiceError.operationFailed(
                                Self.localizedHelperMessage(message) ?? "memory purge"
                            )
                        )
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func localizedHelperMessage(_ message: String?) -> String? {
        guard let message else { return nil }

        switch message {
        case "主 DNS 地址无效", "备用 DNS 地址无效", "无法创建网络配置",
             "无法获取网络服务", "无法应用 DNS 配置更改", "无法设置 DNS 协议配置",
             "无法清除 DNS 协议配置":
            return L10n.string(message)
        default:
            if let interface = message.removingPrefix("未找到匹配的网络服务：") {
                return L10n.format("未找到匹配的网络服务：%@", interface)
            }
            if let interface = message.removingPrefix("未找到网络接口：") {
                return L10n.format("未找到网络接口：%@", interface)
            }
            if let detail = message.removingPrefix("无法刷新网络接口：") {
                return L10n.format("无法刷新网络接口：%@", detail)
            }
            return message
        }
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
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
            return L10n.format("Bundle 内缺少 Helper：%@", path)
        case .missingLaunchDaemonPlist(let path):
            return L10n.format("Bundle 内缺少 LaunchDaemon plist：%@", path)
        case .requiresApproval:
            return L10n.string("Helper 已注册，请在系统设置的登录项中批准")
        case .registrationDidNotEnableService:
            return L10n.string("Helper 注册完成，但服务尚未启用")
        case .unknownStatus:
            return L10n.string("Helper 返回未知的服务状态")
        case .unavailable:
            return L10n.string("Helper 未启用或无法连接")
        case .xpcRequestFailed(let message):
            return L10n.format("Helper 通信失败：%@", message)
        case .requestTimedOut(let operation):
            return L10n.format("Helper %@超时，操作结果未知", L10n.string(operation))
        case .operationFailed(let message):
            return L10n.format("Helper 操作失败：%@", message)
        }
    }
}

private struct HelperVersion: Equatable, Sendable {
    let shortVersion: String
    let buildVersion: String
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
