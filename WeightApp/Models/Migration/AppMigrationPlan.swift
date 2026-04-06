//
//  AppMigrationPlan.swift
//  WeightApp
//
//  Manages schema migrations between versioned schemas.
//  Add new schema versions and migration stages here as the schema evolves.
//

import Foundation
import SwiftData

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No migrations yet — V1 is the only version.
        // When adding V2, add a migration stage here:
        //   migrateV1toV2
        []
    }
}
