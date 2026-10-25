import Foundation

// Registration and completion share one lock because cancellation can precede registration.
final class MihomoTerminationWaitState: @unchecked Sendable {
    private let lock = NSLock()
    private let notificationCenter: NotificationCenter
    nonisolated(unsafe) private var completion: Result<Void, Error>?
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    nonisolated(unsafe) private var continuation: CheckedContinuation<Void, Error>?

    nonisolated init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter
    }

    nonisolated func registerContinuation(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if let completion {
            lock.unlock()
            continuation.resume(with: completion)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    nonisolated func registerObserver(_ observer: NSObjectProtocol) {
        lock.lock()
        if let _ = completion {
            lock.unlock()
            notificationCenter.removeObserver(observer)
        } else {
            self.observer = observer
            lock.unlock()
        }
    }

    nonisolated func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard completion == nil else {
            lock.unlock()
            return
        }
        completion = result
        let observerToRemove = observer
        observer = nil
        let continuationToResume = continuation
        continuation = nil
        lock.unlock()

        // Neither operation may run under the lock: either can invoke external code.
        if let observerToRemove {
            notificationCenter.removeObserver(observerToRemove)
        }
        continuationToResume?.resume(with: result)
    }
}
