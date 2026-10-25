import Foundation

@MainActor
final class PermissionManager {
    func checkAccessibility() -> Bool { false }
}

enum L10n {
    static func string(_ value: String) -> String { value }
    static func format(_ value: String, _ args: CVarArg...) -> String { String(format: value, arguments: args) }
}

@main
struct SceneApplicationSelectionTests {
    @MainActor static func main() throws {
        precondition(AppControlPresentation.name(for: "Legacy Editor") == "Legacy Editor")
        precondition(AppControlPresentation.name(for: "com.example.Editor") == "com.example.Editor")
        precondition(AppControlPresentation.name(for: "~/Downloads/My Editor.app") == "My Editor")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Kairos-AppSelection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = AppControlService(permissionManager: nil)
        var references: [String] = []
        for directory in ["Downloads", "Setapp"] {
            let url = root.appendingPathComponent(directory).appendingPathComponent("Same Name.app")
            try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let identifier = "com.example.Selection.\(directory)"
            let plist = try PropertyListSerialization.data(fromPropertyList: [
                "CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL"
            ], format: .xml, options: 0)
            try plist.write(to: url.appendingPathComponent("Contents/Info.plist"))
            references.append(url.path)
            let resolved = try service.resolve(url.path)
            precondition(resolved.bundleIdentifier == identifier && resolved.url.path == url.path,
                "An unlaunched app selected outside standard application folders must keep its identity")
            precondition(AppControlPresentation.name(for: url.path) == "Same Name",
                "Cards and editors must display the application name rather than its full path")
        }
        precondition(Set(references).count == 2, "Same-name installations must remain distinct selections")
        let scene = NetworkScene(name: "home", routerIP: "192.168.1.1", routerMAC: "AA:BB:CC:DD:EE:FF", controlApps: references + ["Legacy Editor"], isEnabled: false)
        let restored = try JSONDecoder().decode(NetworkScene.self, from: JSONEncoder().encode(scene))
        precondition(restored.controlApps == references + ["Legacy Editor"], "The existing scene format preserves both new paths and legacy names")
        print("Scene application path selection, compact labels, exact offline identity and legacy-format checks passed")
    }
}
