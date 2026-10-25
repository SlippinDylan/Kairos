import Foundation

@main
struct DNSSceneApplicationTests {
    @MainActor static func main() throws {
        let engine = DNSSceneMatchingEngine()
        let scene = DNSScene(name: "home", routerIP: "192.168.1.1", routerMAC: "AA:BB:CC:DD:EE:FF", primaryDNS: "1.1.1.1", secondaryDNS: "", isEnabled: true)
        precondition(engine.matchDNSScene(routerIP: scene.routerIP, routerMAC: scene.routerMAC.lowercased(), availableScenes: [scene]) == scene)
        precondition(engine.matchDNSScene(routerIP: "192.168.2.1", routerMAC: scene.routerMAC, availableScenes: [scene]) == nil)
        var disabled = scene
        disabled.isEnabled = false
        precondition(engine.matchDNSScene(routerIP: scene.routerIP, routerMAC: scene.routerMAC, availableScenes: [disabled]) == nil)

        let initial = DNSSceneApplicationState.Configuration(routerIP: scene.routerIP, routerMAC: scene.routerMAC.lowercased(), primaryDNS: scene.primaryDNS, secondaryDNS: "", interfaces: ["Wi-Fi"])
        let edited = DNSSceneApplicationState.Configuration(routerIP: initial.routerIP, routerMAC: initial.routerMAC, primaryDNS: "9.9.9.9", secondaryDNS: "", interfaces: initial.interfaces)
        let differentInterface = DNSSceneApplicationState.Configuration(routerIP: edited.routerIP, routerMAC: edited.routerMAC, primaryDNS: edited.primaryDNS, secondaryDNS: "", interfaces: ["Ethernet"])
        var state = DNSSceneApplicationState()
        precondition(state.update(initial) == initial)
        precondition(state.applied == nil, "Starting a write is not an acknowledgment")
        precondition(state.update(initial) == nil, "Repeated events must not overlap writes")
        precondition(state.finish(initial, succeeded: false) == nil)
        precondition(state.applied == nil)
        precondition(state.update(initial) == initial, "A failed write must be retryable")
        precondition(state.finish(initial, succeeded: true) == nil)
        precondition(state.update(initial) == nil, "An acknowledged configuration needs no repeat write")
        precondition(state.update(edited) == edited, "Editing DNS under the same scene UUID must apply")
        precondition(state.update(differentInterface) == nil)
        precondition(state.finish(edited, succeeded: true) == differentInterface, "A stale completion must yield to the latest request")
        precondition(state.finish(differentInterface, succeeded: true) == nil)
        precondition(state.update(nil) == nil, "Leaving a matched network must never clear system DNS")
        precondition(state.applied == nil)
        precondition(state.update(differentInterface) == differentInterface, "Reentering must apply again")
        precondition(state.update(nil) == nil)
        precondition(state.finish(differentInterface, succeeded: true) == nil)
        precondition(state.applied == nil, "An old completion cannot resurrect a match after leaving")
        precondition(state.update(initial) == initial)
        precondition(state.update(edited) == nil)
        precondition(state.finish(initial, succeeded: false) == edited, "A stale failure must not discard the latest request")
        precondition(state.finish(edited, succeeded: true) == nil)
        precondition(state.update(nil) == nil)
        precondition(state.update(initial) == initial)
        precondition(state.update(nil) == nil)
        precondition(state.update(initial) == nil)
        precondition(state.finish(initial, succeeded: true) == initial, "Returning while an old write runs requires a fresh acknowledgment")
        precondition(state.finish(initial, succeeded: true) == nil)
        var switching = DNSSceneApplicationState()
        precondition(switching.update(initial) == initial)
        let oldRevision = switching.revision
        precondition(switching.canContinue(initial, revision: oldRevision))
        _ = switching.update(nil)
        precondition(!switching.canContinue(initial, revision: oldRevision),
            "Starting a network refresh must stop the next unsent interface write")
        precondition(switching.finish(initial, succeeded: false) == nil && switching.applied == nil)
        precondition(switching.update(initial) == initial)
        let editedRevision = switching.revision
        _ = switching.update(edited)
        _ = switching.update(initial)
        precondition(!switching.canContinue(initial, revision: editedRevision),
            "Editing away and back cannot revive the old execution plan")
        precondition(switching.finish(initial, succeeded: false) == initial,
            "The latest identical configuration still needs a fresh complete write")
        precondition(switching.canContinue(initial, revision: switching.revision))
        precondition(switching.finish(initial, succeeded: true) == nil)
        let absent = try DNSResolverConfiguration(value: nil)
        let empty = try DNSResolverConfiguration(value: [:] as [String: Any])
        let configured = try DNSResolverConfiguration(value: ["ServerAddresses": ["1.1.1.1", "9.9.9.9"]])
        precondition(absent.servers.isEmpty && empty.servers.isEmpty)
        precondition(configured.servers == ["1.1.1.1", "9.9.9.9"])
        for malformed: Any in ["wrong", ["ServerAddresses": "1.1.1.1"], ["ServerAddresses": [1, 2]], ["ServerAddresses": NSNull()]] {
            do {
                _ = try DNSResolverConfiguration(value: malformed)
                preconditionFailure("Malformed DNS data must never become an empty resolver")
            } catch is CocoaError { }
        }
        print("DNS scene matching, application state and resolver boundary checks passed")
    }
}
