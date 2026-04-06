import Foundation

// MARK: - Data Transfer Object

struct SetPlanDTO: Codable {
    let planId: UUID
    let name: String
    let effortSequence: [String]
    let isCustom: Bool
    let createdTimezone: String
    let planDescription: String?
    let createdDatetime: Date?
    let deleted: Bool?

    init(from plan: SetPlan) {
        self.planId = plan.id
        self.name = plan.name
        self.effortSequence = plan.effortSequence
        self.isCustom = plan.isCustom
        self.createdTimezone = plan.createdTimezone
        self.planDescription = plan.planDescription
        self.createdDatetime = plan.createdAt
        self.deleted = plan.deleted
    }

    init(planId: UUID, name: String, effortSequence: [String], isCustom: Bool,
         createdTimezone: String, planDescription: String? = nil,
         createdDatetime: Date? = nil, deleted: Bool? = nil) {
        self.planId = planId
        self.name = name
        self.effortSequence = effortSequence
        self.isCustom = isCustom
        self.createdTimezone = createdTimezone
        self.planDescription = planDescription
        self.createdDatetime = createdDatetime
        self.deleted = deleted
    }
}

// MARK: - Request Models

struct UpsertSetPlansRequest: Codable {
    let plans: [SetPlanDTO]
}

struct DeleteSetPlansRequest: Codable {
    let planIds: [UUID]
}

// MARK: - Response Models

struct GetSetPlansResponse: Codable {
    let plans: [SetPlanDTO]
}

struct UpsertSetPlansResponse: Codable {
    let plans: [SetPlanDTO]?
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
