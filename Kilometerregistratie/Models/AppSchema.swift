import Foundation
import SwiftData

/// Eén centrale lijst van alle SwiftData-modellen zodat app, previews en
/// tests altijd hetzelfde schema gebruiken. De actuele versie staat in
/// `AppSchemaV2`; het migratiepad in `AppMigrationPlan`.
enum AppSchema {
    static let models: [any PersistentModel.Type] = AppSchemaV2.models

    static var schema: Schema { Schema(versionedSchema: AppSchemaV2.self) }

    static var migrationPlan: any SchemaMigrationPlan.Type { AppMigrationPlan.self }
}
