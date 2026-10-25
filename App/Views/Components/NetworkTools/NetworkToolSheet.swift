import SwiftUI

struct NetworkToolSheet<Content: View>: View {
    let title: String
    let hostWindowSize: CGSize
    let preventsClosing: Bool
    let fitsContent: Bool
    var padsContent = true
    var balancesHeader = false
    var maximumContentHeight: CGFloat = 720
    var progress: Double?
    var onCancel: (() -> Void)?
    let onClose: () -> Void
    let onSizeChange: (CGSize) -> Void
    @ViewBuilder let content: () -> Content
    @State private var measuredSize: CGSize?

    private var headerHeight: CGFloat { SheetHeader.height }
    private var footerHeight: CGFloat { balancesHeader ? headerHeight : 0 }

    private var verticalPadding: CGFloat {
        fitsContent ? (80 - DesignSystem.Input.height) / 2 : DesignSystem.Spacing.standard
    }

    private var maximumHeight: CGFloat {
        min(hostWindowSize.height * 0.8, max(0, maximumContentHeight - headerHeight - footerHeight - DesignSystem.Spacing.standard))
    }
    private var contentWidth: CGFloat { hostWindowSize.width - DesignSystem.Spacing.standard * 2 }
    private var contentHeight: CGFloat? {
        guard let measuredSize, abs(measuredSize.width - contentWidth) < 0.5 else { return nil }
        return measuredSize.height
    }
    private var visibleContentHeight: CGFloat { min(contentHeight ?? maximumHeight, maximumHeight) }
    private var totalHeight: CGFloat { headerHeight + visibleContentHeight + footerHeight + DesignSystem.Spacing.standard }
    private var measuredPageSize: CGSize? {
        guard contentHeight != nil else { return nil }
        return CGSize(width: hostWindowSize.width, height: totalHeight)
    }

    private var measuredContent: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, padsContent ? DesignSystem.Spacing.standard : 0)
            .padding(.vertical, padsContent ? verticalPadding : 0)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { measuredSize = $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: title,
                action: .back,
                isEnabled: !preventsClosing,
                onCancel: onCancel,
                onAction: onClose
            )

            contentArea
                .frame(width: contentWidth, height: visibleContentHeight, alignment: .top)
                .background {
                    if let progress {
                        DNSProgressBackdrop(progress: progress)
                            .animation(.linear(duration: 0.35), value: progress)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                .padding(.bottom, footerHeight)
        }
        .padding(.bottom, DesignSystem.Spacing.standard)
        .frame(width: hostWindowSize.width)
        .frame(height: totalHeight, alignment: .top)
        .onChange(of: measuredPageSize, initial: true) { _, size in
            // A newly opened result must not resize through an estimated compact height.
            if let size { onSizeChange(size) }
        }
    }

    private var contentArea: some View {
        // Preserve input focus and local state when content crosses the viewport height.
        ScrollView { measuredContent }
            .defaultScrollAnchor(.top)
    }
}
