//
//  SceneConfigSheet.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/25.
//  Updated by SlippinDylan on 2026/01/06 - P2-6 修复
//  Updated by SlippinDylan on 2026/01/08 - 修复滚动问题，Form 改为 VStack
//

import SwiftUI

struct SceneConfigSheet: View {
    @Environment(WindowCoordinator.self) private var windowCoordinator
    @Binding var scene: NetworkScene?

    @State private var hasLoadedScene = false
    @State private var sceneName = ""
    @State private var routerIP = ""
    @State private var routerMAC = ""
    @State private var selectedApps: [String] = []
    @State private var showIPError = false
    @State private var showMACError = false

    let isEditing: Bool
    let onCancel: () -> Void
    let onSave: (NetworkScene) throws -> Void

    var body: some View {
        PopoverDetailPage(
            width: min(DesignSystem.Window.width, windowCoordinator.maximumContentWidth ?? DesignSystem.Window.width),
            maximumHeight: windowCoordinator.maximumDetailHeight,
            onSizeChange: windowCoordinator.setContentSize
        ) {
            SheetHeader(
                title: isEditing ? L10n.string("编辑场景") : L10n.string("添加场景"),
                action: .save,
                isEnabled: isFormValid,
                onBack: onCancel,
                onAction: saveScene
            )
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                // Section 1: 场景名称
                FormSection(title: "场景名称") {
                    TextField("输入场景名称", text: $sceneName)
                        .kairosTextField()
                }

                // Section 2: 路由器配置
                FormSection(title: "路由器配置") {
                    VStack(alignment: .leading, spacing: 12) {
                        // 路由器 IP
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("路由器 IP", text: $routerIP)
                                .kairosTextField(isInvalid: showIPError)
                                .onChange(of: routerIP) { _, _ in
                                    showIPError = false
                                }

                            if showIPError {
                                Text("IP 地址格式不正确")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        // MAC 地址
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("MAC 地址", text: $routerMAC)
                                .kairosTextField(isInvalid: showMACError)
                                .onChange(of: routerMAC) { _, _ in
                                    showMACError = false
                                }

                            if showMACError {
                                Text("MAC 地址格式不正确")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                // Section 3: 控制应用
                FormSection(title: "控制应用") {
                    VStack(alignment: .leading, spacing: 8) {
                        if selectedApps.isEmpty {
                            Text("暂未添加应用")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(selectedApps, id: \.self) { app in
                                HStack {
                                    Image(nsImage: AppControlPresentation.icon(for: app))
                                        .resizable()
                                        .frame(width: 24, height: 24)

                                    Text(AppControlPresentation.name(for: app))
                                        .font(.callout)

                                    Spacer()

                                    Button {
                                        selectedApps.removeAll { $0 == app }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                            .font(.system(size: 16))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                                .help(app)
                            }
                        }

                        // 添加应用按钮
                        Button("添加应用") {
                            Task {
                                await selectApplication()
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.top, DesignSystem.Spacing.standard)
        }
        .onAppear {
            guard !hasLoadedScene else { return }
            hasLoadedScene = true
            if let scene = scene {
                sceneName = scene.name
                routerIP = scene.routerIP
                routerMAC = scene.routerMAC
                selectedApps = scene.controlApps
            }
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        if case .success = SceneValidation.appControl(name: sceneName, routerIP: routerIP,
            routerMAC: routerMAC, apps: selectedApps) { return true }
        return false
    }

    // MARK: - Actions

    /// 选择应用（P2-6 修复：使用 FilePanelHelper 替代阻塞式 NSOpenPanel.runModal()）
    private func selectApplication() async {
        let urls = await FilePanelHelper.selectApplications(
            allowMultiple: true,
            message: "选择要控制的应用"
        )

        for url in urls {
            if !selectedApps.contains(url.path) {
                selectedApps.append(url.path)
            }
        }
    }

    private func saveScene() {
        // 验证 IP 地址格式
        if !NetworkValidator.isValidIP(routerIP) {
            showIPError = true
            return
        }

        // 验证 MAC 地址格式
        if !NetworkValidator.isValidMAC(routerMAC) {
            showMACError = true
            return
        }

        // 规范化 MAC 地址（确保存储格式统一）
        guard case .success(let normalizedMAC) = SceneValidation.appControl(name: sceneName,
            routerIP: routerIP, routerMAC: routerMAC, apps: selectedApps) else { return }

        let newScene = NetworkScene(
            id: scene?.id ?? UUID(),
            name: sceneName,
            routerIP: routerIP,
            routerMAC: normalizedMAC,
            controlApps: selectedApps,
            isEnabled: scene?.isEnabled ?? false
        )
        do {
            try onSave(newScene)
            onCancel()
        } catch {
            Toast.error(error.localizedDescription)
        }
    }
}

// MARK: - Form Section Component

/// 表单分组组件（模拟 Form Section 样式）
private struct FormSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(title))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            content
        }
    }
}
