import Foundation

/// Decode the system boundary without confusing malformed data with no resolver.
struct DNSResolverConfiguration {
    let servers: [String]

    init(value: Any?) throws {
        guard let value else {
            servers = []
            return
        }
        guard let dictionary = value as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        guard let addresses = dictionary["ServerAddresses"] else {
            servers = []
            return
        }
        guard let servers = addresses as? [String] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        self.servers = servers
    }
}
