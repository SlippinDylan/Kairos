import Foundation

// Editors and imported settings share validation and canonical MAC formatting.
enum SceneValidation {
    enum Field: Error, Equatable {
        case name, routerIP, routerMAC, controlApps, primaryDNS, secondaryDNS
        case controlApp(Int)

        var path: String {
            switch self {
            case .name: return "name"
            case .routerIP: return "routerIP"
            case .routerMAC: return "routerMAC"
            case .controlApps: return "controlApps"
            case .controlApp(let index): return "controlApps[\(index)]"
            case .primaryDNS: return "primaryDNS"
            case .secondaryDNS: return "secondaryDNS"
            }
        }
    }

    static func appControl(name: String, routerIP: String, routerMAC: String, apps: [String]) -> Result<String, Field> {
        let gateway = gateway(name: name, routerIP: routerIP, routerMAC: routerMAC)
        guard case .success = gateway else { return gateway }
        guard !apps.isEmpty else { return .failure(.controlApps) }
        if let index = apps.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return .failure(.controlApp(index))
        }
        return gateway
    }

    static func dnsControl(name: String, routerIP: String, routerMAC: String, primaryDNS: String, secondaryDNS: String) -> Result<String, Field> {
        let gateway = gateway(name: name, routerIP: routerIP, routerMAC: routerMAC)
        guard case .success = gateway else { return gateway }
        guard NetworkValidator.isValidIP(primaryDNS) else { return .failure(.primaryDNS) }
        guard secondaryDNS.isEmpty || NetworkValidator.isValidIP(secondaryDNS) else { return .failure(.secondaryDNS) }
        return gateway
    }

    static func normalize(_ scene: NetworkScene) throws -> NetworkScene {
        let mac = try appControl(name: scene.name, routerIP: scene.routerIP, routerMAC: scene.routerMAC, apps: scene.controlApps).get()
        var normalized = scene
        normalized.routerMAC = mac
        return normalized
    }

    static func normalize(_ scene: DNSScene) throws -> DNSScene {
        let mac = try dnsControl(name: scene.name, routerIP: scene.routerIP, routerMAC: scene.routerMAC,
            primaryDNS: scene.primaryDNS, secondaryDNS: scene.secondaryDNS).get()
        var normalized = scene
        normalized.routerMAC = mac
        return normalized
    }

    private static func gateway(name: String, routerIP: String, routerMAC: String) -> Result<String, Field> {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.name) }
        guard NetworkValidator.isValidIP(routerIP) else { return .failure(.routerIP) }
        guard let normalizedMAC = NetworkValidator.normalizeMAC(routerMAC) else { return .failure(.routerMAC) }
        return .success(normalizedMAC)
    }
}
