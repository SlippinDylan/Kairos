import SwiftUI

struct ActionTextField: View {
    let placeholder: String
    @Binding var text: String
    let actionTitle: String
    let loadingTitle: String?
    let isLoading: Bool
    let isActionDisabled: Bool
    let onClear: () -> Void
    let action: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            HStack(spacing: 4) {
                TextField(L10n.string(placeholder), text: $text)
                    .disabled(isLoading)
                    .onSubmit {
                        if !isActionDisabled { action() }
                    }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else if !text.isEmpty {
                    Button {
                        text = ""
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.medium)
                            .frame(width: DesignSystem.Input.actionHeight, height: DesignSystem.Input.actionHeight)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("清空"))
                    .help("清空")
                }
            }
            .kairosTextField()

            Button(isLoading ? L10n.string(loadingTitle ?? actionTitle) : L10n.string(actionTitle)) {
                action()
            }
            .buttonStyle(InputActionButtonStyle())
            .disabled(isActionDisabled)
        }
    }
}
