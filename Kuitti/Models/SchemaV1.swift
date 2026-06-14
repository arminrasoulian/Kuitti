import Foundation
import SwiftData

/// Versioned from the first commit: retrofitting versioning onto an unversioned store
/// is the painful path. Migration rules: additive defaulted/optional changes only,
/// renames via @Attribute(originalName:), never retype in place.
nonisolated enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Account.self,
            Category.self,
            Transaction.self,
            LineItem.self,
            Product.self,
            ProductAlias.self,
            Store.self,
            ReceiptImage.self,
            RecurringTemplate.self,
            DismissedDuplicatePair.self,
        ]
    }
}

nonisolated enum KuittiMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
