//
//  QuitConfirmationOverlay.swift
//  Enodia
//
//  Created by SlippinDylan on 2026/01/08.
//

import SwiftUI

/// 退出确认提示覆盖层
///
/// ## 设计规范
/// - 符合 macOS 26 Liquid Glass 设计语言
/// - 使用 `glassEffect` 呈现原生 Liquid Glass
/// - 水平垂直居中显示
/// - 优雅的进入/退出动画
///
/// ## 使用方式
/// ```swift
/// ContentView()
///     .overlay {
///         QuitConfirmationOverlay()
///     }
/// ```
struct QuitConfirmationOverlay: View {

    // MARK: - State

    /// 退出确认协调器
    @State private var coordinator = QuitConfirmationCoordinator.shared

    // MARK: - Body

    var body: some View {
        ZStack {
            // 确认提示卡片
            if coordinator.isShowingConfirmation {
                confirmationCard
                    .transition(.confirmationTransition)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: coordinator.isShowingConfirmation)
    }

    // MARK: - Confirmation Card

    /// 确认提示卡片
    private var confirmationCard: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: "power")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)

            // 提示文字
            Text(coordinator.confirmationMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

// MARK: - Custom Transition

private extension AnyTransition {
    /// 确认提示专用过渡动画
    ///
    /// 组合效果：
    /// - 缩放：从 0.8 → 1.0
    /// - 透明度：从 0 → 1
    /// - 模糊：从模糊 → 清晰
    static var confirmationTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        QuitConfirmationOverlay()
    }
    .frame(width: 600, height: 400)
    .onAppear {
        // 模拟显示确认提示
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            _ = QuitConfirmationCoordinator.shared.requestQuit()
        }
    }
}
