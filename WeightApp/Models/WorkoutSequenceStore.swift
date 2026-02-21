  import Foundation
import SwiftData

enum WorkoutSequenceStore {

    private static let sequencesKey = "workoutSequences"
    private static let activeIdKey = "activeSequenceId"
    private static let legacyKey = "workoutSequence"
    private static let migrationKey = "workoutSequencesMigratedToSwiftData"

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
