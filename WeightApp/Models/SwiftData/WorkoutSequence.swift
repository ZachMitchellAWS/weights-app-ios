import Foundation
import SwiftData

@Model
final class WorkoutSequence {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var createdTimezone: String
    var name: String
    var exerciseIds: [UUID]
    var deleted: Bool

    init(name: String, exerciseIds: [UUID] = []) {
        self.id = UUID()
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.name = name
        self.exerciseIds = exerciseIds
        self.deleted = false
    }

    init(id: UUID, name: String, exerciseIds: [UUID], createdAt: Date, createdTimezone: String, deleted: Bool = false) {
        self.id = id
        self.name = name
        self.exerciseIds = exerciseIds
        self.createdAt = createdAt
        self.createdTimezone = createdTimezone
        self.deleted = deleted
    }
}
