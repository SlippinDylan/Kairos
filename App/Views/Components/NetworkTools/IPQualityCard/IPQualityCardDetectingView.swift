//
//  IPQualityCardDetectingView.swift
//  Kairos
//
//  Created by SlippinDylan on 2026/01/07.
//  网络工具 - IP质量卡片 - 检测中状态
//

import SwiftUI

/// 网络工具卡片 - 检测中状态视图
///
/// ## 设计说明
/// - 适配GroupBox内部布局（紧凑型）
/// - 与原IP质量tab的DetectingStateView功能一致，但UI简化
/// - 原IP质量tab：圆形进度圈（180x180）+ 脉冲动画 + 垂直居中
/// - 网络工具卡片：线性进度条 + 百分比文字 + 左对齐
struct IPQualityCardDetectingView: View {
    // MARK: - Properties

    let progress: Double
    let currentTask: String

    // MARK: - Body

    var body: some View {
        Text("\(currentTask) · \(Int(progress * 100))%")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.9))
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .frame(height: 64)
    }
}

// MARK: - Preview

#Preview {
    GroupBox {
        IPQualityCardDetectingView(
            progress: 0.65,
            currentTask: "检测流媒体解锁..."
        )
        .padding()
    } label: {
        Text("IP 质量")
    }
    .frame(width: 800)
}
