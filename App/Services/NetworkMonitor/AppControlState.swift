import Foundation

struct AppControlApplication: Equatable {
    let bundleIdentifier: String
    let url: URL
    let name: String

    func matches(bundleIdentifier: String?) -> Bool {
        self.bundleIdentifier == bundleIdentifier
    }
}

enum AppControlQuitOutcome {
    case alreadyStopped
    case terminated(AppControlApplication)
    case partiallyTerminated(AppControlApplication, Error)
}

// A timeout ends the wait, not the quit request already delivered to another process.
struct AppControlPendingTerminations {
    private var applications: [Int32: AppControlApplication] = [:]

    var isEmpty: Bool { applications.isEmpty }

    mutating func track(_ application: AppControlApplication, processIdentifier: Int32) {
        applications[processIdentifier] = application
    }

    mutating func confirm(processIdentifier: Int32) -> AppControlApplication? {
        applications.removeValue(forKey: processIdentifier)
    }
}

/// A rule does not prove that Kairos closed an app; only confirmed exits enter this ledger.
struct AppControlState {
    private(set) var closedApplications: [String: AppControlApplication] = [:]
    private var restorationAttempts: [String: Int] = [:]
    private static let maximumRestorationAttempts = 3

    mutating func recordQuit(_ outcome: AppControlQuitOutcome) {
        switch outcome {
        case .alreadyStopped:
            break
        case .terminated(let application), .partiallyTerminated(let application, _):
            closedApplications[application.bundleIdentifier] = application
        }
    }

    mutating func recordRestoration(_ application: AppControlApplication) {
        closedApplications.removeValue(forKey: application.bundleIdentifier)
        restorationAttempts.removeValue(forKey: application.bundleIdentifier)
    }

    mutating func resetRestorationAttempts(controlledIDs: Set<String>) {
        for identifier in controlledIDs { restorationAttempts.removeValue(forKey: identifier) }
    }

    mutating func recordRestorationFailure(_ application: AppControlApplication) -> Bool {
        let identifier = application.bundleIdentifier
        restorationAttempts[identifier, default: 0] += 1
        return restorationAttempts[identifier, default: 0] < Self.maximumRestorationAttempts
    }

    func applicationsToRestore(controlledIDs: Set<String>) -> [AppControlApplication] {
        closedApplications.values
            .filter {
                !controlledIDs.contains($0.bundleIdentifier) &&
                    restorationAttempts[$0.bundleIdentifier, default: 0] < Self.maximumRestorationAttempts
            }
            .sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    }
}
