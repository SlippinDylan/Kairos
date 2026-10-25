//
//  MultiSourceAggregationUseCase.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/31.
//  Refactored from IPQualityViewModel.swift - Multi-source data aggregation logic
//
//  ## 2026/01/07 重构
//  - 统一免费/付费 API 逻辑
//  - 删除 ipdata 和 IPQS（纯付费）
//  - 有免费 API 的数据源：未配置时用免费 API，配置后用付费 API
//  - 纯付费数据源：未配置时跳过
//

import Foundation

/// 多数据源聚合用例 - 负责从多个数据源收集和聚合 IP 信息
///
/// ## 数据源列表
/// ### 有免费 API（配置 Key 后使用付费版）
/// 1. IPinfo - 免费 widget API / 付费官方 API
/// 2. ipapi.is - 匿名精简数据 / 配置 Key 后完整数据（额度由账户决定）
/// 3. DB-IP - 免费基础数据 / 付费完整数据
/// 4. IPWHOIS - 免费 10k/月 / 付费无限制
///
/// ### 纯付费数据源
/// 5. AbuseIPDB - 需要 API Key
/// 6. IP2Location - 需要 API Key
/// 7. ipregistry - 需要 API Key
@MainActor
class MultiSourceAggregationUseCase {
    enum AggregationError: LocalizedError {
        case allSourcesFailed

        var errorDescription: String? {
            L10n.string("所有 IP 质量数据源均请求失败，请检查网络或数据源配置后重试。")
        }
    }

    private let ipDataSourceService: IPDataSourceService
    private let apiKeyManager: APIKeyManager
    private(set) var sourceFailures: [String] = []

    convenience init() {
        self.init(ipDataSourceService: IPDataSourceService(), apiKeyManager: .shared)
    }

    init(ipDataSourceService: IPDataSourceService, apiKeyManager: APIKeyManager) {
        self.ipDataSourceService = ipDataSourceService
        self.apiKeyManager = apiKeyManager
    }

    // MARK: - Multi-Source Data Fetching

    func resetSourceFailures() {
        sourceFailures = []
    }

    /// 从多个数据源获取 IP 信息
    ///
    /// ## 2026/01/07 重构
    /// - 合并了原 IPDetectionUseCase 中的 Step 2-4 调用
    /// - 现在只调用一次 API，避免重复请求
    /// - 同时填充主结果的基础信息和多数据源对比数据
    ///
    /// - Parameters:
    ///   - ip: IP 地址
    ///   - result: IP 质量检测结果（会被修改）
    func fetchMultiSourceData(ip: String, into result: inout IPQualityResult) async throws {
        resetSourceFailures()
        // 使用 IPDataSourceService 并发获取所有数据源
        let results = await ipDataSourceService.fetchAllSources(ip: ip, apiKeyManager: apiKeyManager)
        try Task.checkCancellation()
        try aggregate(results: results, into: &result)
    }

    func aggregate(results: [IPDataSourceService.DataSourceResult], into result: inout IPQualityResult) throws {
        var multiSource = MultiSourceData()
        sourceFailures = IPDataSourceService.DataSource.allCases.compactMap { source in
            guard let error = results.first(where: { $0.source == source })?.error else { return nil }
            return "\(source.displayName): \(error.localizedDescription)"
        }
        // 统计
        let successCount = results.filter { $0.isSuccess }.count
        let skippedCount = results.filter { $0.skipped }.count
        let totalCount = results.count

        guard successCount > 0 else { throw AggregationError.allSourcesFailed }

        AppLogger.info("✅ 数据源检测完成: \(successCount)/\(totalCount) 成功, \(skippedCount) 跳过")

        // 收集数据
        let classification = collectIPTypes(from: results, into: &multiSource)
        collectRiskScores(from: results, into: &multiSource)
        collectRiskFactors(from: results, into: &multiSource)

        // ✅ 填充主结果的基础信息（从多数据源聚合）
        fillBasicInfo(from: results, multiSource: multiSource, classification: classification, into: &result)

        // 调试日志
        AppLogger.debug("📊 收集到的数据: IP类型 \(multiSource.ipTypes.count) 条, 风险评分 \(multiSource.riskScores.count) 条, 风险因子 \(multiSource.riskFactors.count) 条")

        for ipType in multiSource.ipTypes {
            AppLogger.debug("  - IP类型 [\(ipType.source)]: 使用类型=\(ipType.usageType ?? "-"), 公司类型=\(ipType.companyType ?? "-")")
        }

        for riskScore in multiSource.riskScores {
            AppLogger.debug("  - 风险评分 [\(riskScore.source)]: \(riskScore.score) (\(riskScore.level))")
        }

        for riskFactor in multiSource.riskFactors {
            AppLogger.debug("  - 风险因子 [\(riskFactor.source)]: 地区=\(riskFactor.region ?? "-"), Proxy=\(riskFactor.isProxy?.description ?? "-"), VPN=\(riskFactor.isVPN?.description ?? "-")")
        }

        result.multiSourceData = multiSource
    }

