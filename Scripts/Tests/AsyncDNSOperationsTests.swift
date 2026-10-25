import Foundation
import dnssd

private nonisolated final class CleanupCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

@main
struct AsyncDNSOperationsTests {
    static func main() async throws {
        let answer = try await withTimeout(seconds: 1) { 42 }
        precondition(answer == 42)

        let precancelStarted = CleanupCounter()
        let precancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await withTimeout(seconds: 1) {
                precancelStarted.record()
                return 42
            }
        }
        do {
            _ = try await precancelled.value
            preconditionFailure("An already cancelled run must not start work")
        } catch is CancellationError { }
        precondition(precancelStarted.value == 0)

        let timeoutCleanup = CleanupCounter()
        let start = ContinuousClock.now
        do {
            _ = try await SystemDNSResolver.hasAddress(for: "fixture.invalid", timeout: 0.03) { _, _ in
                defer { timeoutCleanup.record() }
                try await Task.sleep(for: .seconds(30))
                return true
            }
            preconditionFailure("A DNS timeout must throw rather than manufacture an answer")
        } catch let error as URLError {
            precondition(error.code == .timedOut)
        }
        precondition(start.duration(to: .now) < .seconds(1))
        precondition(timeoutCleanup.value == 2, "Both family operations must finish cleanup before timeout returns")

        let cancellationCleanup = CleanupCounter()
        let cancellationStarted = CleanupCounter()
        let task = Task {
            try await SystemDNSResolver.hasAddress(for: "fixture.invalid") { _, _ in
                cancellationStarted.record()
                defer { cancellationCleanup.record() }
                try await Task.sleep(for: .seconds(30))
                return true
            }
        }
        while cancellationStarted.value < 2 { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            preconditionFailure("Cancellation must remain cancellation")
        } catch is CancellationError { }
        precondition(cancellationCleanup.value == 2)

        for positiveFamily in [kDNSServiceProtocol_IPv4, kDNSServiceProtocol_IPv6] {
            let result = try await SystemDNSResolver.hasAddress(for: "fixture.invalid") { _, family in
                family == DNSServiceProtocol(positiveFamily)
            }
            precondition(result, "An absent address in one family cannot hide a valid answer in the other")
        }
        let absent = try await SystemDNSResolver.hasAddress(for: "fixture.invalid") { _, _ in false }
        precondition(!absent)
        let singleFamily = try await SystemDNSResolver.hasAddress(for: "fixture.invalid") { _, family in
            if family == DNSServiceProtocol(kDNSServiceProtocol_IPv6) { throw URLError(.cannotFindHost) }
            try await Task.sleep(for: .milliseconds(5))
            return true
        }
        precondition(singleFamily, "A failed optional address family cannot override a valid address")

        let native = try await DNSChecker.checkDomain("example.invalid") { domain in
            domain == "example.invalid"
        }
        precondition(native == .native)
        let wildcard = try await DNSChecker.checkDomain("example.invalid") { _ in true }
        precondition(wildcard == .dns)
        do {
            _ = try await DNSChecker.checkDomain("example.invalid") { _ in throw URLError(.timedOut) }
            preconditionFailure("Wildcard lookup failure cannot become a native/unlocked result")
        } catch let error as URLError {
            precondition(error.code == .timedOut)
        }
        print("Async timeout, DNS classification and cancellation checks passed (no network requests)")
    }
}
