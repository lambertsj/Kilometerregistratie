import Foundation
import SwiftData

/// Schema versie 2: de Duitse Fahrtenbuch-velden op `Trip`, de tombstone
/// (`deletedAt`) en de append-only `TripRevision`.
///
/// Anders dan `AppSchemaV1` verwijst deze versie wél naar de huidige klassen:
/// dit is de versie die de app nu draait.
enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Trip.self, Vehicle.self, AppSettings.self, CachedAddress.self, ClassificationRule.self, TripRevision.self]
    }
}

/// Migratiepad van het schema.
///
/// V1 → V2 voegt alleen velden met een standaardwaarde toe en één nieuwe
/// entiteit. Dat is een lichte migratie: SwiftData behoudt alle bestaande
/// rijen en vult de nieuwe kolommen met hun default. Er wordt niets herschreven
/// en niets verwijderd.
///
/// `MigrationTests` in de harness toont dit aan door een database in de
/// V1-vorm te vullen, te migreren en elke waarde terug te vergelijken.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self, AppSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// Expliciet benoemd in plaats van impliciet: zo staat er zwart-op-wit dat
    /// deze stap additief is en geen data aanraakt.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: AppSchemaV1.self,
        toVersion: AppSchemaV2.self
    )
}
