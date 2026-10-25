import Foundation

// Compile this harness with the real models, service, parsers, key manager, and aggregation use case.
// Logging and display translations are isolated; no network request is made.
enum AppLogger {
    nonisolated static func debug(_ message: String) {}
    nonisolated static func info(_ message: String) {}
    nonisolated static func warning(_ message: String) {}
}

enum L10n {
    static var language = "zh-CN"
    nonisolated static func string(_ key: String) -> String {
        switch (language, key) {
        case ("en", "家宽"): return "Residential"
        case ("zh-TW", "家宽"): return "家寬"
        default: return key
        }
    }
    nonisolated static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: key, arguments: arguments)
    }
}

@main
@MainActor
struct IPDataSourceAggregationTests {
    static func main() throws {
        let suite = "Kairos.IPAggregationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Missing test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = IPDataSourceService()
        let useCase = MultiSourceAggregationUseCase(ipDataSourceService: service, apiKeyManager: APIKeyManager(userDefaults: defaults))

        for language in ["zh-CN", "en", "zh-TW"] {
            L10n.language = language
            let residential = service.parseIPinfo(json: ["asn": ["type": "isp"]], usedPaidAPI: false)
            let lite = service.parseIPinfo(json: ["org": "Example ISP"], usedPaidAPI: true)
            let ipapi = service.parseIPAPI(json: ["company": ["type": "isp"]], usedPaidAPI: false)
            var result = IPQualityResult()
            try useCase.aggregate(results: [residential], into: &result)
            precondition(result.ipType == .isp, "Classification must not depend on translated text")
            try useCase.aggregate(results: [lite, ipapi], into: &result)
            precondition(result.ipType == .isp, "An earlier source without a classification must not hide a later valid source")
            try useCase.aggregate(results: [lite], into: &result)
            precondition(result.ipType == .unknown, "No known source must remain unknown")

            let companyFallback = service.parseIPinfo(json: ["asn": ["type": "unrecognized"], "company": ["type": "isp"]], usedPaidAPI: false)
            try useCase.aggregate(results: [companyFallback], into: &result)
            precondition(result.ipType == .isp, "Unknown usage must fall back to a known company type")
            let business = service.parseIPAPI(json: ["company": ["type": "business"]], usedPaidAPI: false)
            try useCase.aggregate(results: [business, residential], into: &result)
            precondition(result.ipType == .isp, "Provider priority must not depend on completion order")

            let comparison = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DataSourceIPType(source: "fixture", usageType: "unchanged", companyType: nil))) as? [String: Any]
            precondition(comparison?["usageType"] as? String == "unchanged", "Persisted display fields must keep their semantics")
            precondition(comparison?["classification"] == nil, "Runtime classifications must not enter Codable data")
        }

        let flags: [(Any, Bool?)] = [
            (true, true), (false, false), (1, true), (0, false), (-3, true),
            ("provider", true), ("false", true), ("", false),
            (["name": "provider"], true), ([String: String](), true), ([String](), true),
            (NSNull(), nil)
        ]
        for (flag, expected) in flags {
            let payload: [String: Any] = ["is_datacenter": false, "is_proxy": false, "is_tor": false, "is_vpn": flag]
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { fatalError("Invalid fixture") }
            let parsed = service.parseIPAPI(json: json, usedPaidAPI: false)
            precondition(parsed.riskFactors?.isVPN == expected, "VPN flags must follow JSON truthiness")
            if let expected {
                precondition(parsed.riskScore?.score == (expected ? 25 : 0), "Normalized flags must also drive scoring")
            } else {
                precondition(parsed.riskScore == nil, "Null must not fabricate a known VPN state or a score")
            }
        }
        let missing = service.parseIPAPI(json: ["is_datacenter": false, "is_proxy": false, "is_tor": false], usedPaidAPI: false)
        precondition(missing.riskFactors?.isVPN == nil && missing.riskScore == nil, "Missing VPN data must remain unknown")

        let maximumRisk = service.parseIPAPI(json: ["is_datacenter": true, "is_proxy": true, "is_tor": true, "is_vpn": true], usedPaidAPI: true)
        precondition(maximumRisk.riskScore?.score == 100, "Locally synthesized scores must respect the 0...100 contract")
        let absentAbuse = service.parseAbuseIPDB(json: [:])
        let absentProxy = service.parseIP2Location(json: [:])
        precondition(absentAbuse.riskFactors?.isAbuser == nil, "Missing abuse confidence is unknown, not clean")
        precondition(absentProxy.riskFactors?.isProxy == nil && absentProxy.riskScore == nil && absentProxy.riskFactors?.isDatacenter == nil, "Missing paid-plan fields must not manufacture a low-risk score")
        precondition(service.parseDBIP(json: ["threatLevel": "unknown"], usedPaidAPI: true).riskScore == nil, "An unknown provider threat category must not imply low risk")
        let abuse = service.parseAbuseIPDB(json: ["abuseConfidenceScore": 75, "isTor": true, "countryCode": "US"])
        let proxy = service.parseIP2Location(json: ["is_proxy": true, "usage_type": "DCH"])
        var riskResult = IPQualityResult()
        try useCase.aggregate(results: [proxy, abuse], into: &riskResult)
        precondition(riskResult.multiSourceData?.riskFactors.map(\.source) == ["AbuseIPDB", "IP2Location"])
        precondition(riskResult.isTor && riskResult.isAbuser && riskResult.isProxy && riskResult.isDatacenter, "Every successful source's risk evidence must reach the result")

        let info = service.parseIPinfo(json: ["data": ["org": "AS64500 Example ISP", "city": "Example City", "country": "US", "loc": "37.0,-122.0", "timezone": "America/Los_Angeles"]], usedPaidAPI: false)
        let location = service.parseIPAPI(json: ["company": ["name": "Other company"], "asn": ["asn": 64501], "location": ["country": "United States", "country_code": "US", "city": "Other City"]], usedPaidAPI: true)
        var basicResult = IPQualityResult()
        try useCase.aggregate(results: [location, info], into: &basicResult)
        precondition(basicResult.asn == "AS64500" && basicResult.organization == "Example ISP")
        precondition(basicResult.city == "Example City" && basicResult.country == "United States" && basicResult.countryCode == "US")
        precondition(basicResult.latitude == 37 && basicResult.longitude == -122 && basicResult.timezone == "America/Los_Angeles")
        precondition(basicResult.multiSourceData?.riskScores.isEmpty == true, "Basic ownership/location never implies a risk score")

        let anonymous = service.parseIPAPI(json: ["docs": "https://ipapi.is/free-tier.html?ref=api", "asn": "AS64502 Anonymous ISP", "company": "Anonymous ISP", "country": "France", "city": "Example City", "lat": 48.0, "lon": -1.8, "timezone": "Europe/Paris"], usedPaidAPI: false)
        var anonymousResult = IPQualityResult()
        try useCase.aggregate(results: [anonymous], into: &anonymousResult)
        precondition(anonymousResult.asn == "AS64502 Anonymous ISP" && anonymousResult.organization == "Anonymous ISP")
        precondition(anonymousResult.country == "France" && anonymousResult.countryCode == nil, "Country names must not be treated as ISO codes")
        precondition(anonymousResult.ipType == .unknown && anonymousResult.multiSourceData?.riskScores.isEmpty == true)

        let sourceError = IPDataSourceService.DataSourceResult(source: .ipapi, ipType: nil, riskScore: nil, riskFactors: nil,
            error: IPAPIRateLimit.LimitError.recoveryTimeUnavailable(retryAfter: nil), skipped: false, usedPaidAPI: false)
        try useCase.aggregate(results: [.skipped(source: .ipregistry), sourceError, info], into: &basicResult)
        precondition(useCase.sourceFailures.count == 1 && useCase.sourceFailures[0].hasPrefix("ipapi.is: "))
        precondition(useCase.sourceFailures[0].contains("HTTP 429"), "A partial result must preserve each provider's real failure reason")
        do {
            try useCase.aggregate(results: [sourceError], into: &basicResult)
            fatalError("All failed sources must fail the aggregate")
        } catch MultiSourceAggregationUseCase.AggregationError.allSourcesFailed {
            precondition(useCase.sourceFailures.count == 1, "Total failure must retain the source-specific reason")
        }
        try useCase.aggregate(results: [info], into: &basicResult)
        precondition(useCase.sourceFailures.isEmpty, "A later successful run must not retain stale errors")

        print("IP data-source parsing and aggregation checks passed")
    }
}
