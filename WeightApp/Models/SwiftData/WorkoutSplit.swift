import Foundation
import SwiftData

struct WorkoutDay: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var exerciseIds: [UUID]

    init(id: UUID = UUID(), name: String, exerciseIds: [UUID] = []) {
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
    var days: [WorkoutDay]
    var deleted: Bool

    init(name: String, days: [WorkoutDay] = []) {
        self.id = UUID()
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.name = name
        self.days = days
        self.deleted = false
    }

    init(id: UUID, name: String, days: [WorkoutDay], createdAt: Date, createdTimezone: String, deleted: Bool = false) {
        self.id = id
        self.name = name
        self.days = days
        self.createdAt = createdAt
        self.createdTimezone = createdTimezone
        self.deleted = deleted
    }
}
