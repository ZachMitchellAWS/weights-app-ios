//
//  SchemaV1.swift
//  WeightApp
//
//  Frozen snapshot of the V1 schema for migration support.
//  Do NOT modify this file — it represents the schema at initial production release.
//

import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            LiftSet.self,
            Estimated1RM.self,
            UserProperties.self,
            SetPlan.self,
            ExerciseGroup.self,
            AccessoryGoalCheckin.self,
            EntitlementGrant.self
        ]
    }

    // MARK: - Exercise

    @Model
    final class Exercise {
        #Index<Exercise>([\.deleted])

        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var createdTimezone: String
        var name: String
        var isCustom: Bool
        var loadType: String
        var notes: String?
        var deleted: Bool
        var icon: String
        var movementType: String?
        var weightIncrement: Double?
        var barbellWeight: Double?

        init(id: UUID = UUID(), createdAt: Date = Date(), createdTimezone: String = "", name: String = "", isCustom: Bool = false, loadType: String = "", notes: String? = nil, deleted: Bool = false, icon: String = "", movementType: String? = nil, weightIncrement: Double? = nil, barbellWeight: Double? = nil) {
            self.id = id; self.createdAt = createdAt; self.createdTimezone = createdTimezone; self.name = name; self.isCustom = isCustom; self.loadType = loadType; self.notes = notes; self.deleted = deleted; self.icon = icon; self.movementType = movementType; self.weightIncrement = weightIncrement; self.barbellWeight = barbellWeight
        }
    }

    // MARK: - LiftSet

    @Model
    final class LiftSet {
        #Index<LiftSet>([\.createdAt], [\.deleted])

        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var createdTimezone: String
        var reps: Int
        var weight: Double
        var deleted: Bool
        var isBaselineSet: Bool = false

        @Relationship var exercise: Exercise?

        init(id: UUID = UUID(), createdAt: Date = Date(), createdTimezone: String = "", reps: Int = 0, weight: Double = 0, deleted: Bool = false, isBaselineSet: Bool = false, exercise: Exercise? = nil) {
            self.id = id; self.createdAt = createdAt; self.createdTimezone = createdTimezone; self.reps = reps; self.weight = weight; self.deleted = deleted; self.isBaselineSet = isBaselineSet; self.exercise = exercise
        }
    }

    // MARK: - Estimated1RM

    @Model
    final class Estimated1RM {
        #Index<Estimated1RM>([\.createdAt], [\.deleted])

        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var createdTimezone: String
        @Relationship var exercise: Exercise?
        var value: Double
        var setId: UUID
        var deleted: Bool

        init(id: UUID = UUID(), createdAt: Date = Date(), createdTimezone: String = "", exercise: Exercise? = nil, value: Double = 0, setId: UUID = UUID(), deleted: Bool = false) {
            self.id = id; self.createdAt = createdAt; self.createdTimezone = createdTimezone; self.exercise = exercise; self.value = value; self.setId = setId; self.deleted = deleted
        }
    }

    // MARK: - UserProperties

    @Model
    final class UserProperties {
        @Attribute(.unique) var id: UUID
        var bodyweight: Double?
        var availableChangePlates: [Double] = []
        var progressMinReps: Int = 4
        var progressMaxReps: Int = 8
        var activeSetPlanId: UUID?
        var stepsGoal: Int?
        var proteinGoal: Int?
        var bodyweightTarget: Double?
        var timezoneIdentifier: String?
        var biologicalSex: String?
        var weightUnit: String = "lbs"

        init(id: UUID = UUID(), bodyweight: Double? = nil, availableChangePlates: [Double] = [], progressMinReps: Int = 4, progressMaxReps: Int = 8, activeSetPlanId: UUID? = nil, stepsGoal: Int? = nil, proteinGoal: Int? = nil, bodyweightTarget: Double? = nil, timezoneIdentifier: String? = nil, biologicalSex: String? = nil, weightUnit: String = "lbs") {
            self.id = id; self.bodyweight = bodyweight; self.availableChangePlates = availableChangePlates; self.progressMinReps = progressMinReps; self.progressMaxReps = progressMaxReps; self.activeSetPlanId = activeSetPlanId; self.stepsGoal = stepsGoal; self.proteinGoal = proteinGoal; self.bodyweightTarget = bodyweightTarget; self.timezoneIdentifier = timezoneIdentifier; self.biologicalSex = biologicalSex; self.weightUnit = weightUnit
        }
    }

    // MARK: - SetPlan

    @Model
    final class SetPlan {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var createdTimezone: String
        var name: String
        var templateDescription: String?
        var effortSequence: [String]
        var isCustom: Bool
        var deleted: Bool

        init(id: UUID = UUID(), createdAt: Date = Date(), createdTimezone: String = "", name: String = "", templateDescription: String? = nil, effortSequence: [String] = [], isCustom: Bool = false, deleted: Bool = false) {
            self.id = id; self.createdAt = createdAt; self.createdTimezone = createdTimezone; self.name = name; self.templateDescription = templateDescription; self.effortSequence = effortSequence; self.isCustom = isCustom; self.deleted = deleted
        }
    }

    // MARK: - ExerciseGroup

    @Model
    final class ExerciseGroup {
        @Attribute(.unique) var groupId: UUID
        var name: String
        var exerciseIds: [UUID]
        var sortOrder: Int
        var isCustom: Bool
        var createdAt: Date
        var createdTimezone: String
        var lastModifiedDatetime: Date
        var deleted: Bool
        var pendingSync: Bool

        init(groupId: UUID = UUID(), name: String = "", exerciseIds: [UUID] = [], sortOrder: Int = 0, isCustom: Bool = false, createdAt: Date = Date(), createdTimezone: String = "", lastModifiedDatetime: Date = Date(), deleted: Bool = false, pendingSync: Bool = false) {
            self.groupId = groupId; self.name = name; self.exerciseIds = exerciseIds; self.sortOrder = sortOrder; self.isCustom = isCustom; self.createdAt = createdAt; self.createdTimezone = createdTimezone; self.lastModifiedDatetime = lastModifiedDatetime; self.deleted = deleted; self.pendingSync = pendingSync
        }
    }

    // MARK: - AccessoryGoalCheckin

    @Model
    final class AccessoryGoalCheckin {
        #Index<AccessoryGoalCheckin>([\.createdAt], [\.deleted])

        @Attribute(.unique) var id: UUID
        var metricType: String
        var value: Double
        var createdAt: Date
        var createdTimezone: String
        var deleted: Bool

        init(id: UUID = UUID(), metricType: String = "", value: Double = 0, createdAt: Date = Date(), createdTimezone: String = "", deleted: Bool = false) {
            self.id = id; self.metricType = metricType; self.value = value; self.createdAt = createdAt; self.createdTimezone = createdTimezone; self.deleted = deleted
        }
    }

    // MARK: - EntitlementGrant

    @Model
    final class EntitlementGrant {
        var entitlementName: String
        var startUtc: Date
        var endUtc: Date

        init(entitlementName: String = "", startUtc: Date = Date(), endUtc: Date = Date()) {
            self.entitlementName = entitlementName; self.startUtc = startUtc; self.endUtc = endUtc
        }
    }
}
