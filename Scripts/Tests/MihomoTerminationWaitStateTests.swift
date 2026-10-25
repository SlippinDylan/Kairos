import Foundation

private final class NotificationCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

@main
struct MihomoTerminationWaitStateTests {
    static func main() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("Kairos.TerminationWaitStateTests")

        // A pre-cancelled task runs onCancel before its operation installs a continuation.
        let preCancelled = MihomoTerminationWaitState(notificationCenter: center)
        preCancelled.finish(.failure(CancellationError()))
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                preCancelled.registerContinuation(continuation)
            }
            fatalError("Cancellation before registration must resume with an error")
        } catch is CancellationError {}

        // Cancellation can also happen after addObserver returns but before the token is stored.
        let lateObserver = MihomoTerminationWaitState(notificationCenter: center)
        let lateNotifications = NotificationCount()
        let observer = center.addObserver(forName: name, object: nil, queue: nil) { _ in
            lateNotifications.increment()
        }
        lateObserver.finish(.failure(CancellationError()))
        lateObserver.registerObserver(observer)
        center.post(name: name, object: nil)
        precondition(lateNotifications.value == 0, "A token registered after completion must be removed")

        // Exercise both possible lock orders without touching NSWorkspace or a real app.
        for _ in 0..<500 {
            let state = MihomoTerminationWaitState(notificationCenter: center)
            let notifications = NotificationCount()
            let registration = DispatchGroup()
            registration.enter()
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    DispatchQueue.global().async {
                        defer { registration.leave() }
                        state.registerContinuation(continuation)
                        let token = center.addObserver(forName: name, object: nil, queue: nil) { _ in
                            notifications.increment()
                        }
                        state.registerObserver(token)
                    }
                    DispatchQueue.global().async {
                        state.finish(.failure(CancellationError()))
                    }
                }
                fatalError("Concurrent cancellation must resume with an error")
            } catch is CancellationError {}
            await withCheckedContinuation { continuation in
                registration.notify(queue: .global()) {
                    continuation.resume()
                }
            }
            center.post(name: name, object: nil)
            precondition(notifications.value == 0, "Concurrent cancellation must remove its observer")
        }

        let finished = MihomoTerminationWaitState(notificationCenter: center)
        let finishNotifications = NotificationCount()
        let completionObserver = center.addObserver(forName: name, object: nil, queue: nil) { _ in
            finishNotifications.increment()
            finished.finish(.success(()))
        }
        finished.registerObserver(completionObserver)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            finished.registerContinuation(continuation)
            center.post(name: name, object: nil)
            // Competing and repeated finishes must not resume the continuation twice.
            finished.finish(.failure(CancellationError()))
            finished.finish(.success(()))
        }
        center.post(name: name, object: nil)
        precondition(finishNotifications.value == 1, "Completion removes its observer exactly once")
        print("Mihomo termination wait cancellation checks passed")
    }
}
