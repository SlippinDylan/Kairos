import SwiftUI

/// Measures fixed header and scrollable content without placing the scroller inside content margins.
struct PopoverDetailPage<Header: View, Content: View>: View {
    let width: CGFloat
    let maximumHeight: CGFloat
    let onSizeChange: (CGSize) -> Void
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    @State private var headerSize: CGSize?
    @State private var contentSize: CGSize?

    private var headerHeight: CGFloat { headerSize?.height ?? SheetHeader.height }
    private var availableContentHeight: CGFloat {
        max(0, maximumHeight - headerHeight - DesignSystem.Spacing.standard)
    }
    private var measuredContentHeight: CGFloat? {
        guard let contentSize, abs(contentSize.width - width) < 0.5 else { return nil }
        return contentSize.height
    }
    private var viewportHeight: CGFloat {
        min(measuredContentHeight ?? availableContentHeight, availableContentHeight)
    }
    private var pageHeight: CGFloat { headerHeight + viewportHeight + DesignSystem.Spacing.standard }
    private var measuredPageSize: CGSize? {
        guard let headerSize, abs(headerSize.width - width) < 0.5,
              measuredContentHeight != nil else { return nil }
        return CGSize(width: width, height: pageHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            header()
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { headerSize = $0 }

            KairosScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { contentSize = $0 }
            }
            .defaultScrollAnchor(.top)
            .frame(height: viewportHeight)
        }
        .padding(.bottom, DesignSystem.Spacing.standard)
        .frame(width: width, height: pageHeight, alignment: .top)
        .onChange(of: measuredPageSize, initial: true) { _, size in
            // Wait for both measurements rather than resizing through an estimated result height.
            if let size { onSizeChange(size) }
        }
    }
}
