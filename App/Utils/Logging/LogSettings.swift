import Foundation
import Observation

// Read from the same preference before the logger starts and when settings opens.
enum LogPreferences {
    nonisolated static let minimumLevelKey = "logging.minimumLevel"

    nonisolated static func minimumLevel(in defaults: UserDefaults = .standard) -> LogLevel {
        guard let rawValue = defaults.object(forKey: minimumLevelKey) as? Int,
              let level = LogLevel(rawValue: rawValue) else {
            return .debug
        }
        return level
    }
}

@MainActor
@Observable
final class LogSettings {
    static let shared = LogSettings()

    var minimumLevel: LogLevel {
        didSet {
            UserDefaults.standard.set(minimumLevel.rawValue, forKey: LogPreferences.minimumLevelKey)
            let level = minimumLevel
            Task { await AppLogger.shared.setMinimumLevel(level) }
        }
    }

    private init() {
        minimumLevel = LogPreferences.minimumLevel()
    }
}
