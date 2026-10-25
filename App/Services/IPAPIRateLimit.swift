import Foundation

// Both tools share the provider's quota; distinct keys have distinct cooldowns.
actor IPAPIRateLimit {
    static let shared = IPAPIRateLimit()

    enum LimitError: LocalizedError, Sendable {
        case retryAfter(Date)
        case recoveryTimeUnavailable(retryAfter: String?)

        var errorDescription: String? {
            switch self {
            case .retryAfter(let date):
                return L10n.format("ipapi.is 请求额度已受限，请在 %@ 后重试。", date.formatted(date: .abbreviated, time: .standard))
            case .recoveryTimeUnavailable:
                return L10n.string("ipapi.is 返回 HTTP 429，但 Retry-After 缺失或无效，无法确定恢复时间。请检查账户额度或更换 API Key。")
            }
        }
    }

    private var limits: [String: LimitError] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func check(apiKey: String?) throws {
        let account = accountID(apiKey)
        guard let limit = limits[account] else { return }
        if case .retryAfter(let date) = limit, date <= now() {
            limits.removeValue(forKey: account)
            return
        }
        throw limit
    }

    func record(response: HTTPURLResponse, apiKey: String?) -> LimitError {
        let account = accountID(apiKey)
        let currentDate = now()
        let limit: LimitError
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
           let date = retryDate(retryAfter, from: currentDate) {
            limit = .retryAfter(date)
        } else {
            // No recovery deadline is known for this account; do not keep hitting a blocked endpoint.
            limit = .recoveryTimeUnavailable(retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
        }
        if case .retryAfter(let previous)? = limits[account],
           case .retryAfter(let next) = limit, previous > next {
            return .retryAfter(previous)
        }
        limits[account] = limit
        return limit
    }

    private func accountID(_ key: String?) -> String {
        key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func retryDate(_ value: String, from currentDate: Date) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
           let seconds = TimeInterval(value), seconds.isFinite {
            return currentDate.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.date(from: value)
    }
}
