import Foundation
import SwiftData

enum WorkoutSplitStore {

    private static let activeDayIdKey = "activeDayId"
    private static let activeSplitIdKey = "activeSplitId"
    // MARK: - Active Day (UI preference, stays in UserDefaults)

    static func activeDayId() -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: activeDayIdKey) else { return nil }
        return UUID(uuidString: str)
    }

    static func setActiveDayId(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: activeDayIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeDayIdKey)
        }
    }

    // MARK: - Active Split (UI preference, stays in UserDefaults)

    static func activeSplitId() -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: activeSplitIdKey) else { return nil }
        return UUID(uuidString: str)
    }

    static func setActiveSplitId(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: activeSplitIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeSplitIdKey)
        }
    }

    // MARK: - Assign default exercises to days

    /// Populates exerciseIds on existing default days using exercise names.
    /// Safe to call multiple times — only fills days that have empty exerciseIds.
    static func assignDefaultExercisesToDays(context: ModelContext) {
        let allSplits = (try? context.fetch(FetchDescriptor<WorkoutSplit>(
            predicate: #Predicate { !$0.deleted }
        ))) ?? []

        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>(
            predicate: #Predicate { !$0.deleted }
        ))) ?? []
        guard !allExercises.isEmpty else { return }

        let exerciseByName = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.name, $0) })
        let dayExerciseMap: [String: [String]] = [
            "Push": ["Bench Press", "Overhead Press", "Dips"],
            "Pull": ["Deadlifts", "Barbell Row", "Pull Ups", "Barbell Curls"],
            "Leg": ["Squats", "Romanian Deadlifts"],
            "Upper": ["Bench Press", "Overhead Press", "Barbell Row", "Pull Ups", "Barbell Curls", "Dips"],
            "Lower": ["Squats", "Deadlifts", "Romanian Deadlifts"],
            "Full Body": ["Squats", "Bench Press", "Deadlifts", "Overhead Press", "Barbell Row", "Pull Ups"]
        ]

        var didChange = false
        for split in allSplits {
            for i in split.days.indices {
                if let names = dayExerciseMap[split.days[i].name], split.days[i].exerciseIds.isEmpty {
                    split.days[i].exerciseIds = names.compactMap { exerciseByName[$0]?.id }
                    didChange = true
                }
            }
        }

        if didChange {
            try? context.save()
        }
    }
}
