//
//  SectionHeader.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

struct SectionHeader: View {
    let title: String
    let icon: String
    let iconColor: Color
    var description: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.extraSmall) {
                Text(L10n.string(title))
                    .font(.system(size: 15, weight: .semibold))

                if let description {
                    Text(L10n.string(description))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.bottom, 8)
    }
}
