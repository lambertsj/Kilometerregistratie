import SwiftUI

extension TripCategory {
    /// Vaste categoriekleur, overal in de app hetzelfde (lijst, badges, diagram).
    var color: Color {
        switch self {
        case .business: .blue
        case .commute: .teal
        case .personal: .purple
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
        Label(category.displayName, systemImage: category.iconName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(category.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(category.color.opacity(0.15), in: Capsule())
    }
}
