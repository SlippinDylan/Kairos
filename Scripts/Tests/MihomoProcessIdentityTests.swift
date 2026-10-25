import Foundation
import AppKit

enum AppLogger {
    nonisolated static func debug(_ message: String) {}
    nonisolated static func info(_ message: String) {}
    nonisolated static func warning(_ message: String) {}
    nonisolated static func error(_ message: String) {}
}

@main
struct MihomoProcessIdentityTests {
    static func main() async throws {
        precondition(!MihomoProcessService.matchesHostApp(bundleIdentifier: "app.selected", displayName: "Mihomo", runningBundleIdentifier: "app.other", runningDisplayName: "Mihomo"), "A matching display name must not override an available bundle identifier")
        precondition(MihomoProcessService.matchesHostApp(bundleIdentifier: "app.selected", displayName: "Mihomo", runningBundleIdentifier: "app.selected", runningDisplayName: "Renamed app"))
        precondition(MihomoProcessService.matchesHostApp(bundleIdentifier: "", displayName: "Mihomo", runningBundleIdentifier: "app.legacy", runningDisplayName: "Mihomo"), "Legacy name-only associations retain their existing behavior")
        precondition(!MihomoProcessService.matchesHostApp(bundleIdentifier: "", displayName: "", runningBundleIdentifier: nil, runningDisplayName: nil))
        let center = NotificationCenter()
        let first = FixtureApplication(identity: "app.selected", pid: 701)
        let second = FixtureApplication(identity: "app.selected", pid: 702)
        let unrelated = FixtureApplication(identity: "app.other", pid: 703)
        let service = MihomoProcessService(runningApplications: { [first, second, unrelated] }, notificationCenter: center)
        try service.quitHostApps(bundleIdentifier: "app.selected", displayName: "Mihomo")
        precondition(first.quitRequests == 1 && second.quitRequests == 1 && unrelated.quitRequests == 0, "All matching instances, and only matching instances, receive quit requests")
        first.hasExited = true
        do {
            try await service.waitForHostAppToQuit(bundleIdentifier: "app.selected", displayName: "Mihomo", maxWaitTime: 0.01)
            fatalError("One remaining instance must block kernel maintenance")
        } catch MihomoError.appQuitTimeout {}
        let completion = Task {
            try await Task.sleep(for: .milliseconds(10))
            second.hasExited = true
            center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        }
        try await service.waitForHostAppToQuit(bundleIdentifier: "app.selected", displayName: "Mihomo", maxWaitTime: 1)
        try await completion.value
        precondition(!service.isHostAppRunning(bundleIdentifier: "app.selected", displayName: "Mihomo"))

        let refusing = FixtureApplication(identity: "app.selected", pid: 704)
        refusing.acceptsQuit = false
        let refusalService = MihomoProcessService(runningApplications: { [refusing] }, notificationCenter: center)
        do {
            try refusalService.quitHostApps(bundleIdentifier: "app.selected", displayName: "Mihomo")
            fatalError("Refused quit requests must not be reported as success")
        } catch MihomoError.hostAppIsRunning {}
        print("Mihomo application identity and multi-instance exit checks passed (no processes launched or terminated)")
    }
}

private final class FixtureApplication: NSRunningApplication, @unchecked Sendable {
    let identity: String
    let pid: pid_t
    var hasExited = false
    var acceptsQuit = true
    var quitRequests = 0

    init(identity: String, pid: pid_t) {
        self.identity = identity
        self.pid = pid
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("Not used by fixtures") }
    override var bundleIdentifier: String? { identity }
    override var localizedName: String? { "Mihomo" }
    override var processIdentifier: pid_t { pid }
    override var isTerminated: Bool { hasExited }
    override func terminate() -> Bool {
        quitRequests += 1
        return acceptsQuit
    }
}
