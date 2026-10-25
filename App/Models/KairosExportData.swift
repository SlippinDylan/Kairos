//
//  KairosExportData.swift
//  Kairos
//
//  Created by Claude on 2026/01/09.
//
//  ## 设计说明
//  - 统一的配置导出数据结构
//  - 包含版本号便于未来兼容性处理
//  - 所有字段均支持 Codable 序列化
//

import Foundation

/// Kairos 配置导出数据结构
///
/// ## 包含内容
/// - 应用控制场景 (NetworkScene)
/// - DNS 控制场景 (DNSScene)
/// - API Key 配置
/// - Mihomo 配置 (MihomoConfig)
///
/// ## 文件格式
/// - 内部格式：JSON
/// - 文件扩展名：.kairos
struct KairosExportData: Codable {
    // MARK: - Metadata

    /// 导出格式版本（便于未来兼容性处理）
    let version: Int

    /// 导出时间
    let exportedAt: Date

    /// 应用标识
    let appName: String

    /// 应用版本
    let appVersion: String

    // MARK: - Scene Data

    /// 应用控制场景列表
    let appControlScenes: [NetworkScene]

    /// DNS 控制场景列表
    let dnsControlScenes: [DNSScene]

    // MARK: - API Keys

    /// API Key 配置
    let apiKeys: APIKeyExportData

    // MARK: - Mihomo

    /// Mihomo 配置（内核路径、关联应用等）
    let mihomoConfig: MihomoConfig

    // MARK: - Initialization

    /// 创建导出数据（使用当前配置）
    ///
    /// - Parameters:
    ///   - appControlScenes: 应用控制场景列表
    ///   - dnsControlScenes: DNS 控制场景列表
    ///   - apiKeys: API Key 配置
    ///   - mihomoConfig: Mihomo 配置
    init(
        appControlScenes: [NetworkScene],
        dnsControlScenes: [DNSScene],
        apiKeys: APIKeyExportData,
        mihomoConfig: MihomoConfig
    ) {
        self.version = Self.currentVersion
        self.exportedAt = Date()
        self.appName = "Kairos"
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        self.appControlScenes = appControlScenes
        self.dnsControlScenes = dnsControlScenes
        self.apiKeys = apiKeys
        self.mihomoConfig = mihomoConfig
    }

