//
//  SceneCard.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

struct SceneCard: View {
    @Binding var scene: NetworkScene
    let isMatched: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                HStack(spacing: DesignSystem.Spacing.small) {
                    Text(scene.name)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Circle()
                        .fill(isMatched ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(isMatched ? Text("已匹配") : Text("未匹配"))
                        .help(isMatched ? Text("已匹配") : Text("未匹配"))

                    Spacer(minLength: DesignSystem.Spacing.small)

                    HStack(spacing: DesignSystem.Spacing.small) {
                        Toggle("应用控制", isOn: $scene.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.mini)
                            .help("应用控制")

                        Button(action: onEdit) {
                            Label("编辑", systemImage: "square.and.pencil")
                        }

                        Button(role: .destructive, action: onDelete) {
                            Label("删除", systemImage: "trash")
                        }
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.glass)
                    .fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.standard) {
                        gatewayDetail(title: "网关 IP", value: scene.routerIP, symbol: "point.3.connected.trianglepath.dotted")
                        Divider().padding(.vertical, DesignSystem.Spacing.extraSmall)
                        gatewayDetail(title: "网关 MAC", value: scene.routerMAC, symbol: "cable.connector")
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if !scene.controlApps.isEmpty {
                        Divider()

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)],
                            alignment: .leading,
                            spacing: DesignSystem.Spacing.small
                        ) {
                            ForEach(scene.controlApps, id: \.self) { app in
                                HStack(spacing: DesignSystem.Spacing.small) {
                                    Image(nsImage: AppControlPresentation.icon(for: app))
                                        .resizable()
                                        .frame(width: 20, height: 20)

                                    Text(AppControlPresentation.name(for: app))
                                        .font(.callout)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(app)
                            }
                        }
                    }
                }
                .padding(DesignSystem.Spacing.medium)
                .background(
                    Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                )
            }
            .padding(DesignSystem.Spacing.small)
        }
    }

    private func gatewayDetail(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.extraSmall) {
            Label(L10n.string(title), systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
