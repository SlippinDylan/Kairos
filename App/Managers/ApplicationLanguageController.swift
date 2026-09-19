import Foundation
import Observation

enum ApplicationLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var title: String {
        switch self {
        case .system:
            String(localized: "language.follow_system")
        case .english:
            "English"
        case .simplifiedChinese:
            "简体中文"
        case .traditionalChinese:
            "繁體中文"
        }
    }
}

@MainActor
@Observable
final class ApplicationLanguageController {
    static let shared = ApplicationLanguageController()

    private enum Key {
        static let selection = "application.language"
        static let appleLanguages = "AppleLanguages"
    }

    private let userDefaults: UserDefaults

    private(set) var selectedLanguage: ApplicationLanguage

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        userDefaults.register(defaults: [Key.selection: ApplicationLanguage.system.rawValue])
        selectedLanguage = userDefaults.string(forKey: Key.selection)
            .flatMap(ApplicationLanguage.init(rawValue:)) ?? .system
    }

    @discardableResult
    func setSelectedLanguage(_ language: ApplicationLanguage) -> Bool {
        guard language != selectedLanguage else { return false }

        selectedLanguage = language
        userDefaults.set(language.rawValue, forKey: Key.selection)

        switch language {
        case .system:
            userDefaults.removeObject(forKey: Key.appleLanguages)
        case .english, .simplifiedChinese, .traditionalChinese:
            userDefaults.set([language.rawValue], forKey: Key.appleLanguages)
        }

        return true
    }
}
