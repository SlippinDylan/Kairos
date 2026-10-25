//
//  DNSSceneCard.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

struct DNSSceneCard: View {
    @Binding var scene: DNSScene
    let isMatched: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onHelperNotInstalled: (() -> Void)? = nil

    @State private var dnsManager = DNSManager.shared

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
                        Toggle("DNS 控制", isOn: Binding(
                            get: { scene.isEnabled },
                            set: { newValue in
                                if newValue && !dnsManager.isHelperInstalled {
                                    onHelperNotInstalled?()
                                } else {
                                    scene.isEnabled = newValue
                                }
                            }
                        ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.mini)
                            .help("DNS 控制")

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

                HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
                    gatewayDetail(title: "网关 IP", value: scene.routerIP, symbol: "point.3.connected.trianglepath.dotted")
                    Divider().padding(.vertical, DesignSystem.Spacing.extraSmall)
                    gatewayDetail(title: "网关 MAC", value: scene.routerMAC, symbol: "cable.connector")

                    Divider().padding(.vertical, DesignSystem.Spacing.extraSmall)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.extraSmall) {
                        Label("目标 DNS", systemImage: "server.rack")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        dnsServer(scene.primaryDNS)
                        if !scene.secondaryDNS.isEmpty {
                            dnsServer(scene.secondaryDNS)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
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

    private func dnsServer(_ address: String) -> some View {
        Text(address)
            .font(.system(.callout, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .help(address)
    }
}
