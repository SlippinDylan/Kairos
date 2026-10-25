import SwiftUI

struct IPQualityNetworkToolCard: View {
    @State private var viewModel = IPQualityViewModel.shared
    @State private var isHovered = false

    var body: some View {
        Group {
            if viewModel.isLoading {
                VStack(spacing: 4) {
                    Text(viewModel.currentProgress, format: .percent.precision(.fractionLength(0)))
                        .font(.headline.monospacedDigit())
                    Text(viewModel.currentTaskDescription)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: DesignSystem.Input.height)
                .padding(.horizontal, 56)
                .padding(.vertical, 22)
                .accessibilityElement(children: .combine)
            } else if let result = viewModel.result {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(result.detectedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("重新检测", action: viewModel.startDetection)
                            .buttonStyle(.glassProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                    sourceFailureMessages
                    IPQualityCardCompletedView(result: result)
                }
                .padding(16)
            } else {
                VStack(spacing: 0) {
                    Button(action: viewModel.startDetection) {
                        HStack(spacing: 12) {
                            Image(systemName: "shield.checkered")
                                .font(.title2)
                                .foregroundStyle(.cyan)
                                .shadow(color: .cyan.opacity(0.6), radius: 8)
                            Text("开始检测")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .padding(.horizontal, 56)
                        .background {
                            LinearGradient(
                                colors: [Color(red: 0.025, green: 0.055, blue: 0.10), Color(red: 0.03, green: 0.24, blue: isHovered ? 0.55 : 0.42)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .onHover { isHovered = $0 }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                        sourceFailureMessages.padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private var sourceFailureMessages: some View {
        ForEach(viewModel.sourceFailures, id: \.self) { failure in
            Text(failure)
                .font(.caption)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}
