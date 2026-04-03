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

    static let tierExercisesId          = UUID(uuidString: "00000000-0000-0000-0002-000000000001")!
    static let deadliftsPlusId   = UUID(uuidString: "00000000-0000-0000-0002-000000000002")!
    static let squatsPlusId      = UUID(uuidString: "00000000-0000-0000-0002-000000000003")!
    static let benchPressPlusId  = UUID(uuidString: "00000000-0000-0000-0002-000000000004")!
    static let barbellRowPlusId  = UUID(uuidString: "00000000-0000-0000-0002-000000000005")!
    static let ohpPlusId         = UUID(uuidString: "00000000-0000-0000-0002-000000000006")!

    static let builtInIds: Set<UUID> = [
        tierExercisesId,
        deadliftsPlusId, squatsPlusId, benchPressPlusId,
        barbellRowPlusId, ohpPlusId
    ]

    static let accessoryGroupForFundamental: [UUID: UUID] = [
        Exercise.deadliftsId: deadliftsPlusId,
        Exercise.squatsId: squatsPlusId,
        Exercise.benchPressId: benchPressPlusId,
        Exercise.barbellRowId: barbellRowPlusId,
        Exercise.overheadPressId: ohpPlusId,
    ]

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
        ),
        ExerciseGroup(
            groupId: deadliftsPlusId,
            name: "Deadlifts+",
            exerciseIds: [
                Exercise.deadliftsId,
                Exercise.frontSquatsId,
                Exercise.backExtensionsId,
                Exercise.hangingLegRaisesId,
            ],
            sortOrder: 1,
            isCustom: false
        ),
        ExerciseGroup(
            groupId: squatsPlusId,
            name: "Squats+",
            exerciseIds: [
                Exercise.squatsId,
                Exercise.bulgarianSplitSquatsId,
                Exercise.romanianDeadliftsId,
                Exercise.standingCalfRaisesId,
            ],
            sortOrder: 2,
            isCustom: false
        ),
        ExerciseGroup(
            groupId: benchPressPlusId,
            name: "Bench Press+",
            exerciseIds: [
                Exercise.benchPressId,
                Exercise.dipsId,
                Exercise.flyesId,
                Exercise.lateralRaisesId,
            ],
            sortOrder: 3,
            isCustom: false
        ),
        ExerciseGroup(
            groupId: barbellRowPlusId,
            name: "Barbell Rows+",
            exerciseIds: [
                Exercise.barbellRowId,
                Exercise.pullUpsId,
                Exercise.barbellCurlsId,
                Exercise.pulloversId,
            ],
            sortOrder: 4,
            isCustom: false
        ),
        ExerciseGroup(
            groupId: ohpPlusId,
            name: "OHP+",
            exerciseIds: [
                Exercise.overheadPressId,
                Exercise.closeGripBenchPressId,
                Exercise.rearDeltFlysId,
                Exercise.cableYRaisesId,
            ],
            sortOrder: 5,
            isCustom: false
        ),
    ]
}
