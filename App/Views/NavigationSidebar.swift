//
//  NavigationSidebar.swift
//  Kairos
//

import SwiftUI

struct NavigationSidebar: View {
    @Binding var selectedTab: Int

    private let primaryDestinations = [
        Destination(id: 0, title: "网络控制", systemImage: "globe", selectedSystemImage: "globe.americas.fill"),
        Destination(id: 1, title: "网络工具", systemImage: "wrench.and.screwdriver", selectedSystemImage: "wrench.and.screwdriver.fill"),
        Destination(id: 2, title: "Mihomo", systemImage: "shippingbox", selectedSystemImage: "shippingbox.fill")
    ]

    private let utilityDestinations = [
        Destination(id: 4, title: "设置", systemImage: "gearshape", selectedSystemImage: "gearshape.fill"),
        Destination(id: 3, title: "日志", systemImage: "doc.text", selectedSystemImage: "doc.text.fill"),
        Destination(id: 5, title: "关于", systemImage: "info.circle", selectedSystemImage: "info.circle.fill")
    ]

    var body: some View {
        VStack(spacing: 0) {
            destinationGroup(primaryDestinations)

            Spacer(minLength: DesignSystem.Spacing.standard)

            destinationGroup(utilityDestinations)
        }
        .padding(.horizontal, DesignSystem.Spacing.small)
        .padding(.vertical, DesignSystem.Spacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Kairos")
    }

    private func destinationGroup(_ destinations: [Destination]) -> some View {
        VStack(spacing: DesignSystem.Spacing.extraSmall) {
            ForEach(destinations) { destination in
                Button {
                    selectedTab = destination.id
                } label: {
                    Label(
                        L10n.string(destination.title),
                        systemImage: selectedTab == destination.id
                            ? destination.selectedSystemImage
                            : destination.systemImage
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DesignSystem.Spacing.medium)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                        .foregroundStyle(selectedTab == destination.id ? Color.accentColor : Color.primary)
                        .background {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .fill(
                                    selectedTab == destination.id
                                        ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                                        : Color.clear
                                )
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension NavigationSidebar {
    struct Destination: Identifiable {
        let id: Int
        let title: String
        let systemImage: String
        let selectedSystemImage: String
    }
}

#Preview {
    NavigationSidebar(selectedTab: .constant(0))
        .frame(width: 210, height: 696)
}
