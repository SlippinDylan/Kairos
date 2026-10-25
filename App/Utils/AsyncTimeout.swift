import Foundation

// The operation must cooperate with cancellation so the task group can finish promptly.
nonisolated func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try Task.checkCancellation()
    return try await withThrowingTaskGroup(of: T.self) { group in
        defer { group.cancelAll() }
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw URLError(.timedOut)
        }
        for try await result in group {
            try Task.checkCancellation()
            return result
        }
        throw CancellationError()
    }
}
