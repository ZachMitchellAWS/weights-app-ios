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
    var setPlanTemplateId: UUID?

    init(name: String, dayIds: [UUID] = []) {
        self.id = UUID()
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.name = name
        self.dayIds = dayIds
        self.deleted = false
        self.setPlanTemplateId = nil
    }

    init(id: UUID, name: String, dayIds: [UUID], createdAt: Date, createdTimezone: String, deleted: Bool = false, setPlanTemplateId: UUID? = nil) {
        self.id = id
        self.name = name
        self.dayIds = dayIds
        self.createdAt = createdAt
        self.createdTimezone = createdTimezone
        self.deleted = deleted
        self.setPlanTemplateId = setPlanTemplateId
    }
}
