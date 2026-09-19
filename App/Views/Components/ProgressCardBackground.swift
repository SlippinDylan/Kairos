import SwiftUI

struct ProgressCardBackground: View {
    let progress: Double?

    var body: some View {
        ZStack {
            GroupBox {
                Color.clear
            }

            if let progress {
                ProgressCardFill(progress: progress)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }
}

private struct ProgressCardFill: View {
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = proxy.size.width * clampedProgress

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: fillWidth)
                .overlay {
                    if !reduceMotion, fillWidth > 0 {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                            let duration = 1.4
                            let phase = CGFloat(
                                context.date.timeIntervalSinceReferenceDate
                                    .truncatingRemainder(dividingBy: duration) / duration
                            )

                            GeometryReader { shimmerProxy in
                                let shimmerWidth = min(max(shimmerProxy.size.width * 0.25, 28), 72)

                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.65), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: shimmerWidth)
                                .offset(
                                    x: -shimmerWidth
                                        + (shimmerProxy.size.width + shimmerWidth * 2) * phase
                                )
                            }
                        }
                    }
                }
                .clipped()
                .overlay(alignment: .trailing) {
                    if fillWidth >= 2 {
                        Capsule()
                            .fill(.cyan.opacity(0.8))
                            .frame(width: 2, height: proxy.size.height * 0.72)
                            .shadow(color: .cyan.opacity(0.75), radius: 6)
                    }
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: clampedProgress)
        }
        .accessibilityHidden(true)
    }
}
