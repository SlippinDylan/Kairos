import SwiftUI

struct GlassTabBar<Selection: Hashable>: View {
    let options: [Selection]
    @Binding var selection: Selection
    var visibleWidth: CGFloat? = nil
    let title: (Selection) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            Group {
                if let visibleWidth {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            tabButtons
                        }
                        .scrollIndicators(.hidden)
                        .frame(width: visibleWidth, height: 38)
                        .onChange(of: selection, initial: true) { _, option in
                            proxy.scrollTo(option, anchor: .center)
                        }
                    }
                } else {
                    tabButtons
                }
            }
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .accessibilityElement(children: .contain)
    }

    private var tabButtons: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                tabButton(for: option)
                    .id(option)
            }
        }
        .frame(minWidth: visibleWidth.map { $0 - 6 })
        .padding(3)
    }

    private func tabButton(for option: Selection) -> some View {
        let isSelected = selection == option

        return Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                selection = option
            }
        } label: {
            Text(title(option))
                .font(.callout.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, DesignSystem.Spacing.extraSmall)
                .frame(minWidth: 44, minHeight: 32)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Color.clear
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: Capsule())
                    .glassEffectID("tab-selection", in: selectionNamespace)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
