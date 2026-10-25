import AppKit
import UniformTypeIdentifiers

@MainActor
enum AppControlPresentation {
    static func name(for reference: String) -> String {
        guard reference.hasPrefix("/") || reference.hasPrefix("~/") else { return reference }
        return URL(fileURLWithPath: reference).deletingPathExtension().lastPathComponent
    }

    static func icon(for reference: String) -> NSImage {
        do {
            let application = try AppControlService(permissionManager: nil).resolve(reference)
            return NSWorkspace.shared.icon(forFile: application.url.path)
        } catch {
            // An unavailable application remains editable and uses the generic application icon.
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
    }
}
