import Foundation

// Keep the regression independent of the running app's logger and services.
enum AppLogger {
    static func debug(_ message: String) {}
    static func info(_ message: String) {}
    static func warning(_ message: String) {}
    static func error(_ message: String) {}
}

@main
struct MihomoKernelPathTests {
    static func main() throws {
        let manager = FileManager.default
        let directory = manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Kairos-KernelPathTests-\(UUID().uuidString)")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }

        let kernel = directory.appendingPathComponent("mihomo")
        let contents = Data("kernel-path-fixture".utf8)
        try contents.write(to: kernel)
        let tildePath = "~" + String(kernel.path.dropFirst(manager.homeDirectoryForCurrentUser.path.count))
        let service = MihomoFileService()

        let initial = service.getKernelStatus(kernelPath: tildePath)
        precondition(initial.kernelExists && !initial.backupExists,
                     "Status must expand the same home-relative path as file operations")
        try service.backupKernel(kernelPath: tildePath)
        let backedUp = service.getKernelStatus(kernelPath: tildePath)
        precondition(backedUp.kernelExists && backedUp.backupExists,
                     "A backup created from a home-relative path must be visible to the UI")
        precondition(backedUp.kernelPath == kernel.path && backedUp.backupPath == kernel.path + ".bak",
                     "Status paths must identify the actual files")
        let backupContents = try Data(contentsOf: URL(fileURLWithPath: backedUp.backupPath))
        precondition(backupContents == contents,
                     "Backup operations and status must point to the same file")
        let empty = service.getKernelStatus(kernelPath: "")
        precondition(!empty.kernelExists && !empty.backupExists && empty.backupPath.isEmpty,
                     "An empty path remains unconfigured")
        print("Mihomo home-relative kernel path checks passed")
    }
}
