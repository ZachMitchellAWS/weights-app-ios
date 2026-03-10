import Foundation
import SwiftData

struct WorkoutDay: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var exerciseIds: [UUID]

    nonisolated init(id: UUID = UUID(), name: String, exerciseIds: [UUID] = []) {
        self.id = id
        self.name = name
        self.exerciseIds = exerciseIds
    }
}

@Model
final class WorkoutSplit {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var createdTimezone: String
    var name: String
    var daysData: Data = Data()
    var deleted: Bool

    var days: [WorkoutDay] {
        get { (try? JSONDecoder().decode([WorkoutDay].self, from: daysData)) ?? [] }
        set { daysData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(name: String, days: [WorkoutDay] = []) {
        self.id = UUID()
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.name = name
        self.daysData = (try? JSONEncoder().encode(days)) ?? Data()
        self.deleted = false
    }

    init(id: UUID, name: String, days: [WorkoutDay], createdAt: Date, createdTimezone: String, deleted: Bool = false) {
        self.id = id
        self.name = name
        self.daysData = (try? JSONEncoder().encode(days)) ?? Data()
        self.createdAt = createdAt
        self.createdTimezone = createdTimezone
        self.deleted = deleted
    }

    var isBuiltIn: Bool { WorkoutSplit.builtInIds.contains(id) }

    // MARK: - Built-in Split IDs (deterministic)

    static let pplId            = UUID(uuidString: "00000000-0000-0000-0002-000000000001")!
    static let upperLowerId     = UUID(uuidString: "00000000-0000-0000-0002-000000000002")!
    static let fullBodyId       = UUID(uuidString: "00000000-0000-0000-0002-000000000003")!
    static let pplCompleteId    = UUID(uuidString: "00000000-0000-0000-0002-000000000004")!

    // Day IDs
    static let pushDayId             = UUID(uuidString: "00000000-0000-0000-0002-000000000011")!
    static let pullDayId             = UUID(uuidString: "00000000-0000-0000-0002-000000000012")!
    static let legDayId              = UUID(uuidString: "00000000-0000-0000-0002-000000000013")!
    static let upperDayId            = UUID(uuidString: "00000000-0000-0000-0002-000000000021")!
    static let lowerDayId            = UUID(uuidString: "00000000-0000-0000-0002-000000000022")!
    static let fullBodyDayId         = UUID(uuidString: "00000000-0000-0000-0002-000000000031")!
    static let pplCompletePushDayId  = UUID(uuidString: "00000000-0000-0000-0002-000000000041")!
    static let pplCompletePullDayId  = UUID(uuidString: "00000000-0000-0000-0002-000000000042")!
    static let pplCompleteLegDayId   = UUID(uuidString: "00000000-0000-0000-0002-000000000043")!

    static let builtInIds: Set<UUID> = [pplId, upperLowerId, fullBodyId, pplCompleteId]

    static let builtInTemplates: [(id: UUID, name: String, days: [WorkoutDay])] = [
        (
            id: pplId,
            name: "Push / Pull / Legs Basic",
            days: [
                WorkoutDay(id: pushDayId, name: "Push", exerciseIds: [Exercise.benchPressId, Exercise.overheadPressId, Exercise.dipsId]),
                WorkoutDay(id: pullDayId, name: "Pull", exerciseIds: [Exercise.deadliftsId, Exercise.barbellRowId, Exercise.pullUpsId, Exercise.barbellCurlsId]),
                WorkoutDay(id: legDayId, name: "Leg", exerciseIds: [Exercise.squatsId, Exercise.romanianDeadliftsId])
            ]
        ),
        (
            id: pplCompleteId,
            name: "Push / Pull / Legs Complete",
            days: [
                WorkoutDay(id: pplCompletePushDayId, name: "Push", exerciseIds: [Exercise.benchPressId, Exercise.overheadPressId, Exercise.dipsId, Exercise.lateralRaisesId, Exercise.tricepPushdownsId, Exercise.flyesId, Exercise.sideRaisesId]),
                WorkoutDay(id: pplCompletePullDayId, name: "Pull", exerciseIds: [Exercise.deadliftsId, Exercise.barbellRowId, Exercise.pullUpsId, Exercise.barbellCurlsId]),
                WorkoutDay(id: pplCompleteLegDayId, name: "Leg", exerciseIds: [Exercise.squatsId, Exercise.romanianDeadliftsId])
            ]
        ),
        (
            id: upperLowerId,
            name: "Upper / Lower",
            days: [
                WorkoutDay(id: upperDayId, name: "Upper", exerciseIds: [Exercise.benchPressId, Exercise.overheadPressId, Exercise.barbellRowId, Exercise.pullUpsId, Exercise.barbellCurlsId, Exercise.dipsId]),
                WorkoutDay(id: lowerDayId, name: "Lower", exerciseIds: [Exercise.squatsId, Exercise.deadliftsId, Exercise.romanianDeadliftsId])
            ]
        ),
        (
            id: fullBodyId,
            name: "Full Body",
            days: [
                WorkoutDay(id: fullBodyDayId, name: "Full Body", exerciseIds: [Exercise.squatsId, Exercise.benchPressId, Exercise.deadliftsId, Exercise.overheadPressId, Exercise.barbellRowId, Exercise.pullUpsId])
            ]
        )
    ]
}
