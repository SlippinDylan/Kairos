//
//  IPQueryService.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation

/// IP查询服务
@MainActor
final class IPQueryService {
    private let session: URLSession
    private let apiKeyManager: APIKeyManager
    private let ipapiRateLimit: IPAPIRateLimit
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    convenience init() {
        self.init(apiKeyManager: .shared)
    }

    init(session: URLSession? = nil, apiKeyManager: APIKeyManager, ipapiRateLimit: IPAPIRateLimit = .shared) {
        self.apiKeyManager = apiKeyManager
        self.ipapiRateLimit = ipapiRateLimit
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Public API

    /// 查询IP详细信息
    /// - Parameter ip: IP地址
    /// - Returns: IP查询结果
    /// - Throws: 网络错误或解析错误
    ///
    /// **P2-3 修复**：复用 `NetworkValidator.isValidIP()` 进行 IP 验证，移除重复代码
    func fetchIPInfo(ip: String) async throws -> IPQueryResult {
        // 验证IP地址格式（复用 NetworkValidator）
        guard NetworkValidator.isValidIP(ip) else {
            throw IPQueryError.invalidIPAddress
        }

        // 调用ipapi.is API
        let apiResponse = try await fetchFromIPAPI(ip: ip)

        // 转换为查询结果
        return try convertToQueryResult(from: apiResponse)
    }

    // MARK: - Private Methods

    /// 从ipapi.is获取数据
    private func fetchFromIPAPI(ip: String) async throws -> IPAPIQueryResponse {
        var components = URLComponents(string: "https://api.ipapi.is/")
        var queryItems = [URLQueryItem(name: "q", value: ip)]
        let key = apiKeyManager.ipapiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            queryItems.append(URLQueryItem(name: "key", value: key))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw IPQueryError.invalidURL
        }

        let request = URLRequest(url: url).withStandardHeaders(userAgent: userAgent)
        try await ipapiRateLimit.check(apiKey: key)
        let (data, response) = try await session.data(for: request)

        // 检查HTTP状态码
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IPQueryError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw await ipapiRateLimit.record(response: httpResponse, apiKey: key)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw IPQueryError.httpError(statusCode: httpResponse.statusCode)
        }

        // 解析JSON
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(IPAPIQueryResponse.self, from: data)
        } catch {
            throw IPQueryError.decodingError(error)
        }
    }

    private func convertToQueryResult(from response: IPAPIQueryResponse) throws -> IPQueryResult {
        guard NetworkValidator.isValidIP(response.ip) else {
            throw IPQueryError.invalidResponse
        }
        let detail = response.location
        var coordinates: Coordinates?
        if let latitude = detail.latitude, let longitude = detail.longitude {
            guard latitude.isFinite, longitude.isFinite,
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else {
                throw IPQueryError.invalidResponse
            }
            coordinates = Coordinates(latitude: latitude, longitude: longitude)
        }

        let location = LocationInfo(
            state: detail.state.map { GeoUtils.translateStateName($0) },
            city: detail.city,
            zipCode: detail.zip,
            countryCode: detail.countryCode?.uppercased(),
            countryName: detail.country,
            continentCode: detail.continent?.uppercased(),
            continentName: detail.continent.map { GeoUtils.continentName(from: $0) }
        )

        // ASN registration country is independent of the address's usage location.
        let registrationCountry = response.registrationCountryCode.map { rawCode in
            let code = rawCode.uppercased()
            return "\(GeoUtils.countryFlag(countryCode: code))[\(code)]"
        }
        return IPQueryResult(
            ip: response.ip,
            asn: response.asn ?? "—",
            organization: response.organization ?? "—",
            coordinates: coordinates,
            location: location,
            registrationCountry: registrationCountry ?? "—",
            timezone: detail.timezone ?? "—",
            ipType: response.usageType.map { GeoUtils.ipTypeDisplayName(from: $0) } ?? "—"
        )
    }
}

// MARK: - Error Types

enum IPQueryError: LocalizedError {
    case invalidIPAddress
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidIPAddress:
            return L10n.string("无效的IP地址格式")
        case .invalidURL:
            return L10n.string("无效的URL")
        case .invalidResponse:
            return L10n.string("无效的服务器响应")
        case .httpError(let statusCode):
            return L10n.format("HTTP错误: %lld", statusCode)
        case .decodingError(let error):
            return L10n.format("数据解析失败: %@", error.localizedDescription)
        }
    }
}
