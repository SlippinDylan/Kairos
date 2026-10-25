import Foundation

enum AppLogger {
    static func debug(_ message: String) {}
    static func info(_ message: String) {}
    static func error(_ message: String) {}
}

@main
@MainActor
struct ScenePersistenceTests {
    enum Failure: Error { case injected }
    static var checks = 0

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Kairos-ScenePersistence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "Kairos-ScenePersistence-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Missing isolated preferences") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let appURL = directory.appendingPathComponent("scenes.json")
        let dnsURL = directory.appendingPathComponent("dnsScenes.json")
        let appStorage = SceneFileStorage<NetworkScene>(url: appURL, legacyKey: "apps", defaults: defaults)
        let dnsStorage = SceneFileStorage<DNSScene>(url: dnsURL, legacyKey: "dns", defaults: defaults)
        let scene = NetworkScene(name: "Fixture", routerIP: "192.0.2.1", routerMAC: "00:01:02:03:04:05", controlApps: ["Fixture"], isEnabled: false)
        let dnsScene = DNSScene(name: "Fixture DNS", routerIP: "192.0.2.1", routerMAC: "00:01:02:03:04:05", primaryDNS: "1.1.1.1", secondaryDNS: "", isEnabled: false)
        expect(try appStorage.load().isEmpty, "only missing storage is empty")

        defaults.set("invalid legacy type", forKey: "apps")
        expectThrows("invalid legacy types are surfaced") { _ = try appStorage.load() }
        expect(defaults.string(forKey: "apps") == "invalid legacy type", "invalid legacy values remain recoverable")
        defaults.set(Data("{broken".utf8), forKey: "apps")
        expectThrows("corrupt migration input is surfaced") { _ = try appStorage.load() }
        expect(defaults.data(forKey: "apps") == Data("{broken".utf8), "corrupt migration input is retained")

        let legacy = try JSONEncoder().encode([scene])
        defaults.set(legacy, forKey: "apps")
        var brokenWrite = appStorage
        brokenWrite.writeData = { _, _ in throw Failure.injected }
        expectThrows("failed migration is surfaced") { _ = try brokenWrite.load() }
        expect(defaults.data(forKey: "apps") == legacy, "failed migration retains its only source")
        expect(try appStorage.load() == [scene], "migration returns saved scenes")
        expect(defaults.object(forKey: "apps") == nil, "successful migration removes old preferences")
        expect(try JSONDecoder().decode([NetworkScene].self, from: Data(contentsOf: appURL)) == [scene], "migration wrote complete data")

        try Data("{broken".utf8).write(to: appURL)
        expectThrows("corrupt storage is never treated as empty") { _ = try appStorage.load() }
        expect(try appStorage.snapshot() == Data("{broken".utf8), "failed reads preserve original bytes")
        let directoryStorage = SceneFileStorage<NetworkScene>(url: directory, legacyKey: "directory", defaults: defaults)
        expectThrows("IO read errors are surfaced") { _ = try directoryStorage.load() }

        let manager = APIKeyManager(userDefaults: defaults)
        let data = KairosExportData(appControlScenes: [scene], dnsControlScenes: [dnsScene], apiKeys: APIKeyExportData(from: manager), mihomoConfig: .default)
        var brokenDNS = dnsStorage
        brokenDNS.writeData = { _, _ in throw Failure.injected }
        let transaction = SettingsImportService(appStorage: appStorage, dnsStorage: brokenDNS)
        expectThrows("second write failure rejects import") { try transaction.commitSceneFiles(data) }
        expect(try appStorage.snapshot() == Data("{broken".utf8), "rollback restores original bytes even when malformed")
        expect(try dnsStorage.snapshot() == nil, "rollback restores original absence")

        // The first write succeeds, then its rollback fails. The error must name this failure.
        var writeCount = 0
        var failingRollback = appStorage
        failingRollback.writeData = { bytes, url in
            writeCount += 1
            if writeCount > 1 { throw Failure.injected }
            try bytes.write(to: url, options: .atomic)
        }
        do {
            try SettingsImportService(appStorage: failingRollback, dnsStorage: brokenDNS).commitSceneFiles(data)
            fatalError("Rollback failure must throw")
        } catch SettingsImportError.rollbackFailed(_, let errors) {
            expect(errors.count == 1, "rollback failures are explicitly reported")
        }

        try SettingsImportService(appStorage: appStorage, dnsStorage: dnsStorage).commitSceneFiles(data)
        expect(try appStorage.load() == [scene] && dnsStorage.load() == [dnsScene], "successful commit writes both lists")
        try appStorage.save([])
        expect(try appStorage.load().isEmpty, "explicit empty lists remain valid configurations")
        try appStorage.restore(nil)
        try appStorage.restore(nil)
        expect(try appStorage.snapshot() == nil, "restoring an absent file is idempotent")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func decoded(_ object: [String: Any]) throws -> KairosExportData {
            try decoder.decode(KairosExportData.self, from: JSONSerialization.data(withJSONObject: object))
        }
        guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { fatalError("Expected export object") }
        expect(try decoded(object).version == 2, "complete v2 round-trips")
        var changed = object
        changed["version"] = 99
        expectThrows("future versions are rejected") { _ = try decoded(changed) }
        changed["version"] = 0
        expectThrows("invalid version is rejected") { _ = try decoded(changed) }
        changed = object
        changed.removeValue(forKey: "mihomoConfig")
        expectThrows("missing v2 config is rejected") { _ = try decoded(changed) }
        changed["version"] = 1
        expect(try decoded(changed).mihomoConfig == .default, "v1 retains its documented missing-config compatibility")
        changed = object
        changed["mihomoConfig"] = NSNull()
        expectThrows("null v2 config is rejected") { _ = try decoded(changed) }
        changed = object
        guard var config = changed["mihomoConfig"] as? [String: Any] else { fatalError("Expected config object") }
        config.removeValue(forKey: "kernelPath")
        changed["mihomoConfig"] = config
        expectThrows("incomplete nested v2 config is rejected") { _ = try decoded(changed) }
        changed = object
        guard let appObjects = changed["appControlScenes"] as? [Any] else { fatalError("Expected app scenes") }
        changed["appControlScenes"] = appObjects + appObjects
        expectThrows("duplicate app IDs are rejected") { _ = try decoded(changed) }
        changed = object
        guard let dnsObjects = changed["dnsControlScenes"] as? [Any] else { fatalError("Expected DNS scenes") }
        changed["dnsControlScenes"] = dnsObjects + dnsObjects
        expectThrows("duplicate DNS IDs are rejected") { _ = try decoded(changed) }
        changed = object
        changed["appName"] = "Other"
        expectThrows("foreign exports are rejected") { _ = try decoded(changed) }

        // A typed JSON document can still contain unusable scene rules.
        try appStorage.save([scene])
        try dnsStorage.save([dnsScene])
        let originalApps = try appStorage.snapshot()
        let originalDNS = try dnsStorage.snapshot()
        func invalidScenes(apps: [NetworkScene] = [scene], dns: [DNSScene] = [dnsScene], field: String) throws {
            let candidate = KairosExportData(appControlScenes: apps, dnsControlScenes: dns,
                apiKeys: APIKeyExportData(from: manager), mihomoConfig: .default)
            do {
                _ = try decoder.decode(KairosExportData.self, from: encoder.encode(candidate))
                fatalError("Invalid scene JSON must fail decoding")
            } catch SettingsFileValidationError.invalidSceneField(let actualField) {
                expect(actualField == field, "decode errors name the exact scene and field")
            }
            var writes = 0
            var observedAppStorage = appStorage
            var observedDNSStorage = dnsStorage
            observedAppStorage.writeData = { _, _ in writes += 1 }
            observedDNSStorage.writeData = { _, _ in writes += 1 }
            do {
                try SettingsImportService(appStorage: observedAppStorage, dnsStorage: observedDNSStorage).commitSceneFiles(candidate)
                fatalError("Direct import values must share decoder validation")
            } catch SettingsFileValidationError.invalidSceneField(let actualField) {
                expect(actualField == field, "commit errors name the exact scene and field")
            }
            expect(writes == 0, "semantic rejection precedes every write")
            expect(try appStorage.snapshot() == originalApps && dnsStorage.snapshot() == originalDNS,
                "invalid imports leave both existing scene files byte-for-byte unchanged")
        }

        for name in ["", " \t\n"] {
            var invalid = scene
            invalid.name = name
            try invalidScenes(apps: [invalid], field: "appControlScenes[0].name")
            var invalidDNS = dnsScene
            invalidDNS.name = name
            try invalidScenes(dns: [invalidDNS], field: "dnsControlScenes[0].name")
        }
        for value in ["", "999.0.2.1", "router.example"] {
            var invalid = scene
            invalid.routerIP = value
            try invalidScenes(apps: [invalid], field: "appControlScenes[0].routerIP")
            var invalidDNS = dnsScene
            invalidDNS.routerIP = value
            try invalidScenes(dns: [invalidDNS], field: "dnsControlScenes[0].routerIP")
        }
        for value in ["", "00:01:02", "not-a-mac"] {
            var invalid = scene
            invalid.routerMAC = value
            try invalidScenes(apps: [invalid], field: "appControlScenes[0].routerMAC")
            var invalidDNS = dnsScene
            invalidDNS.routerMAC = value
            try invalidScenes(dns: [invalidDNS], field: "dnsControlScenes[0].routerMAC")
        }
        for (apps, field) in [([String](), "controlApps"), ([""], "controlApps[0]"), (["Fixture", " \n"], "controlApps[1]")] {
            var invalid = scene
            invalid.controlApps = apps
            try invalidScenes(apps: [invalid], field: "appControlScenes[0].\(field)")
        }
        for value in ["", "999.1.1.1", "dns.example"] {
            var invalid = dnsScene
            invalid.primaryDNS = value
            try invalidScenes(dns: [invalid], field: "dnsControlScenes[0].primaryDNS")
        }
        for value in [" \t", "999.1.1.1", "dns.example"] {
            var invalid = dnsScene
            invalid.secondaryDNS = value
            try invalidScenes(dns: [invalid], field: "dnsControlScenes[0].secondaryDNS")
        }
        var validIPv6 = dnsScene
        validIPv6.routerIP = "fe80::1"
        validIPv6.primaryDNS = "2606:4700:4700::1111"
        validIPv6.secondaryDNS = "2001:4860:4860::8888"
        _ = try KairosExportData(appControlScenes: [scene], dnsControlScenes: [validIPv6],
            apiKeys: APIKeyExportData(from: manager), mihomoConfig: .default).normalizedScenes()
        let optionalDNS = try SceneValidation.dnsControl(name: dnsScene.name, routerIP: dnsScene.routerIP,
            routerMAC: dnsScene.routerMAC, primaryDNS: dnsScene.primaryDNS, secondaryDNS: "").get()
        expect(optionalDNS == dnsScene.routerMAC, "an omitted secondary DNS remains valid")
        for mac in ["0a-0b-0c-0d-0e-0f", "a:b:c:d:e:f", "0a0b0c0d0e0f"] {
            var app = scene
            var dns = dnsScene
            app.routerMAC = mac
            dns.routerMAC = mac
            let imported = KairosExportData(appControlScenes: [app], dnsControlScenes: [dns],
                apiKeys: APIKeyExportData(from: manager), mihomoConfig: .default)
            let normalized = try decoder.decode(KairosExportData.self, from: encoder.encode(imported))
            expect(normalized.appControlScenes[0].routerMAC == "0A:0B:0C:0D:0E:0F"
                && normalized.dnsControlScenes[0].routerMAC == "0A:0B:0C:0D:0E:0F",
                "decoded scenes use the same MAC representation as editor saves")
            try SettingsImportService(appStorage: appStorage, dnsStorage: dnsStorage).commitSceneFiles(imported)
            expect(try appStorage.load()[0].routerMAC == "0A:0B:0C:0D:0E:0F"
                && dnsStorage.load()[0].routerMAC == "0A:0B:0C:0D:0E:0F",
                "direct import commits also persist canonical MAC values")
        }
        let configService = MihomoConfigService(userDefaults: defaults)
        let importService = SettingsImportService(appStorage: appStorage, dnsStorage: dnsStorage)
        var importedConfig = MihomoConfig.default
        importedConfig.appBundlePath = directory.appendingPathComponent("Missing.app").path
        importedConfig.appBundleIdentifier = "example.exporting-machine"
        importedConfig.appDisplayName = "Old machine app"
        let previousToken = manager.ipinfoToken
        manager.ipinfoToken = "fixture-import-rejected"
        let rejectedKeys = APIKeyExportData(from: manager)
        manager.ipinfoToken = previousToken
        let invalidHostImport = KairosExportData(appControlScenes: [scene], dnsControlScenes: [dnsScene],
            apiKeys: rejectedKeys, mihomoConfig: importedConfig)
        let appBefore = try appStorage.snapshot()
        let dnsBefore = try dnsStorage.snapshot()
        expectThrows("an unavailable imported host app rejects import") {
            try importService.apply(invalidHostImport, configService: configService, apiKeyManager: manager)
        }
        expect(try appStorage.snapshot() == appBefore && dnsStorage.snapshot() == dnsBefore,
            "invalid imported application paths cannot mutate either scene file")
        expect(defaults.object(forKey: "mihomo_config") == nil,
            "invalid imported application paths cannot publish preferences")
        expect(manager.ipinfoToken == previousToken && defaults.string(forKey: "api_key_ipinfo") != "fixture-import-rejected",
            "invalid imported application paths cannot apply imported credentials")
        let localApp = directory.appendingPathComponent("Local.app")
        let contents = localApp.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "example.local-machine", "CFBundleDisplayName": "Local app", "CFBundlePackageType": "APPL"
        ], format: .xml, options: 0)
        try info.write(to: contents.appendingPathComponent("Info.plist"))
        importedConfig.appBundlePath = localApp.path
        let validHostImport = KairosExportData(appControlScenes: [scene], dnsControlScenes: [dnsScene],
            apiKeys: APIKeyExportData(from: manager), mihomoConfig: importedConfig)
        try importService.apply(validHostImport, configService: configService, apiKeyManager: manager)
        let resolvedConfig = try configService.loadConfig()
        expect(resolvedConfig.appBundleIdentifier == "example.local-machine" && resolvedConfig.appDisplayName == "Local app",
            "import derives application identity from the local bundle rather than exported metadata")
        importedConfig.appBundlePath = ""
        let noHostImport = KairosExportData(appControlScenes: [], dnsControlScenes: [],
            apiKeys: APIKeyExportData(from: manager), mihomoConfig: importedConfig)
        try importService.apply(noHostImport, configService: configService, apiKeyManager: manager)
        let unlinked = try configService.loadConfig()
        expect(unlinked.appBundleIdentifier.isEmpty && unlinked.appDisplayName.isEmpty,
            "an empty imported path also clears stale exported identity")
        print("Scene persistence: \(checks) checks passed")
    }

    static func expect(_ value: Bool, _ message: String) {
        checks += 1
        precondition(value, message)
    }

    static func expectThrows(_ message: String, operation: () throws -> Void) {
        checks += 1
        do { try operation(); fatalError(message) } catch { }
    }
}
