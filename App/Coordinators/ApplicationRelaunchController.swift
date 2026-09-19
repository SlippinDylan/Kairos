import AppKit

@MainActor
final class ApplicationRelaunchController {
    static let shared = ApplicationRelaunchController()

    private let applicationURL: URL
    private var relaunchRequested = false

    private init(applicationURL: URL = Bundle.main.bundleURL) {
        self.applicationURL = applicationURL
    }

    func requestRelaunch() {
        guard !relaunchRequested else { return }
        relaunchRequested = true
        NSApp.terminate(nil)
    }

    func relaunchIfRequested() {
        guard relaunchRequested else { return }
        relaunchRequested = false

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        ) { _, error in
            if let error {
                AppLogger.error("Unable to relaunch Kairos", error: error)
            }
        }
    }
}
