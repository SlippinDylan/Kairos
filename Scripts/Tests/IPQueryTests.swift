import Foundation

// Only the logger is isolated. Requests use URLProtocol fixtures and never reach the network.
enum AppLogger {
    nonisolated static func debug(_ message: String) {}
    nonisolated static func info(_ message: String) {}
    nonisolated static func warning(_ message: String) {}
}

private final class FixtureProtocol: URLProtocol {
    nonisolated(unsafe) static var headers: [String: String] = [:]
    nonisolated(unsafe) static var reply: (URLRequest) throws -> (Int, Data) = { _ in
        fatalError("Missing fixture")
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.reply(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: Self.headers) else {
                fatalError("Invalid fixture response")
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@main
@MainActor
struct IPQueryTests {
    static let anonymous = Data(#"""
    {"ip":"192.0.2.1","company":"Example ISP","asn":"AS64500 Example ISP",
     "city":"Example City","region":"Example Region","country":"France",
     "lat":48.0,"lon":-1.8,"timezone":"Europe/Paris",
     "docs":"https://ipapi.is/free-tier.html?ref=api"}
    """#.utf8)
    static let detailed = Data(#"""
    {"ip":"192.0.2.1","asn":{"asn":64500,"country":"US"},
     "company":{"name":"Example ISP","type":"isp"},
     "location":{"city":"Example City","state":"California","country":"France",
      "country_code":"FR","continent":"EU","latitude":48.0,"longitude":-1.8,
      "timezone":"Europe/Paris","zip":null}}
    """#.utf8)

    static func main() async throws {
        try await checkRateLimitContract()
        let suite = "Kairos.IPQueryTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Missing test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let keys = APIKeyManager(userDefaults: defaults)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let cooldown = IPAPIRateLimit()
        let service = IPQueryService(session: session, apiKeyManager: keys, ipapiRateLimit: cooldown)

        FixtureProtocol.reply = { request in
            guard let url = request.url else { fatalError("Missing request URL") }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            precondition(items.first(where: { $0.name == "q" })?.value == "192.0.2.1")
            precondition(!items.contains(where: { $0.name == "key" }), "Anonymous queries must omit the key")
            return (200, anonymous)
        }
        let minimal = try await service.fetchIPInfo(ip: "192.0.2.1")
        precondition(minimal.asn == "AS64500 Example ISP" && minimal.organization == "Example ISP")
        precondition(minimal.location.usageLocation == "France", "A country name is not an ISO code")
        precondition(minimal.location.cityDisplay == "Example Region, Example City")
        precondition(minimal.registrationCountry == "—" && minimal.ipType == "—")
        precondition(minimal.coordinates?.latitude == 48.0)

        keys.ipapiKey = "  fixture&key=example\n"
        FixtureProtocol.reply = { request in
            guard let url = request.url else { fatalError("Missing request URL") }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            precondition(items.first(where: { $0.name == "key" })?.value == "fixture&key=example", "Credentials must be trimmed and query-encoded")
            return (200, detailed)
        }
        let full = try await service.fetchIPInfo(ip: "192.0.2.1")
        precondition(full.asn == "AS64500" && full.ipType == GeoUtils.ipTypeDisplayName(from: "isp"))
        precondition(full.location.usageLocation.contains("[FR]France"))
        precondition(full.registrationCountry.contains("[US]") && !full.registrationCountry.contains("France"), "ASN registration must not use the usage country's name")
        precondition(full.location.cityDisplay == "California, Example City", "Standalone regressions do not bundle the app's translated resources")
        precondition(GeoUtils.ipTypeDisplayName(from: "business") == L10n.string("商业"))
        precondition(GeoUtils.ipTypeDisplayName(from: "business") != GeoUtils.ipTypeDisplayName(from: "hosting"), "Business must not be classified as hosting")

        for body in [#"{"ip":"192.0.2.1","location":null}"#, #"{"ip":"192.0.2.1","rir":"ARIN","is_bogon":true}"#] {
            FixtureProtocol.reply = { _ in (200, Data(body.utf8)) }
            let withoutLocation = try await service.fetchIPInfo(ip: "192.0.2.1")
            precondition(withoutLocation.coordinates == nil)
            precondition(withoutLocation.location.usageLocation == "—" && withoutLocation.location.cityDisplay == "—")
            precondition(withoutLocation.asn == "—" && withoutLocation.organization == "—" && withoutLocation.timezone == "—")
        }
        FixtureProtocol.reply = { _ in (200, Data(#"{"ip":"192.0.2.1","location":{"city":42}}"#.utf8)) }
        do {
            _ = try await service.fetchIPInfo(ip: "192.0.2.1")
            fatalError("Wrong field types must remain decoding errors")
        } catch IPQueryError.decodingError { }

        // Select decoding by the response format, not by whether the request used a key.
        FixtureProtocol.reply = { _ in (200, anonymous) }
        let keyedMinimal = try await service.fetchIPInfo(ip: "192.0.2.1")
        precondition(keyedMinimal.ipType == "—")
        keys.ipapiKey = ""
        FixtureProtocol.reply = { _ in (200, detailed) }
        let anonymousFull = try await service.fetchIPInfo(ip: "192.0.2.1")
        precondition(anonymousFull.asn == "AS64500")

        let nulls = Data(#"""
        {"ip":"192.0.2.1","company":null,"asn":null,"city":null,"region":null,
         "country":null,"lat":null,"lon":null,"timezone":null,
         "docs":"https://ipapi.is/free-tier.html?ref=api"}
        """#.utf8)
        FixtureProtocol.reply = { _ in (200, nulls) }
        let missing = try await service.fetchIPInfo(ip: "192.0.2.1")
        precondition(missing.coordinates == nil && missing.asn == "—" && missing.organization == "—")
        precondition(missing.location.usageLocation == "—" && missing.location.cityDisplay == "—")

        let invalidCoordinates = Data(String(decoding: anonymous, as: UTF8.self).replacingOccurrences(of: "48.0", with: "148.0").utf8)
        FixtureProtocol.reply = { _ in (200, invalidCoordinates) }
        do {
            _ = try await service.fetchIPInfo(ip: "192.0.2.1")
            fatalError("Out-of-range coordinates must not reach the map")
        } catch IPQueryError.invalidResponse { }

        for body in [Data("{}".utf8), Data(#"{"error":"Invalid request"}"#.utf8), Data("not JSON".utf8)] {
            FixtureProtocol.reply = { _ in (200, body) }
            do {
                _ = try await service.fetchIPInfo(ip: "192.0.2.1")
                fatalError("Malformed responses must fail, not produce empty results")
            } catch IPQueryError.decodingError { }
        }
        for status in [403, 500] {
            FixtureProtocol.reply = { _ in (status, Data(#"{"error":"Request refused"}"#.utf8)) }
            do {
                _ = try await service.fetchIPInfo(ip: "192.0.2.1")
                fatalError("HTTP failures must not be decoded as lookup results")
            } catch IPQueryError.httpError(let actual) {
                precondition(actual == status)
            }
        }

        FixtureProtocol.headers = ["Retry-After": "3600"]
        FixtureProtocol.reply = { _ in (429, Data(#"{"error":"Quota exhausted"}"#.utf8)) }
        do {
            _ = try await service.fetchIPInfo(ip: "192.0.2.1")
            fatalError("HTTP 429 must install a shared cooldown")
        } catch IPAPIRateLimit.LimitError.retryAfter(let date) {
            precondition(date.timeIntervalSinceNow > 3500)
        }
        // A cooldown in IP Lookup must prevent another request from IP Quality while allowing other sources.
        FixtureProtocol.headers = [:]
        FixtureProtocol.reply = { request in
            switch request.url?.host {
            case "api.ipapi.is": fatalError("The blocked source must not make another network request")
            case "ipinfo.io": return (200, Data(#"{"data":{"country":"US"}}"#.utf8))
            case "api.db-ip.com": return (200, Data(#"{"countryCode":"US"}"#.utf8))
            case "ipwho.is": return (200, Data(#"{"success":true,"country_code":"US"}"#.utf8))
            default: fatalError("Unexpected fixture request")
            }
        }
        let qualityService = IPDataSourceService(session: session, ipapiRateLimit: cooldown)
        let limitedSources = await qualityService.fetchAllSources(ip: "192.0.2.1", apiKeyManager: keys)
        precondition(limitedSources.first(where: { $0.source == .ipapi })?.error is IPAPIRateLimit.LimitError)
        precondition(limitedSources.filter { $0.isSuccess }.count == 3, "Other providers must continue during the ipapi cooldown")

        // A configured account has a separate quota from anonymous requests.
        keys.ipapiKey = "fixture-separate-account"
        FixtureProtocol.reply = { request in
            precondition(request.url?.host == "api.ipapi.is")
            return (200, anonymous)
        }
        _ = try await service.fetchIPInfo(ip: "192.0.2.1")

        // The reverse direction shares the same limiter, including an unknown recovery deadline.
        FixtureProtocol.reply = { request in
            switch request.url?.host {
            case "api.ipapi.is": return (429, Data(#"{"error":"Account limit"}"#.utf8))
            case "ipinfo.io": return (200, Data(#"{"data":{"country":"US"}}"#.utf8))
            case "api.db-ip.com": return (200, Data(#"{"countryCode":"US"}"#.utf8))
            case "ipwho.is": return (200, Data(#"{"success":true,"country_code":"US"}"#.utf8))
            default: fatalError("Unexpected fixture request")
            }
        }
        let accountSources = await qualityService.fetchAllSources(ip: "192.0.2.1", apiKeyManager: keys)
        precondition(accountSources.first(where: { $0.source == .ipapi })?.error is IPAPIRateLimit.LimitError)
        FixtureProtocol.reply = { _ in fatalError("IP Lookup must reuse the account cooldown from IP Quality") }
        do {
            _ = try await service.fetchIPInfo(ip: "192.0.2.1")
            fatalError("An unknown recovery deadline must not silently allow retries")
        } catch IPAPIRateLimit.LimitError.recoveryTimeUnavailable(let rawHeader) {
            precondition(rawHeader == nil)
        }
        // A configured IPinfo account must be used directly, and its real error preserved.
        keys.ipinfoToken = "fixture&token=value"
        FixtureProtocol.reply = { request in
            switch request.url?.host {
            case "ipinfo.io":
                precondition(request.url?.path == "/192.0.2.1", "No widget fallback may mask a configured account failure")
                guard let url = request.url else { fatalError("Missing fixture URL") }
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                precondition(items?.first(where: { $0.name == "token" })?.value == "fixture&token=value")
                throw URLError(.timedOut)
            case "api.db-ip.com": return (200, Data(#"{"countryCode":"US"}"#.utf8))
            case "ipwho.is": return (200, Data(#"{"success":true,"country_code":"US"}"#.utf8))
            default: fatalError("Unexpected fixture request")
            }
        }
        let ipinfoFailure = await qualityService.fetchAllSources(ip: "192.0.2.1", apiKeyManager: keys)
        precondition((ipinfoFailure.first(where: { $0.source == .ipinfo })?.error as? URLError)?.code == .timedOut)
        // IPWHOIS uses separate free/Pro hosts; credentials must remain one query value.
        for key in ["", "fixture&key=value+?#/测试"] {
            keys.ipwhoisKey = key
            FixtureProtocol.reply = { request in
                guard let url = request.url else { fatalError("Missing fixture URL") }
                switch url.host {
                case "ipwho.is", "ipwhois.pro":
                    precondition(url.scheme == "https")
                    precondition(url.host == (key.isEmpty ? "ipwho.is" : "ipwhois.pro"))
                    precondition(url.path == "/192.0.2.1")
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    if key.isEmpty {
                        precondition(components?.queryItems == nil)
                    } else {
                        precondition(components?.queryItems == [URLQueryItem(name: "key", value: key)])
                        precondition(components?.fragment == nil)
                    }
                    return (200, Data(#"{"success":true,"country_code":"US"}"#.utf8))
                case "ipinfo.io", "api.db-ip.com": throw URLError(.timedOut)
                default: fatalError("Unexpected fixture request")
                }
            }
            let sources = await qualityService.fetchAllSources(ip: "192.0.2.1", apiKeyManager: keys)
            guard let result = sources.first(where: { $0.source == .ipwhois }) else {
                fatalError("Missing IPWHOIS result")
            }
            precondition(result.isSuccess)
            precondition(result.usedPaidAPI == !key.isEmpty)
        }
        print("IP query response and request checks passed")
    }

    private static func checkRateLimitContract() async throws {
        let now = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00:00 UTC
        let limiter = IPAPIRateLimit(now: { now })
        guard let url = URL(string: "https://api.ipapi.is/") else { fatalError("Invalid fixture URL") }
        func response(_ header: String?) -> HTTPURLResponse {
            guard let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil,
                headerFields: header.map { ["Retry-After": $0] }) else { fatalError("Invalid fixture response") }
            return response
        }
        let seconds = await limiter.record(response: response("120"), apiKey: nil)
        guard case .retryAfter(let secondsDate) = seconds else { fatalError("Missing retry deadline") }
        precondition(secondsDate == now.addingTimeInterval(120))
        do {
            try await limiter.check(apiKey: " \n")
            fatalError("Empty and absent keys share the anonymous quota")
        } catch IPAPIRateLimit.LimitError.retryAfter { }
        try await limiter.check(apiKey: "another-account")
        let dated = await limiter.record(response: response("Thu, 01 Jan 2026 00:05:00 GMT"), apiKey: "account")
        guard case .retryAfter(let datedDate) = dated else { fatalError("HTTP-date Retry-After must be parsed") }
        precondition(datedDate == now.addingTimeInterval(300))
        _ = await limiter.record(response: response("0"), apiKey: "expired")
        try await limiter.check(apiKey: "expired")
        for header in [nil, "not-a-date", "-1", "NaN", "1.5", "1e3"] as [String?] {
            let key = "invalid-header-\(header ?? "missing")"
            _ = await limiter.record(response: response(header), apiKey: key)
            do {
                try await limiter.check(apiKey: key)
                fatalError("Missing or invalid Retry-After must remain an explicit blocked state")
            } catch IPAPIRateLimit.LimitError.recoveryTimeUnavailable(let originalHeader) {
                precondition(originalHeader == header, "Preserve the original protocol failure")
            }
        }
        let anonymousWithoutHeader = IPAPIRateLimit(now: { now })
        _ = await anonymousWithoutHeader.record(response: response(nil), apiKey: nil)
        do {
            try await anonymousWithoutHeader.check(apiKey: nil)
            fatalError("Anonymous responses without a deadline must not invent midnight recovery")
        } catch IPAPIRateLimit.LimitError.recoveryTimeUnavailable { }
    }
}
