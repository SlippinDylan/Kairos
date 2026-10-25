import Foundation

/// Serializes DNS writes and records only configurations acknowledged by the Helper.
struct DNSSceneApplicationState {
    struct Configuration: Equatable {
        let routerIP: String
        let routerMAC: String
        let primaryDNS: String
        let secondaryDNS: String
        let interfaces: [String]
    }

    private(set) var desired: Configuration?
    private(set) var applied: Configuration?
    private(set) var inFlight: Configuration?
    private(set) var revision: UInt64 = 0
    private var changedDuringWrite = false

    mutating func update(_ configuration: Configuration?) -> Configuration? {
        if desired != configuration {
            revision += 1
            if inFlight != nil { changedDuringWrite = true }
        }
        desired = configuration
        if configuration == nil {
            // Reentering a network must reapply DNS even if its rule has not changed.
            applied = nil
        }
        return beginPendingConfiguration()
    }

    func canContinue(_ configuration: Configuration, revision: UInt64) -> Bool {
        self.revision == revision && desired == configuration
    }

    mutating func finish(_ configuration: Configuration, succeeded: Bool) -> Configuration? {
        precondition(inFlight == configuration)
        inFlight = nil
        let mustReapply = changedDuringWrite
        changedDuringWrite = false
        applied = succeeded && desired != nil && !mustReapply ? configuration : nil
        // A failure remains retryable on the next event, without an automatic retry loop.
        guard desired != configuration || mustReapply else { return nil }
        return beginPendingConfiguration()
    }

    private mutating func beginPendingConfiguration() -> Configuration? {
        guard inFlight == nil, let desired, desired != applied else { return nil }
        inFlight = desired
        return desired
    }
}
