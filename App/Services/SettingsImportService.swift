import Foundation

/// Commit scene files before publishing preferences or changing running automation.
struct SettingsImportService {
    let appStorage: SceneFileStorage<NetworkScene>
    let dnsStorage: SceneFileStorage<DNSScene>

    @MainActor
    static func apply(_ data: KairosExportData) throws {
        let transaction = try Self(appStorage: SceneStorage.fileStorage(), dnsStorage: DNSSceneStorage.shared.fileStorage())
        try transaction.apply(data, configService: MihomoConfigService(), apiKeyManager: .shared)
    }

    @MainActor
    func apply(_ data: KairosExportData, configService: MihomoConfigService, apiKeyManager: APIKeyManager) throws {
        // Imported identity belongs to the exporting machine; resolve locally before any writes.
        let config = try configService.resolvingHostApp(in: data.mihomoConfig)
        try commitSceneFiles(data)
        data.apiKeys.apply(to: apiKeyManager)
        try configService.saveConfig(config)
    }

    func commitSceneFiles(_ data: KairosExportData) throws {
        let scenes = try data.normalizedScenes()
        // Capture original bytes, not decoded models, including the absence of a file.
        let appSnapshot = try appStorage.snapshot()
        let dnsSnapshot = try dnsStorage.snapshot()
        do {
            try appStorage.save(scenes.apps)
            try dnsStorage.save(scenes.dns)
        } catch {
            let originalError = error
            var rollbackErrors: [String] = []
            do { try appStorage.restore(appSnapshot) } catch { rollbackErrors.append(error.localizedDescription) }
            do { try dnsStorage.restore(dnsSnapshot) } catch { rollbackErrors.append(error.localizedDescription) }
            if !rollbackErrors.isEmpty {
                throw SettingsImportError.rollbackFailed(originalError, rollbackErrors)
            }
            throw originalError
        }
    }
}

enum SettingsImportError: LocalizedError {
    case reading(Error)
    case rollbackFailed(Error, [String])

    var errorDescription: String? {
        switch self {
        case .reading(let error):
            switch error {
            case DecodingError.keyNotFound(let key, let context):
                return L10n.format("配置文件缺少字段：%@", (context.codingPath + [key]).map(\.stringValue).joined(separator: "."))
            case DecodingError.valueNotFound(_, let context), DecodingError.typeMismatch(_, let context):
                return L10n.format("配置文件字段无效：%@", context.codingPath.map(\.stringValue).joined(separator: "."))
            default:
                return error.localizedDescription
            }
        case .rollbackFailed(let error, let failures):
            return L10n.format("导入失败：%@；恢复原配置也失败：%@", error.localizedDescription, failures.joined(separator: "; "))
        }
    }
}
