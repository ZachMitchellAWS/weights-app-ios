import Foundation
import SwiftData

enum SeedService {

    // MARK: - Default Exercises

    static let defaultExercises: [(name: String, loadType: ExerciseLoadType, movementType: ExerciseMovementType)] = [
        ("Deadlifts", .barbell, .hinge),
        ("Squats", .barbell, .squat),
        ("Bench Press", .barbell, .push),
        ("Overhead Press", .barbell, .push),
        ("Barbell Row", .barbell, .pull),
        ("Pull Ups", .singleLoad, .pull),
        ("Dips", .singleLoad, .push),
        ("Barbell Curls", .barbell, .pull),
        ("Romanian Deadlifts", .barbell, .hinge)
    ]

    @MainActor
    static func seedExercises(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        guard existing.isEmpty else { return }

        for (name, loadType, movementType) in defaultExercises {
            let icon = IconCarouselPicker.suggestedIcon(for: name)
            let exercise = Exercise(name: name, isCustom: false, loadType: loadType, movementType: movementType, icon: icon)
            context.insert(exercise)
        }

        try? context.save()
    }

    // MARK: - Default Splits

    private static let splitSeedKey = "workoutSplitsSeeded"

    @MainActor
    static func seedSplits(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: splitSeedKey) else { return }

        let existingSplits = (try? context.fetch(FetchDescriptor<WorkoutSplit>())) ?? []
        guard existingSplits.isEmpty else {
            defaults.set(true, forKey: splitSeedKey)
            return
        }

        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>(
            predicate: #Predicate { !$0.deleted }
        ))) ?? []
        let exerciseByName = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.name, $0) })

        func resolveIds(_ names: [String]) -> [UUID] {
            names.compactMap { exerciseByName[$0]?.id }
        }

        let pplSplit = WorkoutSplit(
            name: "Push / Pull / Legs",
            days: [
                WorkoutDay(name: "Push", exerciseIds: resolveIds(["Bench Press", "Overhead Press", "Dips"])),
                WorkoutDay(name: "Pull", exerciseIds: resolveIds(["Deadlifts", "Barbell Row", "Pull Ups", "Barbell Curls"])),
                WorkoutDay(name: "Leg", exerciseIds: resolveIds(["Squats", "Romanian Deadlifts"]))
            ]
        )
        context.insert(pplSplit)

        let ulSplit = WorkoutSplit(
            name: "Upper / Lower",
            days: [
                WorkoutDay(name: "Upper", exerciseIds: resolveIds(["Bench Press", "Overhead Press", "Barbell Row", "Pull Ups", "Barbell Curls", "Dips"])),
                WorkoutDay(name: "Lower", exerciseIds: resolveIds(["Squats", "Deadlifts", "Romanian Deadlifts"]))
            ]
        )
        context.insert(ulSplit)

        let fbSplit = WorkoutSplit(
            name: "Full Body",
            days: [
                WorkoutDay(name: "Full Body", exerciseIds: resolveIds(["Squats", "Bench Press", "Deadlifts", "Overhead Press", "Barbell Row", "Pull Ups"]))
            ]
        )
        context.insert(fbSplit)

        try? context.save()

        WorkoutSplitStore.setActiveSplitId(pplSplit.id)
        WorkoutSplitStore.setActiveDayId(pplSplit.days.first?.id)

        defaults.set(true, forKey: splitSeedKey)

        Task {
            await SyncService.shared.syncSplit(pplSplit)
            await SyncService.shared.syncSplit(ulSplit)
            await SyncService.shared.syncSplit(fbSplit)
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
