import SwiftUI

extension TripCategory {
    /// Vaste categoriekleur, overal in de app hetzelfde (lijst, badges, diagram).
    var color: Color {
        switch self {
        case .business: Theme.business
        case .commute: Theme.commute
        case .personal: Theme.personal
        }
    }

    var iconName: String {
        switch self {
        case .business: "briefcase.fill"
        case .commute: "building.2.fill"
        case .personal: "house.fill"
        }
    }
}

/// Klein gekleurd categorielabel voor in lijsten en detailschermen.
struct CategoryBadge: View {
    let category: TripCategory

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.iconName)
                .accessibilityHidden(true)
            Text(category.displayName)
        }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(category.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(category.color.opacity(0.14), in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}
