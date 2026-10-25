//
//  DNSSceneConfigSheet.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/25.
//  Updated by SlippinDylan on 2026/01/08 - 修复滚动问题，Form 改为 VStack
//

import SwiftUI

struct DNSSceneConfigSheet: View {
    @Environment(WindowCoordinator.self) private var windowCoordinator

    @State private var hasLoadedScene = false
    @State private var sceneName = ""
    @State private var routerIP = ""
    @State private var routerMAC = ""
    @State private var primaryDNS = ""
    @State private var secondaryDNS = ""
    @State private var showRouterIPError = false
    @State private var showRouterMACError = false
    @State private var showPrimaryDNSError = false
    @State private var showSecondaryDNSError = false

    let scene: DNSScene?
    let onCancel: () -> Void
    let onSave: (DNSScene) throws -> Void

    private var isEditing: Bool {
        scene != nil
    }

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
                DNSFormSection(title: "场景名称") {
                    TextField("输入场景名称", text: $sceneName)
                        .kairosTextField()
                }

                // Section 2: 路由器配置
                DNSFormSection(title: "路由器配置") {
                    VStack(alignment: .leading, spacing: 12) {
                        // 路由器 IP
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("路由器 IP", text: $routerIP)
                                .kairosTextField(isInvalid: showRouterIPError)
                                .onChange(of: routerIP) { _, _ in
                                    showRouterIPError = false
                                }

                            if showRouterIPError {
                                Text("IP 地址格式不正确")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        // MAC 地址
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("MAC 地址", text: $routerMAC)
                                .kairosTextField(isInvalid: showRouterMACError)
                                .onChange(of: routerMAC) { _, _ in
                                    showRouterMACError = false
                                }

                            if showRouterMACError {
                                Text("MAC 地址格式不正确")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                // Section 3: DNS 配置
                DNSFormSection(title: "DNS 配置") {
                    VStack(alignment: .leading, spacing: 12) {
                        // 主 DNS
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("主 DNS", text: $primaryDNS)
                                .kairosTextField(isInvalid: showPrimaryDNSError)
                                .onChange(of: primaryDNS) { _, _ in
                                    showPrimaryDNSError = false
                                }

                            if showPrimaryDNSError {
                                Text("DNS 地址格式不正确")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        // 备用 DNS
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("备用 DNS（可选）", text: $secondaryDNS)
                                .kairosTextField(isInvalid: showSecondaryDNSError)
                                .onChange(of: secondaryDNS) { _, _ in
                                    showSecondaryDNSError = false
                                }

                            if showSecondaryDNSError {
                                Text("DNS 地址格式不正确")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
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
                primaryDNS = scene.primaryDNS
                secondaryDNS = scene.secondaryDNS
            }
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        if case .success = SceneValidation.dnsControl(name: sceneName, routerIP: routerIP,
            routerMAC: routerMAC, primaryDNS: primaryDNS, secondaryDNS: secondaryDNS) { return true }
        return false
    }

    // MARK: - Actions

    private func saveScene() {
        // 验证路由器 IP 地址格式
        if !NetworkValidator.isValidIP(routerIP) {
            showRouterIPError = true
            return
        }

        // 验证路由器 MAC 地址格式
        if !NetworkValidator.isValidMAC(routerMAC) {
            showRouterMACError = true
            return
        }

        // 验证主 DNS 地址格式
        if !NetworkValidator.isValidIP(primaryDNS) {
            showPrimaryDNSError = true
            return
        }

        // 验证备用 DNS 地址格式（如果填写了）
        if !secondaryDNS.isEmpty && !NetworkValidator.isValidIP(secondaryDNS) {
            showSecondaryDNSError = true
            return
        }

        // 规范化 MAC 地址（确保存储格式统一）
        guard case .success(let normalizedMAC) = SceneValidation.dnsControl(name: sceneName,
            routerIP: routerIP, routerMAC: routerMAC, primaryDNS: primaryDNS, secondaryDNS: secondaryDNS) else { return }

        let newScene = DNSScene(
            id: scene?.id ?? UUID(),
            name: sceneName,
            routerIP: routerIP,
            routerMAC: normalizedMAC,
            primaryDNS: primaryDNS,
            secondaryDNS: secondaryDNS,
            isEnabled: scene?.isEnabled ?? true
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
private struct DNSFormSection<Content: View>: View {
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
