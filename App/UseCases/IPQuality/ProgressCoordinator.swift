//
//  ProgressCoordinator.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/31.
//  Refactored from IPQualityViewModel.swift - Progress management logic
//

import Foundation
import SwiftUI
import Observation

/// 进度协调器 - 负责平滑进度更新和任务状态管理
///
/// ## 架构说明
/// - 使用 SwiftUI 原生动画系统（`withAnimation`）实现进度平滑过渡
/// - 避免手动实现帧动画（Task.sleep）导致的CPU浪费和复杂性
/// - 符合 Swift 6+ 并发最佳实践
@MainActor
@Observable
final class ProgressCoordinator {
    // MARK: - Published Properties

    /// 当前进度值 (0.0-1.0)
    ///
    /// 通过 `withAnimation` 修改此属性，SwiftUI 会自动处理动画插值
    var progress: Double = 0.0

    /// 当前任务描述
    var currentTask: String = ""

    // MARK: - Public Methods

    // Apply progress in the owning run, without a detached write surviving cancellation.
    func smoothUpdateProgress(
        to target: Double,
        duration: TimeInterval = 0.3,
        curve: Animation = .easeInOut
    ) {
        // 边界检查：确保进度值在合法范围内
        let clampedTarget = min(max(target, 0.0), 1.0)

        withAnimation(curve.speed(1.0 / duration)) {
            progress = clampedTarget
        }
    }

    /// 重置进度和任务状态
    ///
    /// 不使用动画，立即重置到初始状态
    func reset() {
        progress = 0.0
        currentTask = ""
    }

    /// 更新当前任务描述
    ///
    /// - Parameter task: 任务描述文本
    func updateTask(_ task: String) {
        currentTask = task
    }
}
