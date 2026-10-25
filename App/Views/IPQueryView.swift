//
//  IPQueryView.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

struct IPQueryView: View {
    @State private var viewModel = IPQueryViewModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 查询输入
                GroupBox {
                    VStack(spacing: 12) {
                        HStack(spacing: DesignSystem.Spacing.small) {
                            // 输入框（带清空按钮）
                            HStack(spacing: DesignSystem.Spacing.small) {
                                TextField("输入 IP 地址", text: $viewModel.ipAddress)
                                    .kairosTextField()
                                    .disabled(viewModel.isLoading)

                                // 清空按钮（仅在有内容时显示）
                                if !viewModel.ipAddress.isEmpty {
                                    Button(action: {
                                        viewModel.ipAddress = ""
                                        viewModel.reset()
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                            .imageScale(.medium)
                                            .frame(width: DesignSystem.Input.actionHeight, height: DesignSystem.Input.actionHeight)
                                    }
                                    .buttonStyle(.plain)
                                    .help("清空")
                                }
                            }

                            Button {
                                Task {
                                    await viewModel.queryIP(viewModel.ipAddress)
                                }
                            } label: {
                                if viewModel.isLoading {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("查询中...")
                                    }
                                } else {
                                    Text("查询")
                                }
                            }
                            .buttonStyle(InputActionButtonStyle())
                            .disabled(viewModel.isLoading || viewModel.ipAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding()
                }

                // 查询结果
                if let result = viewModel.result {
                    IPQueryResultView(result: result)
                } else {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(label: "自治系统号", value: "-")
                            InfoRow(label: "IP类型", value: "-")
                            InfoRow(label: "组织", value: "-")
                            InfoRow(label: "时区", value: "-")
                            InfoRow(label: "使用地", value: "-")
                            InfoRow(label: "注册地", value: "-")
                            InfoRow(label: "城市", value: "-")
                            InfoRow(label: "坐标", value: "-")
                        }
                        .padding()
                    } label: {
                        SectionHeader(title: "查询结果", icon: "doc.text", iconColor: .green)
                    }
                }

                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - IP Query Result View

struct IPQueryResultView: View {
    let result: IPQueryResult

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(label: "自治系统号", value: result.asn)
                InfoRow(label: "IP类型", value: result.ipType)
                InfoRow(label: "组织", value: result.organization)
                InfoRow(label: "时区", value: result.timezone)
                InfoRow(label: "使用地", value: result.location.usageLocation)
                InfoRow(label: "注册地", value: result.registrationCountry)
                InfoRow(label: "城市", value: result.location.cityDisplay)
                InfoRow(label: "坐标", value: result.coordinates?.displayString ?? "—")

                if let coordinates = result.coordinates {
                    Divider()
                    MapView(latitude: coordinates.latitude, longitude: coordinates.longitude)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                }
            }
            .padding()
        } label: {
            SectionHeader(title: "查询结果", icon: "doc.text", iconColor: .green)
        }
    }
}
