//
//  MihomoConfigService.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation

/// Mihomo 配置管理服务
class MihomoConfigService {
    private let userDefaults: UserDefaults
    private let configKey = "mihomo_config"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func resolvingHostApp(in draft: MihomoConfig) throws -> MihomoConfig {
        var config = draft
        let path = (draft.appBundlePath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        if path.isEmpty {
            config.appBundlePath = ""
            config.appBundleIdentifier = ""
            config.appDisplayName = ""
            return config
        }

        guard path.hasPrefix("/"), URL(fileURLWithPath: path).pathExtension.lowercased() == "app",
              let bundle = Bundle(path: path), let identifier = bundle.bundleIdentifier else {
            throw HostAppPathError.invalidApplication
        }
        config.appBundlePath = path
        config.appBundleIdentifier = identifier
        config.appDisplayName = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return config
    }

    // MARK: - 配置读写

    /// 加载配置
    /// - Returns: Mihomo 配置,如果不存在则返回默认配置
    func loadConfig() throws -> MihomoConfig {
        AppLogger.debug("加载 Mihomo 配置")
        guard let storedValue = userDefaults.object(forKey: configKey) else {
            return .default
        }
        do {
            guard let data = storedValue as? Data else {
                throw CocoaError(.coderReadCorrupt)
            }
            return try JSONDecoder().decode(MihomoConfig.self, from: data)
        } catch {
            throw MihomoConfigurationError.reading(error)
        }
    }

    /// 保存配置
    /// - Parameter config: 要保存的配置
    func saveConfig(_ config: MihomoConfig) throws {
        let data = try JSONEncoder().encode(config)
        userDefaults.set(data, forKey: configKey)
    }

}

private enum HostAppPathError: LocalizedError {
    case invalidApplication

    var errorDescription: String? {
        L10n.string("无法读取该应用的信息，请确认选择的是有效的 App")
    }
}

enum MihomoConfigurationError: LocalizedError {
    case reading(Error)

    var errorDescription: String? {
        switch self {
        case .reading(let error):
            L10n.format("无法读取 Mihomo 配置：%@", error.localizedDescription)
        }
    }
}
