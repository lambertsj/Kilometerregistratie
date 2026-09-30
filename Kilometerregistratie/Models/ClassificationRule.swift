import Foundation
import SwiftData

/// Zelflerende classificatie: onthoudt per adrescombinatie welke categorie
/// de gebruiker eerder koos, zodat die de volgende keer voorgesteld wordt.
@Model
final class ClassificationRule {
    /// Genormaliseerde sleutel uit `TripClassifier.routeKey`.
    var routeKey: String
    var categoryRawValue: String
    var timesUsed: Int
    var updatedAt: Date

    var category: TripCategory {
        get { TripCategory(rawValue: categoryRawValue) ?? .business }
        set { categoryRawValue = newValue.rawValue }
    }

    init(routeKey: String, category: TripCategory, timesUsed: Int = 1, updatedAt: Date = .now) {
        self.routeKey = routeKey
        self.categoryRawValue = category.rawValue
        self.timesUsed = timesUsed
        self.updatedAt = updatedAt
    }
}
