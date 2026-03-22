import Foundation
import SwiftData

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

    init(groupId: UUID = UUID(), name: String, exerciseIds: [UUID], sortOrder: Int, isCustom: Bool = true) {
        self.groupId = groupId
        self.name = name
        self.exerciseIds = exerciseIds
        self.sortOrder = sortOrder
        self.isCustom = isCustom
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.lastModifiedDatetime = Date()
        self.deleted = false
        self.pendingSync = false
    }

    init(groupId: UUID, name: String, exerciseIds: [UUID], sortOrder: Int, isCustom: Bool,
         createdAt: Date, createdTimezone: String, lastModifiedDatetime: Date,
         deleted: Bool = false, pendingSync: Bool = false) {
        self.groupId = groupId
        self.name = name
        self.exerciseIds = exerciseIds
        self.sortOrder = sortOrder
        self.isCustom = isCustom
        self.createdAt = createdAt
        self.createdTimezone = createdTimezone
        self.lastModifiedDatetime = lastModifiedDatetime
        self.deleted = deleted
        self.pendingSync = pendingSync
    }

    // MARK: - Built-in Group IDs (deterministic, segment 0002)

    static let tierExercisesId = UUID(uuidString: "00000000-0000-0000-0002-000000000001")!

    static let builtInIds: Set<UUID> = [tierExercisesId]

    var isBuiltIn: Bool {
        ExerciseGroup.builtInIds.contains(groupId)
    }

    // MARK: - Built-in Definitions

    static let builtInTemplates: [ExerciseGroup] = [
        ExerciseGroup(
            groupId: tierExercisesId,
            name: "Strength Tier",
            exerciseIds: [
                Exercise.deadliftsId,
                Exercise.squatsId,
                Exercise.benchPressId,
                Exercise.barbellRowId,
                Exercise.overheadPressId,
            ],
            sortOrder: 0,
            isCustom: false
        )
    ]
}
