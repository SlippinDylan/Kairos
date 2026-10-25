import Foundation

/// Selects the first enabled gateway rule; applying DNS is the orchestrator's responsibility.
@MainActor
final class DNSSceneMatchingEngine {
    nonisolated init() {}

    func matchDNSScene(
        routerIP: String,
        routerMAC: String,
        availableScenes: [DNSScene]
    ) -> DNSScene? {
        availableScenes.first { scene in
            scene.isEnabled && scene.routerIP == routerIP &&
                scene.routerMAC.caseInsensitiveCompare(routerMAC) == .orderedSame
        }
    }
}