    // MARK: - Fill Basic Info

    /// 从多数据源结果填充主结果的基础信息
    ///
    /// 使用优先级策略：取第一个有效值
    private func fillBasicInfo(from results: [IPDataSourceService.DataSourceResult], multiSource: MultiSourceData, classification: IPType?, into result: inout IPQualityResult) {
        let order: [IPDataSourceService.DataSource] = [.ipinfo, .ipapi, .ipregistry, .ip2location, .ipwhois, .dbip, .abuseipdb]
        let basic = order.compactMap { source in
            results.first(where: { $0.source == source && $0.isSuccess })?.basicInfo
        }
        result.asn = basic.compactMap(\.asn).first
        result.organization = basic.compactMap(\.organization).first
        result.city = basic.compactMap(\.city).first
        result.country = basic.compactMap(\.country).first
        result.countryCode = basic.compactMap(\.countryCode).first
        result.timezone = basic.compactMap(\.timezone).first
        // Coordinates must be a complete pair from the same provider.
        let coordinates = basic.first { info in
            guard let latitude = info.latitude, let longitude = info.longitude else { return false }
            return latitude.isFinite && longitude.isFinite
                && (-90...90).contains(latitude) && (-180...180).contains(longitude)
        }
        result.latitude = coordinates?.latitude
        result.longitude = coordinates?.longitude
        // 1. 填充地区信息（从风险因子中取第一个有效值）
        for riskFactor in multiSource.riskFactors {
            if result.countryCode == nil, let region = riskFactor.region, !region.isEmpty {
                result.countryCode = region
                break
            }
        }

        result.ipType = classification ?? .unknown

        // 3. 填充风险评分（取第一个有效评分）
        if let firstRiskScore = multiSource.riskScores.first {
            result.riskScore = firstRiskScore.score
            result.riskLevel = mapToRiskLevel(score: firstRiskScore.score)
        }

        // 4. 填充风险因子（聚合所有数据源的结果，任一为 true 则为 true）
        for riskFactor in multiSource.riskFactors {
            if riskFactor.isProxy == true { result.isProxy = true }
            if riskFactor.isVPN == true { result.isVPN = true }
            if riskFactor.isTor == true { result.isTor = true }
            if riskFactor.isDatacenter == true { result.isDatacenter = true }
            if riskFactor.isAbuser == true { result.isAbuser = true }
        }

        // 5. 根据风险因子调整 IP 类型
        if result.isDatacenter {
            result.ipType = .hosting
        }
    }

    /// 根据评分计算风险等级
    private func mapToRiskLevel(score: Int) -> RiskLevel {
        switch score {
        case 0..<20:
            return .veryLow
        case 20..<40:
            return .low
        case 40..<60:
            return .medium
        case 60..<80:
            return .high
        default:
            return .veryHigh
        }
    }

    // MARK: - Private Methods

    /// 收集 IP 类型属性
    private func collectIPTypes(from results: [IPDataSourceService.DataSourceResult], into multiSource: inout MultiSourceData) -> IPType? {
        var classification: IPType?
        // 按优先级顺序：IPinfo > ipapi > ipregistry > IP2Location > AbuseIPDB
        let order: [IPDataSourceService.DataSource] = [
            .ipinfo, .ipapi, .ipregistry, .ip2location, .abuseipdb
        ]

        for source in order {
            if let result = results.first(where: { $0.source == source && $0.isSuccess }),
               let ipType = result.ipType {
                multiSource.ipTypes.append(ipType)
                if classification == nil { classification = result.classification }
            }
        }
        return classification
    }

    /// 收集风险评分
    private func collectRiskScores(from results: [IPDataSourceService.DataSourceResult], into multiSource: inout MultiSourceData) {
        // 顺序：ipapi > IP2Location > AbuseIPDB > DB-IP
        let order: [IPDataSourceService.DataSource] = [
            .ipapi, .ip2location, .abuseipdb, .dbip
        ]

        for source in order {
            if let result = results.first(where: { $0.source == source && $0.isSuccess }),
               let riskScore = result.riskScore {
                multiSource.riskScores.append(riskScore)
            }
        }
    }

    /// 收集风险因子
    private func collectRiskFactors(from results: [IPDataSourceService.DataSourceResult], into multiSource: inout MultiSourceData) {
        // Keep the existing display order and include both additional risk-bearing sources.
        let order: [IPDataSourceService.DataSource] = [
            .ipapi, .ipregistry, .ipinfo, .ipwhois, .dbip, .abuseipdb, .ip2location
        ]

        for source in order {
            if let result = results.first(where: { $0.source == source && $0.isSuccess }),
               let riskFactors = result.riskFactors {
                multiSource.riskFactors.append(riskFactors)
            }
        }
    }
}
