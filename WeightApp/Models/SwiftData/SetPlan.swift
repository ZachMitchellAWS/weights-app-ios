import Foundation
import SwiftData

@Model
final class SetPlan {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var createdTimezone: String
    var name: String
    var templateDescription: String?
    var effortSequence: [String]
    var isCustom: Bool
    var deleted: Bool

    init(id: UUID = UUID(), name: String, effortSequence: [String], isCustom: Bool = true, templateDescription: String? = nil) {
        self.id = id
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.name = name
        self.templateDescription = templateDescription
        self.effortSequence = effortSequence
        self.isCustom = isCustom
        self.deleted = false
    }

    init(id: UUID, name: String, effortSequence: [String], isCustom: Bool, templateDescription: String?,
         createdAt: Date, createdTimezone: String, deleted: Bool = false) {
        self.id = id
        self.name = name
        self.effortSequence = effortSequence
        self.isCustom = isCustom
        self.templateDescription = templateDescription
        self.createdAt = createdAt
        self.createdTimezone = createdTimezone
        self.deleted = deleted
    }

    // MARK: - Built-in Template IDs (deterministic)

    static let standardId      = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let greaseId        = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    static let maintenanceId   = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    static let deloadId        = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
    static let pyramidId       = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
    static let topSetBackoffId = UUID(uuidString: "00000000-0000-0000-0000-000000000106")!

    static let builtInIds: Set<UUID> = [standardId, greaseId, maintenanceId, deloadId, pyramidId, topSetBackoffId]

    // MARK: - Built-in Definitions

    static let builtInTemplates: [(id: UUID, name: String, sequence: [String], description: String)] = [
        (standardId,      "Standard",            ["easy", "easy", "moderate", "moderate", "hard", "pr"],                           "Progressive warmup to PR attempt"),
        (greaseId,        "Grease the Groove",   ["easy", "easy", "easy", "easy", "moderate", "moderate", "moderate", "hard"], "High volume, low intensity"),
        (maintenanceId,   "Maintenance",         ["moderate", "moderate", "hard"],                                 "Moderate volume, hold strength"),
        (deloadId,        "Deload",              ["easy", "easy", "easy"],                                         "Recovery phase"),
        (pyramidId,       "Pyramid",             ["easy", "moderate", "hard", "pr", "hard", "moderate"],           "Build up then back off"),
        (topSetBackoffId, "Top Set + Backoff",   ["easy", "moderate", "hard", "pr", "moderate", "moderate"],       "Work up to max, drop intensity"),
    ]

}
