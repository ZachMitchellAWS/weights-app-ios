import Foundation
import SwiftData

enum SeedService {

    // MARK: - Default Exercises (upsert-based seeding)

    /// Upserts all built-in exercises: updates existing ones (preserving notes), inserts missing ones.
    /// Returns the newly inserted exercises (for sync).
    @MainActor
    static func seedExercises(context: ModelContext) -> [Exercise] {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: existing.compactMap { e -> (UUID, Exercise)? in
            (e.id, e)
        })

        var inserted: [Exercise] = []

        for def in Exercise.builtInTemplates {
            if let ex = existingById[def.id] {
                // Update fields but preserve notes
                ex.name = def.name
                ex.loadType = def.loadType.rawValue
                ex.movementType = def.movementType.rawValue
                ex.icon = def.icon
                ex.isCustom = false
            } else {
                let exercise = Exercise(
                    id: def.id,
                    name: def.name,
                    isCustom: false,
                    loadType: def.loadType,
                    movementType: def.movementType,
                    icon: def.icon
                )
                context.insert(exercise)
                inserted.append(exercise)
            }
        }

        try? context.save()

        if !inserted.isEmpty {
            Task {
                for exercise in inserted {
                    await SyncService.shared.syncExercise(exercise)
                }
            }
        }

        return inserted
    }


    // MARK: - Built-in Groups

    @MainActor
    static func seedGroups(context: ModelContext) {
        let existingDescriptor = FetchDescriptor<ExerciseGroup>(
            predicate: #Predicate { $0.isCustom == false }
        )
        let existing = (try? context.fetch(existingDescriptor)) ?? []
        let existingIds = Set(existing.map { $0.groupId })

        for def in ExerciseGroup.builtInTemplates {
            if existingIds.contains(def.groupId) {
                if let group = existing.first(where: { $0.groupId == def.groupId }) {
                    group.name = def.name
                    group.exerciseIds = def.exerciseIds
                    group.sortOrder = def.sortOrder
                }
                continue
            }

            let group = ExerciseGroup(
                groupId: def.groupId,
                name: def.name,
                exerciseIds: def.exerciseIds,
                sortOrder: def.sortOrder,
                isCustom: false
            )
            context.insert(group)
        }

        try? context.save()
    }

    // MARK: - Built-in Set Plans

    @MainActor
    static func seedSetPlans(context: ModelContext) {
        let existingDescriptor = FetchDescriptor<SetPlan>(
            predicate: #Predicate { $0.isCustom == false }
        )
        let existing = (try? context.fetch(existingDescriptor)) ?? []
        let existingIds = Set(existing.map { $0.id })

        for def in SetPlan.builtInPlans {
            if existingIds.contains(def.id) {
                if let plan = existing.first(where: { $0.id == def.id }) {
                    plan.name = def.name
                    plan.effortSequence = def.sequence
                    plan.planDescription = def.description
                }
                continue
            }

            let plan = SetPlan(
                id: def.id,
                name: def.name,
                effortSequence: def.sequence,
                isCustom: false,
                planDescription: def.description
            )
            context.insert(plan)
        }

        if let userProps = try? context.fetch(FetchDescriptor<UserProperties>()).first,
           userProps.activeSetPlanId == nil {
            userProps.activeSetPlanId = SetPlan.standardId
            try? context.save()
            Task { await SyncService.shared.updateActiveSetPlan(SetPlan.standardId) }
        } else {
            try? context.save()
        }
    }
}
