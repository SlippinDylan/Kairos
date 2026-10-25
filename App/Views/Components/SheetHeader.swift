import SwiftUI

struct SheetHeader: View {
    static var height: CGFloat { PopoverPageHeader<EmptyView>.height }

    enum Action {
        case back
        case close
        case save
    }

    let title: String
    let action: Action
    var isEnabled = true
    var onBack: (() -> Void)?
    var onCancel: (() -> Void)?
    let onAction: () -> Void

    var body: some View {
        PopoverPageHeader {
            HStack(spacing: 12) {
                if action == .back {
                    backButton(action: onAction).disabled(!isEnabled)
                } else if let onBack {
                    backButton(action: onBack)
                }
                Text(title).font(.headline)
                Spacer()
                if let onCancel {
                    Button("取消", systemImage: "xmark", action: onCancel)
                        .labelStyle(.iconOnly)
                        .buttonStyle(NavigationActionButtonStyle())
                        .help("取消")
                } else if action == .save {
                    Button("保存", systemImage: "checkmark", action: onAction)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.white)
                        .buttonStyle(NavigationActionButtonStyle(tint: .blue))
                        .disabled(!isEnabled)
                        .keyboardShortcut(.defaultAction)
                } else if action == .close {
                    Button("关闭", systemImage: "xmark", action: onAction)
                        .labelStyle(.iconOnly)
                        .buttonStyle(NavigationActionButtonStyle())
                        .disabled(!isEnabled)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .font(.title3)
        }
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button("取消", systemImage: "chevron.left", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(NavigationActionButtonStyle())
    }
}

/// Main navigation and detail pages reserve the same space above their content.
struct PopoverPageHeader<Content: View>: View {
    static var height: CGFloat { 60 }
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(height: Self.height - 4)
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.top, 4)
    }
}

struct NavigationActionButtonStyle: ButtonStyle {
    var diameter: CGFloat = 32
    var tint: Color?
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .glassEffect(.regular.tint(tint).interactive(), in: Circle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
    }
}
