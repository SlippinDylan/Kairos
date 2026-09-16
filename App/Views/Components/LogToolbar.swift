//
//  LogToolbar.swift
//  Enodia
//
//  Created by SlippinDylan on 2025/12/31.
//

import SwiftUI

/// 日志工具栏
///
/// 提供以下功能：
/// - 按级别过滤（纯文字）
/// - 内容搜索
/// - 时间范围筛选（预设 + 自定义）
/// - 清空/导出操作
struct LogToolbar: View {
    // MARK: - Bindings

    @Binding var searchText: String
    @Binding var selectedLevel: LogLevel?

    // MARK: - Callbacks

    let onClear: () -> Void
    let onExport: () -> Void

    private let filterOptions: [LogLevel?] = [nil] + LogLevel.allCases.map(Optional.some)

    var body: some View {
        HStack(spacing: 12) {
            filterControl
                .fixedSize()

            searchControl
                .layoutPriority(1)

            actionControls
                .fixedSize()
        }
    }

    private var filterControl: some View {
        HStack(spacing: 0) {
            ForEach(filterOptions, id: \.self) { level in
                let isSelected = selectedLevel == level

                Button {
                    selectedLevel = level
                } label: {
                    Text(filterTitle(for: level))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(minWidth: 52)
                        .frame(height: 28)
                        .background(isSelected ? Color.accentColor : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .logToolbarGlass()
        .help("按日志级别过滤")
    }

    private var searchControl: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(DesignSystem.IconScale.small)

            TextField("搜索内容...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(DesignSystem.IconScale.small)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 160, idealWidth: 240, maxWidth: .infinity)
        .frame(height: 32)
        .logToolbarGlass()
    }

    private var actionControls: some View {
        HStack(spacing: 8) {
            Button {
                onClear()
            } label: {
                Text("清空")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .logToolbarGlass(tint: .red)
            }
            .buttonStyle(.plain)
            .help("清空所有日志")

            Button {
                onExport()
            } label: {
                Text("导出")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .logToolbarGlass(tint: .accentColor)
            }
            .buttonStyle(.plain)
            .help("导出日志到文件")
        }
    }

    private func filterTitle(for level: LogLevel?) -> String {
        level?.displayName.trimmingCharacters(in: .whitespaces) ?? "全部"
    }
}

private extension View {
    @ViewBuilder
    func logToolbarGlass(tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint).interactive(), in: Capsule())
        } else if let tint {
            background(tint, in: Capsule())
        } else {
            background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                }
        }
    }
}
