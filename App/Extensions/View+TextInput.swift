import SwiftUI

extension View {
    func kairosTextField(isInvalid: Bool = false) -> some View {
        modifier(KairosTextFieldModifier(isInvalid: isInvalid))
    }
}

private struct KairosTextFieldModifier: ViewModifier {
    let isInvalid: Bool
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        // Native bordered styles keep an intrinsic bezel height even inside a taller frame.
        content
            .textFieldStyle(.plain)
            .focused($isFocused)
            .padding(.horizontal, 10)
            .frame(height: DesignSystem.Input.height)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .strokeBorder(
                        isInvalid ? Color.red : isFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isFocused ? 2 : 1
                    )
                    .allowsHitTesting(false)
            }
    }
}

struct InputActionButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .frame(height: DesignSystem.Input.actionHeight)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .glassEffect(.regular.tint(prominent ? .accentColor : nil).interactive(), in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}
