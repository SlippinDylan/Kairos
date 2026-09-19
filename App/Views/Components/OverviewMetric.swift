import SwiftUI
import AppKit

enum OverviewMetricIcon {
    case symbol(String, Color)
    case application(NSImage)
}

struct OverviewCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DesignSystem.Spacing.standard)
            .background(.blue.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(.blue.opacity(0.1), lineWidth: 1)
            }
    }
}

struct OverviewMetricDivider: View {
    var body: some View {
        Divider()
            .frame(height: 48)
            .padding(.horizontal, DesignSystem.Spacing.standard)
    }
}

struct OverviewMetric: View {
    let title: String
    let value: String
    let icon: OverviewMetricIcon
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            iconView

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.extraSmall) {
                Text(L10n.string(title))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .symbol(let name, let tint):
            Image(systemName: name)
                .font(.system(size: 24))
                .foregroundStyle(tint)
        case .application(let image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
        }
    }
}
