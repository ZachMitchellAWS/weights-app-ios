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

    // MARK: - Default Splits (upsert-based seeding)

    @MainActor
    static func seedSplits(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<WorkoutSplit>())) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        var inserted: [WorkoutSplit] = []
        let baseDate = Date()

        for (index, def) in WorkoutSplit.builtInTemplates.enumerated() {
            if let split = existingById[def.id] {
                split.name = def.name
                split.days = def.days
            } else {
                let split = WorkoutSplit(
                    id: def.id,
                    name: def.name,
                    days: def.days,
                    createdAt: baseDate.addingTimeInterval(Double(index)),
                    createdTimezone: TimeZone.current.identifier
                )
                context.insert(split)
                inserted.append(split)
            }
        }

        try? context.save()

        // Set default active split if none is set
        if WorkoutSplitStore.activeSplitId() == nil {
            WorkoutSplitStore.setActiveSplitId(WorkoutSplit.pplId)
            WorkoutSplitStore.setActiveDayId(WorkoutSplit.pushDayId)
            Task { await SyncService.shared.updateActiveSplit(WorkoutSplit.pplId) }
        }

        if !inserted.isEmpty {
            Task {
                for split in inserted {
                    await SyncService.shared.syncSplit(split)
                }
            }
        }
    }

    // MARK: - Built-in Set Plans

    @MainActor
    static func seedSetPlans(context: ModelContext) {
        let existingDescriptor = FetchDescriptor<SetPlan>(
            predicate: #Predicate { $0.isCustom == false }
        )
        let existing = (try? context.fetch(existingDescriptor)) ?? []
        let existingIds = Set(existing.map { $0.id })

        for def in SetPlan.builtInTemplates {
            if existingIds.contains(def.id) {
                if let template = existing.first(where: { $0.id == def.id }) {
                    template.name = def.name
                    template.effortSequence = def.sequence
                    template.templateDescription = def.description
                }
                continue
            }

            let template = SetPlan(
                id: def.id,
                name: def.name,
                effortSequence: def.sequence,
                isCustom: false,
                templateDescription: def.description
            )
            context.insert(template)
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
