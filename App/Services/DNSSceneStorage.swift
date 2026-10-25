import Foundation

final class DNSSceneStorage {
    static let shared = DNSSceneStorage()
    private init() {}

    func fileStorage() throws -> SceneFileStorage<DNSScene> {
        try .applicationStorage(filename: "dnsScenes.json", legacyKey: "dnsScenes")
    }

    func saveScenes(_ scenes: [DNSScene]) throws {
        try fileStorage().save(scenes)
    }

    func loadScenes() throws -> [DNSScene] {
        try fileStorage().load()
    }

    func clearScenes() throws {
        try fileStorage().restore(nil)
    }
}
