  import Foundation
import SwiftData

enum WorkoutSequenceStore {

    private static let sequencesKey = "workoutSequences"
    private static let activeIdKey = "activeSequenceId"
    private static let activeSplitIdKey = "activeSplitId"
    private static let legacyKey = "workoutSequence"
    private static let migrationKey = "workoutSequencesMigratedToSwiftData"
    private static let splitMigrationKey = "workoutSequencesMigratedToSplits"

    // MARK: - Active Sequence (UI preference, stays in UserDefaults)

    static func activeSequenceId() -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: activeIdKey) else { return nil }
        return UUID(uuidString: str)
    }

    static func setActiveSequenceId(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: activeIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeIdKey)
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

    // MARK: - Migration to SwiftData

    static func migrateToSwiftData(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        // First run legacy single-sequence migration into UserDefaults array format
        migrateIfNeeded()

        // Load all sequences from UserDefaults
        let sequences = loadAll()

        // Insert each into SwiftData
        for seq in sequences {
            let model = WorkoutSequence(
                id: seq.id,
                name: seq.name,
                exerciseIds: seq.exerciseIds,
                createdAt: Date(),
                createdTimezone: TimeZone.current.identifier
            )
            context.insert(model)
        }

        try? context.save()

        // Clear UserDefaults sequences data
        defaults.removeObject(forKey: sequencesKey)

        // Set migration flag
        defaults.set(true, forKey: migrationKey)

        if !sequences.isEmpty {
            print("WorkoutSequenceStore: Migrated \(sequences.count) sequence(s) to SwiftData")
        }
    }

    // MARK: - Migrate Sequences to Splits

    static func migrateSequencesToSplits(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: splitMigrationKey) else { return }

        // Check if any splits already exist
        let existingSplits = (try? context.fetch(FetchDescriptor<WorkoutSplit>())) ?? []
        guard existingSplits.isEmpty else {
            defaults.set(true, forKey: splitMigrationKey)
            return
        }

        // Load all exercises to resolve default day assignments by name
        let allExercises = (try? context.fetch(FetchDescriptor<Exercises>(
            predicate: #Predicate { !$0.deleted }
        ))) ?? []
        let exerciseByName = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.name, $0) })

        // Define default days
        let pushNames = ["Bench Press", "Overhead Press", "Dips"]
        let pullNames = ["Deadlift", "Barbell Row", "Pull Ups"]
        let legNames = ["Squat"]

        func resolveIds(_ names: [String]) -> [UUID] {
            names.compactMap { exerciseByName[$0]?.id }
        }

        let pushDay = WorkoutSequence(name: "Push", exerciseIds: resolveIds(pushNames))
        let pullDay = WorkoutSequence(name: "Pull", exerciseIds: resolveIds(pullNames))
        let legDay = WorkoutSequence(name: "Leg", exerciseIds: resolveIds(legNames))

        context.insert(pushDay)
        context.insert(pullDay)
        context.insert(legDay)

        let split = WorkoutSplit(
            name: "PPL",
            dayIds: [pushDay.id, pullDay.id, legDay.id]
        )
        context.insert(split)

        try? context.save()

        // Set active split and first day
        setActiveSplitId(split.id)
        setActiveSequenceId(pushDay.id)

        defaults.set(true, forKey: splitMigrationKey)

        print("WorkoutSequenceStore: Created default Push/Pull/Legs split with \(allExercises.count) exercises available")

        // Sync new objects to backend
        Task {
            await SyncService.shared.syncSequence(pushDay)
            await SyncService.shared.syncSequence(pullDay)
            await SyncService.shared.syncSequence(legDay)
            await SyncService.shared.syncSplit(split)
        }
    }

    // MARK: - Assign default exercises to days

    /// Populates exerciseIds on existing default days (Push/Pull/Leg) using exercise names.
    /// Safe to call multiple times — only fills days that have empty exerciseIds.
    static func assignDefaultExercisesToDays(context: ModelContext) {
        let allSequences = (try? context.fetch(FetchDescriptor<WorkoutSequence>(
            predicate: #Predicate { !$0.deleted }
        ))) ?? []

        let allExercises = (try? context.fetch(FetchDescriptor<Exercises>(
            predicate: #Predicate { !$0.deleted }
        ))) ?? []
        guard !allExercises.isEmpty else { return }

        let exerciseByName = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.name, $0) })
        let dayExerciseMap: [String: [String]] = [
            "Push": ["Bench Press", "Overhead Press", "Dips"],
            "Pull": ["Deadlift", "Barbell Row", "Pull Ups"],
            "Leg": ["Squat"]
        ]

        var didChange = false
        for seq in allSequences {
            if let names = dayExerciseMap[seq.name], seq.exerciseIds.isEmpty {
                seq.exerciseIds = names.compactMap { exerciseByName[$0]?.id }
                didChange = true
            }
        }

        if didChange {
            try? context.save()
        }
    }

    // MARK: - Private (kept for migration path)

    private static func loadAll() -> [LegacyWorkoutSequence] {
        guard let data = UserDefaults.standard.data(forKey: sequencesKey),
              let sequences = try? JSONDecoder().decode([LegacyWorkoutSequence].self, from: data) else {
            return []
        }
        return sequences
    }

    private static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard let oldIds = defaults.stringArray(forKey: legacyKey) else { return }
        let uuids = oldIds.compactMap { UUID(uuidString: $0) }
        guard !uuids.isEmpty else {
            defaults.removeObject(forKey: legacyKey)
            return
        }
        let seq = LegacyWorkoutSequence(id: UUID(), name: "My Workout", exerciseIds: uuids)
        if let data = try? JSONEncoder().encode([seq]) {
            defaults.set(data, forKey: sequencesKey)
        }
        setActiveSequenceId(seq.id)
        defaults.removeObject(forKey: legacyKey)
    }
}

// Codable struct kept only for reading UserDefaults during migration
private struct LegacyWorkoutSequence: Codable, Identifiable {
    var id: UUID
    var name: String
    var exerciseIds: [UUID]
}
