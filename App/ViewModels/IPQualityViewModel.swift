//
//  IPQualityViewModel.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/29.
//  Refactored on 2025/12/31 - Simplified to MVVM + UseCase pattern
//

import Foundation
import Network
import Observation

// MARK: - Detection State
enum DetectionState {
    case idle       // 初始状态：显示大圆形按钮
    case detecting  // 检测中：显示进度圈和动画
    case completed  // 完成：显示详细结果
}

@MainActor
@Observable
final class IPQualityViewModel {
    static let shared = IPQualityViewModel()

    // MARK: - Published Properties
    var result: IPQualityResult?
    var isLoading = false
    var errorMessage: String?
    var sourceFailures: [String] = []
    var detectionState: DetectionState = .idle

    @ObservationIgnored
    private var detectionTask: Task<Void, Never>?

    // MARK: - Dependencies
    private let progressCoordinator: ProgressCoordinator
    private let ipDetectionUseCase: IPDetectionUseCase

    private init() {
        // Initialize dependencies
        let session = URLSession(configuration: {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 30
            return config
        }())

        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        // Create use cases
        self.progressCoordinator = ProgressCoordinator()

        let ipDataFetchingUseCase = IPDataFetchingUseCase(
            session: session,
            userAgent: userAgent
        )

        let streamingTestUseCase = StreamingTestUseCase(
            session: session,
            userAgent: userAgent
        )

        let emailTestUseCase = EmailTestUseCase()

        let multiSourceAggregationUseCase = MultiSourceAggregationUseCase()

        self.ipDetectionUseCase = IPDetectionUseCase(
            progressCoordinator: progressCoordinator,
            ipDataFetchingUseCase: ipDataFetchingUseCase,
            streamingTestUseCase: streamingTestUseCase,
            emailTestUseCase: emailTestUseCase,
            multiSourceAggregationUseCase: multiSourceAggregationUseCase
        )
    }

    // MARK: - Progress Properties (delegate to ProgressCoordinator)

    /// 当前进度（从 ProgressCoordinator 读取）
    var currentProgress: Double {
        progressCoordinator.progress
    }

    /// 当前任务（从 ProgressCoordinator 读取）
    var currentTaskDescription: String {
        progressCoordinator.currentTask
    }

    // MARK: - Main Detection Function
    func startDetection() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        sourceFailures = []
        result = nil
        progressCoordinator.reset()
        detectionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runDetection()
        }
    }

    func cancelDetection() {
        detectionTask?.cancel()
    }

    func resetDetection() {
        cancelDetection()
        detectionState = .idle
        result = nil
        errorMessage = nil
        sourceFailures = []
        progressCoordinator.reset()
    }

    private func runDetection() async {
        AppLogger.debug("开始IP质量检测")
        // Keep the run exclusive until cancellation has unwound all awaited work.
        defer {
            isLoading = false
            detectionTask = nil
        }

        do {
            try Task.checkCancellation()
            let detectionResult = try await ipDetectionUseCase.executeDetection()
            try Task.checkCancellation()
            result = detectionResult
            sourceFailures = ipDetectionUseCase.sourceFailures
            AppLogger.info("IP质量检测完成")
        } catch is CancellationError {
            AppLogger.info("IP质量检测已取消")
        } catch {
            guard !Task.isCancelled else {
                AppLogger.info("IP质量检测已取消")
                return
            }
            sourceFailures = ipDetectionUseCase.sourceFailures
            errorMessage = L10n.format("检测失败: %@", error.localizedDescription)
            AppLogger.error("IP质量检测失败: \(error.localizedDescription)")
        }
    }
}
