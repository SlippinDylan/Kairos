import Foundation

/// File IO stays explicit so a failed read can never become an empty configuration.
struct SceneFileStorage<Scene: Codable> {
    let url: URL
    let legacyKey: String
    let defaults: UserDefaults
    var writeData: (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }

    static func applicationStorage(filename: String, legacyKey: String) throws -> Self {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Kairos", isDirectory: true)
        return Self(url: directory.appendingPathComponent(filename), legacyKey: legacyKey, defaults: .standard)
    }

    func load() throws -> [Scene] {
        do {
            if let data = try snapshot() {
                return try JSONDecoder().decode([Scene].self, from: data)
            }
            if let legacyValue = defaults.object(forKey: legacyKey) {
                guard let legacy = legacyValue as? Data else {
                    throw CocoaError(.coderReadCorrupt)
                }
                let scenes = try JSONDecoder().decode([Scene].self, from: legacy)
                try save(scenes)
                // The migration source survives every failure before the successful write.
                defaults.removeObject(forKey: legacyKey)
                return scenes
            }
            return []
        } catch {
            throw SceneStorageError.reading(url.lastPathComponent, error)
        }
    }

    func save(_ scenes: [Scene]) throws {
        do {
            try write(JSONEncoder().encode(scenes))
        } catch {
            throw SceneStorageError.writing(url.lastPathComponent, error)
        }
    }

    func snapshot() throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    func restore(_ snapshot: Data?) throws {
        if let snapshot {
            try write(snapshot)
        } else {
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                // Restoring a previously absent file is already complete.
            }
        }
    }

    private func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeData(data, url)
    }
}

enum SceneStorageError: LocalizedError {
    case reading(String, Error)
    case writing(String, Error)

    var errorDescription: String? {
        switch self {
        case .reading(let filename, let error):
            L10n.format("无法读取场景文件 %@：%@", filename, error.localizedDescription)
        case .writing(let filename, let error):
            L10n.format("无法保存场景文件 %@：%@", filename, error.localizedDescription)
        }
    }
}
