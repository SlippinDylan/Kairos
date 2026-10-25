import Foundation
import AppKit

@MainActor
final class PermissionManager {
    func checkAccessibility() -> Bool { false }
}

enum L10n {
    static func string(_ value: String) -> String { value }
    static func format(_ value: String, _ args: CVarArg...) -> String { String(format: value, arguments: args) }
}

@main
struct AppControlTests {
    @MainActor static func main() async throws {
        let app = AppControlApplication(bundleIdentifier: "com.example.Editor", url: URL(fileURLWithPath: "/Applications/Editor.app"), name: "Editor")
        precondition(app.matches(bundleIdentifier: "com.example.Editor"))
        precondition(!app.matches(bundleIdentifier: "com.example.Editor.Helper"))
        precondition(!app.matches(bundleIdentifier: "com.other.Editor"))
        precondition(!app.matches(bundleIdentifier: nil))

        var state = AppControlState()
        state.recordQuit(.alreadyStopped)
        precondition(state.applicationsToRestore(controlledIDs: []).isEmpty, "An app that was not running must never be restored")
        state.recordQuit(.terminated(app))
        precondition(state.applicationsToRestore(controlledIDs: [app.bundleIdentifier]).isEmpty, "An app shared by the next scene remains controlled")
        precondition(state.applicationsToRestore(controlledIDs: []) == [app], "Only a confirmed Kairos exit is restored")
        precondition(state.applicationsToRestore(controlledIDs: []) == [app], "Failed restoration leaves the original identity and URL available for retry")
        state.recordRestoration(app)
        precondition(state.applicationsToRestore(controlledIDs: []).isEmpty)
        // A late quit receipt is recorded, then evaluated against the newest controlled identities.
        state.recordQuit(.terminated(app))
        precondition(state.applicationsToRestore(controlledIDs: []) == [app])
        state.recordRestoration(app)
        state.recordQuit(.terminated(app))
        precondition(state.closedApplications.count == 1, "Repeated receipts do not duplicate the identity")

        state.recordRestoration(app)
        state.recordQuit(.partiallyTerminated(app, AppControlError.terminationTimeout(app.name)))
        precondition(state.applicationsToRestore(controlledIDs: []) == [app], "A later process failure must not discard an already confirmed exit")

        let other = AppControlApplication(bundleIdentifier: "com.example.Other", url: URL(fileURLWithPath: "/Applications/Other.app"), name: "Other")
        var pending = AppControlPendingTerminations()
        var delayedState = AppControlState()
        pending.track(app, processIdentifier: 101)
        pending.track(other, processIdentifier: 102)
        precondition(delayedState.applicationsToRestore(controlledIDs: []).isEmpty,
            "A timed-out request is not proof that an application exited")
        if let confirmed = pending.confirm(processIdentifier: 101) {
            delayedState.recordQuit(.terminated(confirmed))
        }
        precondition(delayedState.applicationsToRestore(controlledIDs: []) == [app],
            "A confirmed exit after the timeout still restores on the latest unmatched scene")
        precondition(delayedState.applicationsToRestore(controlledIDs: [app.bundleIdentifier]).isEmpty,
            "A delayed exit must not reopen an app still controlled by the newest scene")
        precondition(pending.confirm(processIdentifier: 101) == nil && !pending.isEmpty,
            "Duplicate receipts cannot consume another process's pending request")
        precondition(pending.confirm(processIdentifier: 102) == other && pending.isEmpty)
        state.recordQuit(.terminated(other))
        precondition(state.recordRestorationFailure(app))
        precondition(state.recordRestorationFailure(app))
        precondition(!state.recordRestorationFailure(app))
        precondition(state.applicationsToRestore(controlledIDs: []) == [other], "Another pending app must not bypass this app's retry limit")
        state.resetRestorationAttempts(controlledIDs: [app.bundleIdentifier])
        precondition(state.applicationsToRestore(controlledIDs: [app.bundleIdentifier]) == [other])
        precondition(state.applicationsToRestore(controlledIDs: []).contains(app), "A new control cycle resets its restoration retry budget")

        let scene = NetworkScene(name: "home", routerIP: "192.168.1.1", routerMAC: "AA:BB:CC:DD:EE:FF", controlApps: [app.name], isEnabled: true)
        let engine = SceneMatchingEngine()
        precondition(engine.matchScenes(routerIP: scene.routerIP, routerMAC: scene.routerMAC.lowercased(), availableScenes: [scene]) == [scene])
        precondition(engine.matchScenes(routerIP: "192.168.2.1", routerMAC: scene.routerMAC, availableScenes: [scene]).isEmpty)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Kairos-AppControl-\(UUID().uuidString)")
        let bundle = root.appendingPathComponent("Fixture.app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.Fixture", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let service = AppControlService(permissionManager: nil)
        let resolved = try service.resolve(bundle.path)
        precondition(resolved.bundleIdentifier == "com.example.Fixture" && resolved.url.path == bundle.path)
        do {
            _ = try service.resolve(root.appendingPathComponent("Missing.app").path)
            preconditionFailure("A missing app identity must fail explicitly")
        } catch AppControlError.invalidApplication { }

        let center = NotificationCenter()
        let delayedApp = FixtureApplication(identity: app.bundleIdentifier, url: app.url, pid: 1101)
        let delayedService = AppControlService(permissionManager: nil, runningApplications: { [delayedApp] },
            notificationCenter: center, terminationTimeout: .milliseconds(5))
        var delayedReceipts: [AppControlApplication] = []
        delayedService.onDelayedTermination = { delayedReceipts.append($0) }
        do {
            _ = try await delayedService.quit(app, shouldContinue: { true })
            preconditionFailure("An unconfirmed quit must time out")
        } catch AppControlError.terminationTimeout { }
        precondition(delayedApp.quitRequests == 1 && delayedReceipts.isEmpty)
        delayedApp.hasExited = true
        center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: delayedApp])
        for _ in 0..<100 where delayedReceipts.isEmpty { await Task.yield() }
        precondition(delayedReceipts == [app], "A real termination notification after timeout must still deliver the quit receipt")
        center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: delayedApp])
        for _ in 0..<10 { await Task.yield() }
        precondition(delayedReceipts.count == 1, "The delayed observer must be cleaned up after its final receipt")
        print("App-control identity, matching, confirmed-exit ledger and recovery checks passed")
    }
}

private final class FixtureApplication: NSRunningApplication, @unchecked Sendable {
    let identity: String
    let applicationURL: URL
    let pid: pid_t
    var hasExited = false
    var quitRequests = 0

    init(identity: String, url: URL, pid: pid_t) {
        self.identity = identity
        applicationURL = url
        self.pid = pid
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("Not used by fixtures") }
    override var bundleIdentifier: String? { identity }
    override var bundleURL: URL? { applicationURL }
    override var processIdentifier: pid_t { pid }
    override var isTerminated: Bool { hasExited }
    override func terminate() -> Bool { quitRequests += 1; return true }
}
