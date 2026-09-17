import Sparkle

@MainActor
final class ApplicationUpdateController: NSObject, SPUUpdaterDelegate {
    static let shared = ApplicationUpdateController()

    private let allowedUpdateChannels: Set<String>
    private var updaterController: SPUStandardUpdaterController?

    private override init() {
        let updateChannel = Bundle.main.object(forInfoDictionaryKey: "KairosUpdateChannel") as? String ?? "stable"
        allowedUpdateChannels = Self.allowedChannels(for: updateChannel)
        super.init()

        guard (Bundle.main.object(forInfoDictionaryKey: "KairosUpdaterEnabled") as? String)?
            .localizedCaseInsensitiveCompare("YES") == .orderedSame else {
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates == true
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        allowedUpdateChannels
    }

    private static func allowedChannels(for updateChannel: String) -> Set<String> {
        switch updateChannel {
        case "stable": []
        case "beta": ["beta"]
        case "alpha": ["alpha", "beta"]
        default: preconditionFailure("Unsupported Kairos update channel: \(updateChannel)")
        }
    }
}
