import SwiftUI

struct PopoverNavigationBar<Actions: View>: View {
    @Environment(WindowCoordinator.self) private var coordinator
    @State private var availableWidth = DesignSystem.Window.width - DesignSystem.Spacing.standard * 2
    @ViewBuilder var actions: () -> Actions

    private var tabWidth: CGFloat { max(44, availableWidth - (32 + 12) * 2) }

    var body: some View {
        PopoverPageHeader {
            ZStack {
                ViewThatFits(in: .horizontal) {
                    tabs()
                    tabs(visibleWidth: tabWidth)
                }
                .frame(width: tabWidth)
                HStack {
                    Spacer(minLength: 0)
                    actions()
                        .buttonStyle(NavigationActionButtonStyle())
                        .font(.title3)
                }
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        }
    }

    private func tabs(visibleWidth: CGFloat? = nil) -> some View {
        GlassTabBar(
            options: [0, 6, 1, 4, 5],
            selection: Binding(get: { coordinator.selectedTab }, set: { coordinator.selectedTab = $0 }),
            visibleWidth: visibleWidth
        ) { tab in
            switch tab {
            case 6: L10n.string("DNS 控制")
            case 1: L10n.string("网络工具")
            case 4: L10n.string("设置")
            case 5: L10n.string("关于")
            default: L10n.string("应用控制")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