    /// 自定义解码：兼容 version 1 导出文件（缺少 mihomoConfig 字段）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard (1...Self.currentVersion).contains(version) else {
            throw SettingsFileValidationError.unsupportedVersion(version)
        }
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        appName = try container.decode(String.self, forKey: .appName)
        guard appName == "Kairos" else {
            throw SettingsFileValidationError.wrongApplication
        }
        appVersion = try container.decode(String.self, forKey: .appVersion)
        appControlScenes = try Self.normalizeApps(container.decode([NetworkScene].self, forKey: .appControlScenes))
        dnsControlScenes = try Self.normalizeDNS(container.decode([DNSScene].self, forKey: .dnsControlScenes))
        apiKeys = try container.decode(APIKeyExportData.self, forKey: .apiKeys)
        if version == 1 {
            mihomoConfig = try container.decodeIfPresent(MihomoConfig.self, forKey: .mihomoConfig) ?? .default
        } else {
            // Local preferences retain their older decoder; v2 exports require a full schema.
            let config = try container.nestedContainer(keyedBy: MihomoKeys.self, forKey: .mihomoConfig)
            mihomoConfig = try MihomoConfig(
                kernelPath: config.decode(String.self, forKey: .kernelPath),
                appBundlePath: config.decode(String.self, forKey: .appBundlePath),
                appBundleIdentifier: config.decode(String.self, forKey: .appBundleIdentifier),
                appDisplayName: config.decode(String.self, forKey: .appDisplayName),
                githubReleasesURL: config.decode(String.self, forKey: .githubReleasesURL),
                kernelFilenameTemplate: config.decode(String.self, forKey: .kernelFilenameTemplate)
            )
        }
        guard Set(appControlScenes.map(\.id)).count == appControlScenes.count else {
            throw SettingsFileValidationError.duplicateIDs("appControlScenes")
        }
        guard Set(dnsControlScenes.map(\.id)).count == dnsControlScenes.count else {
            throw SettingsFileValidationError.duplicateIDs("dnsControlScenes")
        }
    }

    func normalizedScenes() throws -> (apps: [NetworkScene], dns: [DNSScene]) {
        (try Self.normalizeApps(appControlScenes), try Self.normalizeDNS(dnsControlScenes))
    }

    private static func normalizeApps(_ scenes: [NetworkScene]) throws -> [NetworkScene] {
        try scenes.enumerated().map { index, scene in
            do { return try SceneValidation.normalize(scene) }
            catch let field as SceneValidation.Field {
                throw SettingsFileValidationError.invalidSceneField("appControlScenes[\(index)].\(field.path)")
            }
        }
    }

    private static func normalizeDNS(_ scenes: [DNSScene]) throws -> [DNSScene] {
        try scenes.enumerated().map { index, scene in
            do { return try SceneValidation.normalize(scene) }
            catch let field as SceneValidation.Field {
                throw SettingsFileValidationError.invalidSceneField("dnsControlScenes[\(index)].\(field.path)")
            }
        }
    }

    private enum MihomoKeys: String, CodingKey {
        case kernelPath, appBundlePath, appBundleIdentifier, appDisplayName
        case githubReleasesURL, kernelFilenameTemplate
    }

    // MARK: - Version

    /// 当前导出格式版本
    static let currentVersion = 2
}

// MARK: - API Key Export Data

/// API Key 导出数据结构
struct APIKeyExportData: Codable {
    // MARK: - 有免费 API 的数据源

    /// IPinfo Token
    let ipinfoToken: String

    /// ipapi.is API Key
    let ipapiKey: String

    /// DB-IP API Key
    let dbipKey: String

    /// IPWHOIS API Key
    let ipwhoisKey: String

    // MARK: - 纯付费数据源

    /// AbuseIPDB API Key
    let abuseipdbKey: String

    /// IP2Location API Key
    let ip2locationKey: String

    /// ipregistry API Key
    let ipregistryKey: String

    // MARK: - Convenience Initializer

    /// 从 APIKeyManager 创建导出数据
    @MainActor
    init(from manager: APIKeyManager) {
        self.ipinfoToken = manager.ipinfoToken
        self.ipapiKey = manager.ipapiKey
        self.dbipKey = manager.dbipKey
        self.ipwhoisKey = manager.ipwhoisKey
        self.abuseipdbKey = manager.abuseipdbKey
        self.ip2locationKey = manager.ip2locationKey
        self.ipregistryKey = manager.ipregistryKey
    }

    /// 应用到 APIKeyManager
    @MainActor
    func apply(to manager: APIKeyManager) {
        manager.ipinfoToken = ipinfoToken
        manager.ipapiKey = ipapiKey
        manager.dbipKey = dbipKey
        manager.ipwhoisKey = ipwhoisKey
        manager.abuseipdbKey = abuseipdbKey
        manager.ip2locationKey = ip2locationKey
        manager.ipregistryKey = ipregistryKey
        manager.saveAPIKeys()
    }
}


enum SettingsFileValidationError: LocalizedError {
    case unsupportedVersion(Int)
    case wrongApplication
    case duplicateIDs(String)
    case invalidSceneField(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            L10n.format("不支持的配置文件版本：%lld", version)
        case .wrongApplication:
            L10n.string("该文件不是 Kairos 配置文件")
        case .duplicateIDs(let section):
            L10n.format("配置文件含重复场景 ID：%@", section)
        case .invalidSceneField(let field):
            L10n.format("配置文件字段无效：%@", field)
        }
    }
}
