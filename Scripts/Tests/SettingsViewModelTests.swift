import Foundation

// Logging stays isolated; the real key manager uses the temporary preference domain.
enum AppLogger {
    static func debug(_ message: String) {}
    static func info(_ message: String) {}
    static func error(_ message: String) {}
}

@main
@MainActor
struct SettingsViewModelTests {
    private static var checks = 0

    static func main() throws {
        let suite = "Kairos.SettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Missing test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = MihomoConfigService(userDefaults: defaults)
        let manager = APIKeyManager(userDefaults: defaults)
        let model = SettingsViewModel(configService: service, apiKeyManager: manager)

        func editConfig(_ edit: (inout MihomoConfig) -> Void) throws {
            var config = try model.mihomo.get()
            edit(&config)
            model.mihomo = .success(config)
        }

        expect(!model.hasChanges, "initial settings are clean")
        model.apiKeys.ipinfoToken = "draft"
        try editConfig { $0.kernelPath = "/temporary/kernel" }
        expect(model.hasChanges, "both sections participate in change tracking")
        try expect(manager.ipinfoToken.isEmpty && service.loadConfig() == .default, "editing cannot affect runtime or persisted settings")
        model.apiKeys.ipinfoToken = ""
        try editConfig { $0.kernelPath = "" }
        expect(!model.hasChanges, "reverting fields removes the save action")

        try editConfig { $0.appBundlePath = "/missing/Test.app" }
        model.apiKeys.ipinfoToken = "draft"
        do {
            try model.save()
            fatalError("Invalid apps must reject the save")
        } catch {
        try expect(service.loadConfig() == .default && !manager.hasAnyAPIKey && defaults.string(forKey: "api_key_ipinfo") == nil, "app validation precedes saving either section")
            expect(model.hasChanges, "failed saves retain the draft")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Kairos-App-Test-\(UUID().uuidString)")
        let app = directory.appendingPathComponent("Fixture.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let metadata: [String: String] = [
            "CFBundleIdentifier": "example.kairos.settings-fixture",
            "CFBundleDisplayName": "Fixture App",
            "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try editConfig { $0.appBundlePath = app.path }
        try model.save()
        expect(!model.hasChanges && defaults.string(forKey: "api_key_ipinfo") == "draft" && manager.ipinfoToken == "draft", "a successful save applies both sections")
        try expect(service.loadConfig().appBundleIdentifier == "example.kairos.settings-fixture", "the app path resolves its bundle identifier")
        try expect(model.mihomo.get().appDisplayName == "Fixture App", "the app display name comes from bundle metadata")

        try editConfig { $0.appBundlePath = "" }
        try model.save()
        try expect(!model.mihomo.get().hasAssociatedApp && model.mihomo.get().appBundleIdentifier.isEmpty && model.mihomo.get().appDisplayName.isEmpty, "clearing and saving unlinks the app completely")
        expect(!model.hasChanges, "saved clearing resets change tracking")

        var stale = try model.mihomo.get()
        stale.appBundlePath = "/uninstalled/PreviouslyLinked.app"
        stale.appBundleIdentifier = "example.previously-linked"
        try service.saveConfig(stale)
        model.reload()
        model.apiKeys.ipapiKey = "draft"
        try model.save()
        try expect(manager.ipapiKey == "draft" && service.loadConfig().appBundlePath == stale.appBundlePath, "unchanged missing apps cannot block unrelated API edits")

        try editConfig { $0.kernelPath = "/unsaved" }
        manager.ipapiKey = "imported"
        try service.saveConfig(.default)
        model.reload()
        try expect(!model.hasChanges && model.mihomo.get() == .default && model.apiKeys.ipapiKey == "imported", "import reload replaces drafts and saved baselines")

        model.apiKeys.ipinfoToken = " \tfixture-ipinfo\n"
        model.apiKeys.ipapiKey = "\nfixture-ipapi \t"
        model.apiKeys.dbipKey = " fixture-dbip\r\n"
        model.apiKeys.ipwhoisKey = "\tfixture-ipwhois "
        model.apiKeys.abuseipdbKey = " \nfixture-abuseipdb\t"
        model.apiKeys.ip2locationKey = " fixture-ip2location\n"
        model.apiKeys.ipregistryKey = "\nfixture-ipregistry "
        try model.save()
        expect(!model.hasChanges && model.apiKeys == APIKeySettingsDraft(from: manager), "normalization updates the editor and saved baseline together")
        expect(manager.ipinfoToken == "fixture-ipinfo" && manager.ipapiKey == "fixture-ipapi" && manager.dbipKey == "fixture-dbip" && manager.ipwhoisKey == "fixture-ipwhois" && manager.abuseipdbKey == "fixture-abuseipdb" && manager.ip2locationKey == "fixture-ip2location" && manager.ipregistryKey == "fixture-ipregistry", "all credentials are normalized before requests use them")
        let reloadedManager = APIKeyManager(userDefaults: defaults)
        expect(APIKeySettingsDraft(from: reloadedManager) == model.apiKeys, "runtime and persisted credentials are identical without restarting")
        model.apiKeys.abuseipdbKey = " \t\r\n"
        try model.save()
        expect(!manager.hasAbuseIPDBKey && manager.abuseipdbKey.isEmpty && !model.hasChanges, "whitespace-only credentials are cleared consistently")

        manager.ipregistryKey = "\n direct-save-fixture \t"
        manager.saveAPIKeys()
        expect(manager.ipregistryKey == "direct-save-fixture" && defaults.string(forKey: "api_key_ipregistry") == manager.ipregistryKey, "the common save boundary also normalizes callers outside the editor")

        for invalidValue: Any in [Data("{broken".utf8), "wrong-type", Data("{\"kernelPath\":123}".utf8)] {
            defaults.set(invalidValue, forKey: "mihomo_config")
            let brokenModel = SettingsViewModel(configService: service, apiKeyManager: manager)
            expect(!brokenModel.canSaveConfiguration, "bad configurations remain an explicit load error")
            let attemptedKey = "must-not-save-\(checks)"
            brokenModel.apiKeys.ipapiKey = attemptedKey
            do {
                try brokenModel.save()
                fatalError("Bad configuration must block a key-only save")
            } catch {
                expect(manager.ipapiKey != attemptedKey, "failed configuration load blocks credential writes too")
                expect((defaults.object(forKey: "mihomo_config") as? NSObject) == (invalidValue as? NSObject), "failed saves preserve original configuration bytes/type")
            }
            try service.saveConfig(.default)
            brokenModel.retryConfigurationLoad()
            expect(brokenModel.canSaveConfiguration && brokenModel.apiKeys.ipapiKey == attemptedKey, "explicit retry recovers after external repair without losing key drafts")
            try brokenModel.save()
            expect(!brokenModel.hasChanges, "saving works after a successful retry")
        }
        // Older local preference objects retain their established missing-field compatibility.
        defaults.set(Data("{\"kernelPath\":\"/legacy/kernel\"}".utf8), forKey: "mihomo_config")
        try expect(service.loadConfig().kernelPath == "/legacy/kernel", "valid legacy local settings are still readable")

        print("SettingsViewModel: \(checks) checks passed")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAIL: \(message)") }
        checks += 1
    }
}
