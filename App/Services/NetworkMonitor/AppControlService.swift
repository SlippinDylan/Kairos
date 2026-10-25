import AppKit
import Foundation

@MainActor
final class AppControlService {
    private let permissionManager: PermissionManager?
    private let runningApplications: () -> [NSRunningApplication]
    private let notificationCenter: NotificationCenter
    private let terminationTimeout: Duration
    var onDelayedTermination: ((AppControlApplication) -> Void)?
    private var pendingTerminations = AppControlPendingTerminations()
    private var delayedTerminationObservation: MihomoTerminationWaitState?

    convenience init(permissionManager: PermissionManager?) {
        self.init(permissionManager: permissionManager,
            runningApplications: { NSWorkspace.shared.runningApplications },
            notificationCenter: NSWorkspace.shared.notificationCenter)
    }

    init(permissionManager: PermissionManager?, runningApplications: @escaping () -> [NSRunningApplication],
         notificationCenter: NotificationCenter, terminationTimeout: Duration = .seconds(10)) {
        self.permissionManager = permissionManager
        self.runningApplications = runningApplications
        self.notificationCenter = notificationCenter
        self.terminationTimeout = terminationTimeout
    }

    /// Legacy rules contain names, bundle IDs, or paths. Resolve once, then use exact identity.
    func resolve(_ reference: String) throws -> AppControlApplication {
        if reference.hasPrefix("/") || reference.hasPrefix("~/") {
            return try application(at: URL(fileURLWithPath: (reference as NSString).expandingTildeInPath))
        }
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: reference) {
            return try application(at: url)
        }
        let filename = reference.hasSuffix(".app") ? reference : reference + ".app"
        let roots = ["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications", "/System/Applications/Utilities"]
        var urls = roots.map { URL(fileURLWithPath: $0).appendingPathComponent(filename) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        urls += runningApplications().filter {
            $0.localizedName == reference || $0.bundleURL?.lastPathComponent == filename
        }.compactMap(\.bundleURL)
        let applications = try urls.map(application(at:))
        let identities = Set(applications.map(\.bundleIdentifier))
        guard identities.count <= 1 else { throw AppControlError.ambiguousApplication(reference) }
        guard let resolved = applications.first else { throw AppControlError.applicationNotFound(reference) }
        return resolved
    }

    private func application(at url: URL) throws -> AppControlApplication {
        guard url.pathExtension == "app", let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier, !identifier.isEmpty else {
            throw AppControlError.invalidApplication(url.path)
        }
        return AppControlApplication(bundleIdentifier: identifier, url: url, name: url.deletingPathExtension().lastPathComponent)
    }

    func launch(_ application: AppControlApplication) async throws {
        try Task.checkCancellation()
        guard !runningApplications().contains(where: {
            application.matches(bundleIdentifier: $0.bundleIdentifier)
        }) else { return }
        // NSWorkspace's completion is the launch result; a local timer cannot cancel its request.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: application.url, configuration: .init()) { app, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let app, application.matches(bundleIdentifier: app.bundleIdentifier) {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AppControlError.invalidApplication(application.url.path))
                }
            }
        }
    }

    func quit(_ application: AppControlApplication, shouldContinue: () -> Bool) async throws -> AppControlQuitOutcome {
        try Task.checkCancellation()
        let running = runningApplications().filter {
            application.matches(bundleIdentifier: $0.bundleIdentifier) && !$0.isTerminated
        }
        guard !running.isEmpty else { return .alreadyStopped }
        if let permissionManager, !permissionManager.checkAccessibility() {
            throw AppControlError.permissionDenied
        }
        var terminatedApplication: AppControlApplication?
        for app in running {
            do {
                try Task.checkCancellation()
                guard shouldContinue() else { throw CancellationError() }
                guard let url = app.bundleURL else { throw AppControlError.invalidApplication(application.bundleIdentifier) }
                let actualApplication = AppControlApplication(bundleIdentifier: application.bundleIdentifier, url: url, name: application.name)
                if try await terminateAndWait(app, application: actualApplication) {
                    // Restore the actual installation that was closed, not another copy found by Launch Services.
                    terminatedApplication = AppControlApplication(bundleIdentifier: application.bundleIdentifier, url: url, name: application.name)
                }
            } catch {
                if let terminatedApplication { return .partiallyTerminated(terminatedApplication, error) }
                throw error
            }
        }
        return terminatedApplication.map(AppControlQuitOutcome.terminated) ?? .alreadyStopped
    }

    private func terminateAndWait(_ app: NSRunningApplication, application: AppControlApplication) async throws -> Bool {
        guard !app.isTerminated else { return false }
        guard app.terminate() else {
            if app.isTerminated { return false }
            throw AppControlError.terminationRejected(application.name)
        }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    try await self.awaitTermination(app)
                }
                let timeout = terminationTimeout
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw AppControlError.terminationTimeout(application.name)
                }
                defer { group.cancelAll() }
                try await group.next()
            }
        } catch {
            // Preserve a sent request even when the local wait times out or is cancelled.
            trackDelayedTermination(app, application: application)
            throw error
        }
        return true
    }

    private func trackDelayedTermination(_ app: NSRunningApplication, application: AppControlApplication) {
        pendingTerminations.track(application, processIdentifier: app.processIdentifier)
        if delayedTerminationObservation == nil {
            let center = notificationCenter
            let observation = MihomoTerminationWaitState(notificationCenter: center)
            let observer = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                guard let stopped = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let processIdentifier = stopped.processIdentifier
                Task { @MainActor [weak self] in
                    self?.confirmDelayedTermination(processIdentifier)
                }
            }
            observation.registerObserver(observer)
            delayedTerminationObservation = observation
        }
        // Cover termination between the timed observer's removal and this registration.
        if app.isTerminated { confirmDelayedTermination(app.processIdentifier) }
    }

    private func confirmDelayedTermination(_ processIdentifier: Int32) {
        guard let application = pendingTerminations.confirm(processIdentifier: processIdentifier) else { return }
        if pendingTerminations.isEmpty {
            delayedTerminationObservation?.finish(.success(()))
            delayedTerminationObservation = nil
        }
        onDelayedTermination?(application)
    }

    deinit {
        delayedTerminationObservation?.finish(.failure(CancellationError()))
    }

    private func awaitTermination(_ app: NSRunningApplication) async throws {
        let center = notificationCenter
        let state = MihomoTerminationWaitState(notificationCenter: center)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                state.registerContinuation(continuation)
                let observer = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { notification in
                    guard let stopped = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          stopped.processIdentifier == app.processIdentifier else { return }
                    state.finish(.success(()))
                }
                state.registerObserver(observer)
                // The app may exit before notification registration.
                if app.isTerminated { state.finish(.success(())) }
            }
        } onCancel: {
            state.finish(.failure(CancellationError()))
        }
    }
}

enum AppControlError: LocalizedError {
    case applicationNotFound(String)
    case ambiguousApplication(String)
    case invalidApplication(String)
    case permissionDenied
    case terminationRejected(String)
    case terminationTimeout(String)

    var errorDescription: String? {
        switch self {
        case .applicationNotFound(let name): L10n.format("找不到应用：%@", name)
        case .ambiguousApplication(let name): L10n.format("存在多个同名应用，请使用应用路径或 Bundle ID：%@", name)
        case .invalidApplication(let path): L10n.format("无法读取应用身份：%@", path)
        case .permissionDenied: L10n.string("缺少辅助功能权限")
        case .terminationRejected(let name): L10n.format("应用拒绝退出：%@", name)
        case .terminationTimeout(let name): L10n.format("等待应用退出超时：%@", name)
        }
    }
}
