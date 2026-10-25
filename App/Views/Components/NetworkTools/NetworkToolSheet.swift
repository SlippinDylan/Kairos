import SwiftUI

struct NetworkToolSheet<PinnedContent: View, Content: View>: View {
    let title: String
    let width: CGFloat
    let preventsClosing: Bool
    let fitsContent: Bool
    var padsContent = true
    var maximumContentHeight: CGFloat = 720
    var progress: Double?
    var onCancel: (() -> Void)?
    let onClose: () -> Void
    let onSizeChange: (CGSize) -> Void
    @ViewBuilder let pinnedContent: () -> PinnedContent
    @ViewBuilder let content: () -> Content

    private var verticalPadding: CGFloat {
        fitsContent ? (80 - DesignSystem.Input.height) / 2 : DesignSystem.Spacing.standard
    }

    var body: some View {
        PopoverDetailPage(
            width: width,
            maximumHeight: maximumContentHeight,
            onSizeChange: onSizeChange
        ) {
            VStack(spacing: 0) {
                SheetHeader(
                    title: title,
                    action: .back,
                    isEnabled: !preventsClosing,
                    onCancel: onCancel,
                    onAction: onClose
                )
                pinnedContent()
            }
        } content: {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, padsContent ? DesignSystem.Spacing.standard : 0)
                .padding(.vertical, padsContent ? verticalPadding : 0)
                .background {
                    if let progress {
                        DNSProgressBackdrop(progress: progress)
                            .animation(.linear(duration: 0.35), value: progress)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                .padding(.horizontal, DesignSystem.Spacing.standard)
        }
    }
}
