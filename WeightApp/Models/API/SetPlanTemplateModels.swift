import Foundation

// MARK: - Data Transfer Object

struct SetPlanTemplateDTO: Codable {
    let templateId: UUID
    let name: String
    let effortSequence: [String]
    let isBuiltIn: Bool
    let createdTimezone: String
    let templateDescription: String?
    let createdDatetime: Date?
    let deleted: Bool?

    init(from template: SetPlanTemplate) {
        self.templateId = template.id
        self.name = template.name
        self.effortSequence = template.effortSequence
        self.isBuiltIn = template.isBuiltIn
        self.createdTimezone = template.createdTimezone
        self.templateDescription = template.templateDescription
        self.createdDatetime = template.createdAt
        self.deleted = template.deleted
    }

    init(templateId: UUID, name: String, effortSequence: [String], isBuiltIn: Bool,
         createdTimezone: String, templateDescription: String? = nil,
         createdDatetime: Date? = nil, deleted: Bool? = nil) {
        self.templateId = templateId
        self.name = name
        self.effortSequence = effortSequence
        self.isBuiltIn = isBuiltIn
        self.createdTimezone = createdTimezone
        self.templateDescription = templateDescription
        self.createdDatetime = createdDatetime
        self.deleted = deleted
    }
}

// MARK: - Request Models

struct UpsertSetPlanTemplatesRequest: Codable {
    let templates: [SetPlanTemplateDTO]
}

struct DeleteSetPlanTemplatesRequest: Codable {
    let templateIds: [UUID]
}

// MARK: - Response Models

struct GetSetPlanTemplatesResponse: Codable {
    let templates: [SetPlanTemplateDTO]
}

struct UpsertSetPlanTemplatesResponse: Codable {
    let templates: [SetPlanTemplateDTO]?
    let created: Int?
    let updated: Int?
}

struct DeleteSetPlanTemplatesResponse: Codable {
    let message: String
}

// MARK: - SetPlanTemplate Extension

extension SetPlanTemplate {
    func toDTO() -> SetPlanTemplateDTO {
        return SetPlanTemplateDTO(from: self)
    }
}
