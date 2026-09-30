import Foundation
import SwiftData

/// Opslag en opvraag van geleerde adrescombinatie→categorie-regels.
struct ClassificationRuleRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// De eerder geleerde categorie voor deze adrescombinatie, indien bekend.
    func learnedCategory(forRouteKey key: String) -> TripCategory? {
        var descriptor = FetchDescriptor<ClassificationRule>(
            predicate: #Predicate { $0.routeKey == key }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first?.category
    }

    /// Leert (of actualiseert) de gekozen categorie voor een adrescombinatie.
    func learn(routeKey key: String, category: TripCategory) throws {
        var descriptor = FetchDescriptor<ClassificationRule>(
            predicate: #Predicate { $0.routeKey == key }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.category = category
            existing.timesUsed += 1
            existing.updatedAt = .now
        } else {
            context.insert(ClassificationRule(routeKey: key, category: category))
        }
        try context.save()
    }
}
