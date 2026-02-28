import Foundation
import SwiftData

@Model
final class WorkoutSplit {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var createdTimezone: String
    var name: String
    var dayIds: [UUID]
    var deleted: Bool

    init(name: String, dayIds: [UUID] = []) {
        self.id = UUID()
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.name = name
        self.dayIds = dayIds
        self.deleted = false
    }

    init(id: UUID, name: String, dayIds: [UUID], createdAt: Date, createdTimezone: String, deleted: Bool = false) {
        self.id = id
        self.name = name
        self.dayIds = dayIds
        self.createdAt = createdAt
        self.createdTimezone = createdTimezone
        self.deleted = deleted
    }
}
