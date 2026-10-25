import Foundation

/// Gateway matching does not infer whether a previous app-control operation succeeded.
@MainActor
final class SceneMatchingEngine {
    nonisolated init() {}

    func matchScenes(routerIP: String, routerMAC: String, availableScenes: [NetworkScene]) -> [NetworkScene] {
        availableScenes.filter {
            $0.isEnabled && $0.routerIP == routerIP &&
                $0.routerMAC.caseInsensitiveCompare(routerMAC) == .orderedSame
        }
    }
}
