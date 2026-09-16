//
//  SceneCard.swift
//  Enodia
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

struct SceneCard: View {
    @Binding var scene: NetworkScene
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                HStack(spacing: DesignSystem.Spacing.medium) {
                    Text(scene.name)
                        .font(.headline)

                    Spacer()

                    Toggle("", isOn: $scene.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)

                    Menu {
                        Button {
                            onEdit()
                        } label: {
                            Label("编辑", systemImage: "square.and.pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 15))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("场景操作")
                }

                HStack(spacing: DesignSystem.Spacing.large) {
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Image(systemName: "network")
                            .frame(width: 16)
                        Text(scene.routerIP)
                    }

                    HStack(spacing: DesignSystem.Spacing.small) {
                        Image(systemName: "externaldrive.connected.to.line.below")
                            .frame(width: 16)
                        Text(scene.routerMAC)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if !scene.controlApps.isEmpty {
                    Divider()
                        .padding(.top, DesignSystem.Spacing.extraSmall)

                    HStack(spacing: DesignSystem.Spacing.standard) {
                        Text("控制应用")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: DesignSystem.Spacing.standard) {
                            ForEach(scene.controlApps, id: \.self) { app in
                                HStack(spacing: DesignSystem.Spacing.small) {
                                    if let icon = getAppIcon(appName: app) {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                    } else {
                                        Image(systemName: "app.fill")
                                            .frame(width: 20, height: 20)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(app)
                                        .font(.callout)
                                }
                            }
                        }

                        Spacer()
                    }
                }
            }
            .padding(DesignSystem.Spacing.standard)
        }
    }

    // 获取应用图标
    private func getAppIcon(appName: String) -> NSImage? {
        let workspace = NSWorkspace.shared
        let appPath = workspace.urlForApplication(withBundleIdentifier: "com.apple.\(appName)") ??
                      workspace.urlForApplication(withBundleIdentifier: appName) ??
                      URL(fileURLWithPath: "/Applications/\(appName).app")

        return workspace.icon(forFile: appPath.path)
    }
}
