import Foundation

final class SceneStorage {
    static func fileStorage() throws -> SceneFileStorage<NetworkScene> {
        try .applicationStorage(filename: "scenes.json", legacyKey: "networkScenes")
    }

    static func saveScenes(_ scenes: [NetworkScene]) throws {
        try fileStorage().save(scenes)
    }

    static func loadScenes() throws -> [NetworkScene] {
        try fileStorage().load()
    }
}
