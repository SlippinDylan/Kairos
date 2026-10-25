import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    var mihomo: Result<MihomoConfig, Error>
    var apiKeys: APIKeySettingsDraft

    private var savedMihomo: Result<MihomoConfig, Error>
    private var savedAPIKeys: APIKeySettingsDraft
    private let configService: MihomoConfigService
    private let apiKeyManager: APIKeyManager

    var hasChanges: Bool {
        if apiKeys != savedAPIKeys { return true }
        if case .success(let draft) = mihomo, case .success(let saved) = savedMihomo {
            return draft != saved
        }
        return false
    }

    convenience init() {
        self.init(configService: MihomoConfigService(), apiKeyManager: .shared)
    }

    init(configService: MihomoConfigService, apiKeyManager: APIKeyManager) {
        self.configService = configService
        self.apiKeyManager = apiKeyManager
        let config = Result { try configService.loadConfig() }
        let keys = APIKeySettingsDraft(from: apiKeyManager)
        mihomo = config
        savedMihomo = config
        apiKeys = keys
        savedAPIKeys = keys
    }

    func reload() {
        mihomo = Result { try configService.loadConfig() }
        apiKeys = APIKeySettingsDraft(from: apiKeyManager)
        savedMihomo = mihomo
        savedAPIKeys = apiKeys
    }

    var canSaveConfiguration: Bool {
        if case .success = mihomo { return true }
        return false
    }

    func retryConfigurationLoad() {
        mihomo = Result { try configService.loadConfig() }
        savedMihomo = mihomo
    }

    func save() throws {
        // A failed load remains an error even when only a credential was edited.
        let draft = try mihomo.get()
        let saved = try savedMihomo.get()
        let config = draft.appBundlePath == saved.appBundlePath
            ? draft
            : try configService.resolvingHostApp(in: draft)
        try configService.saveConfig(config)
        apiKeys.apply(to: apiKeyManager)
        apiKeys = APIKeySettingsDraft(from: apiKeyManager)
        mihomo = .success(config)
        savedMihomo = .success(config)
        savedAPIKeys = apiKeys
    }
}

struct APIKeySettingsDraft: Equatable {
    var ipinfoToken: String
    var ipapiKey: String
    var dbipKey: String
    var ipwhoisKey: String
    var abuseipdbKey: String
    var ip2locationKey: String
    var ipregistryKey: String

    @MainActor
    init(from manager: APIKeyManager) {
        ipinfoToken = manager.ipinfoToken
        ipapiKey = manager.ipapiKey
        dbipKey = manager.dbipKey
        ipwhoisKey = manager.ipwhoisKey
        abuseipdbKey = manager.abuseipdbKey
        ip2locationKey = manager.ip2locationKey
        ipregistryKey = manager.ipregistryKey
    }

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
