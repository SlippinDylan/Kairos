import Foundation

enum DNSChecker {
    enum UnlockType: String {
        case native = "原生"
        case dns = "DNS"
        case unknown = "-"

        var displayName: String {
            switch self {
            case .native: L10n.string("原生")
            case .dns: "DNS"
            case .unknown: "-"
            }
        }
    }

    typealias Lookup = @Sendable (String) async throws -> Bool

    static func getUnlockType(dns1Result: Bool, dns3Result: Bool) -> UnlockType {
        !dns1Result || !dns3Result ? .dns : .native
    }

    static func checkDomain(
        _ domain: String,
        lookup: @escaping Lookup = { try await SystemDNSResolver.hasAddress(for: $0) }
    ) async throws -> UnlockType {
        let subdomain = "test\(UUID().uuidString.replacingOccurrences(of: "-", with: "")).\(domain)"
        async let addressExists = lookup(domain)
        async let wildcardExists = lookup(subdomain)
        let (address, wildcard) = try await (addressExists, wildcardExists)
        try Task.checkCancellation()
        return getUnlockType(dns1Result: address, dns3Result: !wildcard)
    }
}
