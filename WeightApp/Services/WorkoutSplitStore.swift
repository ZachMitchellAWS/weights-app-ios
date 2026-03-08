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

    // MARK: - Smart Day/Exercise Selection

    static var smartExerciseSelectionEnabled = true

    /// Determines which workout day to auto-select based on today's activity or rotation.
    /// Returns the day ID to select, or nil if no split/days available.
    static func autoSelectDay(days: [WorkoutDay], context: ModelContext) -> UUID? {
        guard !days.isEmpty else { return nil }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        // Fetch today's non-deleted sets
        let todayDescriptor = FetchDescriptor<LiftSet>(
            predicate: #Predicate<LiftSet> { !$0.deleted && $0.createdAt >= todayStart && $0.createdAt < tomorrowStart },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let todaySets = (try? context.fetch(todayDescriptor)) ?? []

        // Step 1: Check if any day has activity today → mid-workout
        var dayActivity: [(day: WorkoutDay, mostRecent: Date)] = []
        for day in days {
            let dayExerciseSet = Set(day.exerciseIds)
            if let mostRecent = todaySets.first(where: { set in
                guard let exId = set.exercise?.id else { return false }
                return dayExerciseSet.contains(exId)
            }) {
                dayActivity.append((day, mostRecent.createdAt))
            }
        }
        if !dayActivity.isEmpty {
            // Pick the day with the most recent set today
            return dayActivity.max(by: { $0.mostRecent < $1.mostRecent })?.day.id
        }

        // Step 2: No activity today → find the most recent set in the last 7 days
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: todayStart)!
        var recentDescriptor = FetchDescriptor<LiftSet>(
            predicate: #Predicate<LiftSet> { !$0.deleted && $0.createdAt >= sevenDaysAgo && $0.createdAt < todayStart },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        recentDescriptor.fetchLimit = 1
        if let mostRecentSet = (try? context.fetch(recentDescriptor))?.first,
           let exerciseId = mostRecentSet.exercise?.id,
           let (dayIndex, _) = days.enumerated().first(where: { $0.element.exerciseIds.contains(exerciseId) }) {
            let nextIndex = (dayIndex + 1) % days.count
            return days[nextIndex].id
        }

        // Step 3: No history in the last 7 days (or no match) → first day
        return days.first?.id
    }

}
