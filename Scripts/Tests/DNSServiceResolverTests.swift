import Foundation
import SystemConfiguration

@main
struct DNSServiceResolverTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Kairos.DNSServiceResolver.\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func service(_ bsdName: String, name: String = "Wi-Fi", enabled: Bool = true) -> [String: Any] {
            var value: [String: Any] = [
                "UserDefinedName": name,
                "Interface": ["DeviceName": bsdName, "Hardware": "Ethernet", "Type": "Ethernet"],
                "DNS": ["ServerAddresses": ["192.0.2.53"]]
            ]
            if !enabled { value["__INACTIVE__"] = 1 }
            return value
        }
        func location(_ identifiers: [String]) -> [String: Any] {
            ["Network": [
                "Service": Dictionary(uniqueKeysWithValues: identifiers.map { ($0, ["__LINK__": "/NetworkServices/\($0)"]) }),
                "Global": ["IPv4": ["ServiceOrder": identifiers]]
            ]]
        }
        func preferences(current: [String], services: [String: [String: Any]], hasCurrent: Bool = true) throws -> SCPreferences {
            var fixture: [String: Any] = [
                "NetworkServices": services,
                "Sets": ["current": location(current), "other": location(["other-location"])]
            ]
            if hasCurrent { fixture["CurrentSet"] = "/Sets/current" }
            let file = directory.appendingPathComponent("\(UUID()).plist")
            try PropertyListSerialization.data(fromPropertyList: fixture, format: .xml, options: 0).write(to: file)
            guard let preferences = SCPreferencesCreate(nil, "KairosTests" as CFString, file.path as CFString) else {
                fatalError("Cannot open isolated preferences")
            }
            return preferences
        }
        func expectError(_ expected: DNSServiceResolver.ResolutionError, in preferences: SCPreferences, name: String = "en0") throws {
            do {
                _ = try DNSServiceResolver.service(forBSDName: name, in: preferences)
                fatalError("Expected \(expected)")
            } catch let error as DNSServiceResolver.ResolutionError {
                precondition(error == expected, "Unexpected resolution error: \(error)")
            }
        }

        let services = [
            "active": service("en0"),
            "other-location": service("en0"),
            "renamed": service("en1", name: "en0"),
            "disabled": service("en0", enabled: false)
        ]
        let prefs = try preferences(current: ["renamed", "disabled", "active"], services: services)
        let resolved = try DNSServiceResolver.service(forBSDName: "en0", in: prefs)
        precondition(SCNetworkServiceGetServiceID(resolved) as String? == "active")
        try expectError(.interfaceNotFound("Wi-Fi"), in: prefs, name: "Wi-Fi")
        try expectError(.interfaceNotFound("en0"), in: preferences(current: ["renamed", "disabled"], services: services))
        try expectError(.interfaceNotFound("en0"), in: preferences(current: [], services: services))
        try expectError(.ambiguousInterface("en0"), in: preferences(
            current: ["active", "duplicate"], services: services.merging(["duplicate": service("en0")]) { _, new in new }))
        try expectError(.noCurrentLocation, in: preferences(current: ["active"], services: services, hasCurrent: false))
        print("DNS service resolution checks passed (isolated preferences; no system writes)")
    }
}
