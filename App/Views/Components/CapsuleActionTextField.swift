import SwiftUI

struct CapsuleActionTextField: View {
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
            TextField(L10n.string(placeholder), text: $text)
                .textFieldStyle(.plain)
                .disabled(isLoading)
                .onSubmit {
                    if !isActionDisabled {
                        action()
                    }
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
                }
                .buttonStyle(.plain)
                .help("清空")
            }

            Button(isLoading ? L10n.string(loadingTitle ?? actionTitle) : L10n.string(actionTitle)) {
                action()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.regular)
            .disabled(isActionDisabled)
        }
        .padding(.leading, DesignSystem.Spacing.standard)
        .padding(.trailing, DesignSystem.Spacing.extraSmall)
        .frame(height: 40)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        }
    }
}
