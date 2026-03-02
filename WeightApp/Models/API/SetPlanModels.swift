import Foundation

// MARK: - Data Transfer Object

struct SetPlanDTO: Codable {
    let templateId: UUID
    let name: String
    let effortSequence: [String]
    let isCustom: Bool
    let createdTimezone: String
    let templateDescription: String?
    let createdDatetime: Date?
    let deleted: Bool?

    init(from template: SetPlan) {
        self.templateId = template.id
        self.name = template.name
        self.effortSequence = template.effortSequence
        self.isCustom = template.isCustom
        self.createdTimezone = template.createdTimezone
        self.templateDescription = template.templateDescription
        self.createdDatetime = template.createdAt
        self.deleted = template.deleted
    }

    init(templateId: UUID, name: String, effortSequence: [String], isCustom: Bool,
         createdTimezone: String, templateDescription: String? = nil,
         createdDatetime: Date? = nil, deleted: Bool? = nil) {
        self.templateId = templateId
        self.name = name
        self.effortSequence = effortSequence
        self.isCustom = isCustom
        self.createdTimezone = createdTimezone
        self.templateDescription = templateDescription
        self.createdDatetime = createdDatetime
        self.deleted = deleted
    }
}

// MARK: - Request Models

struct UpsertSetPlansRequest: Codable {
    let templates: [SetPlanDTO]
}

struct DeleteSetPlansRequest: Codable {
    let templateIds: [UUID]
}

// MARK: - Response Models

struct GetSetPlansResponse: Codable {
    let templates: [SetPlanDTO]
}

struct UpsertSetPlansResponse: Codable {
    let templates: [SetPlanDTO]?
    let created: Int?
    let updated: Int?
}

struct DeleteSetPlansResponse: Codable {
    let message: String
}

// MARK: - SetPlan Extension

extension SetPlan {
    func toDTO() -> SetPlanDTO {
        return SetPlanDTO(from: self)
    }
}
