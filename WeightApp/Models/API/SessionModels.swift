//
//  SessionModels.swift
//  WeightApp
//
//  Wire types for POST /sessions/generate.
//
//  Contract: WeightApp-backend/frontend-api-context/sessions.md
//
//  The backend assembles the model's inputs itself — recent training, strength tiers,
//  local dates — by reading DynamoDB. We send only the two things it cannot know: the set
//  plan catalog (which lives in client code and includes plans the user wrote) and
//  whatever the user said about today.
//
//  These use snake_case on the wire, unlike the rest of the app's DTOs. `APIService`
//  encodes with a plain `JSONEncoder` and no key strategy, so every property here carries
//  explicit `CodingKeys` rather than relying on a converter that is not configured.
//

import Foundation

// MARK: - Request

struct GeneratedSessionRequest: Encodable {
    let setPlanCatalog: [SetPlanCatalogEntry]
    let userContext: SessionUserContext

    enum CodingKeys: String, CodingKey {
        case setPlanCatalog = "set_plan_catalog"
        case userContext = "user_context"
    }
}

struct SetPlanCatalogEntry: Encodable {
    let id: String
    let name: String
    /// Sent as the app stores them — "redline" and "pr" included. The backend normalizes
    /// those to its own "near_max"/"progress" spellings, so translating here would be
    /// duplicated work with two chances to drift.
    let sequence: [String]
    let description: String
}

struct SessionUserContext: Encodable {
    let chips: [String]
    let note: String
}

// MARK: - Response

struct GeneratedSessionResponse: Decodable {
    let session: GeneratedSession
    /// True when the user has already trained everything worth recommending today, so the
    /// generator deliberately chose nothing. A real answer, not a failure.
    ///
    /// Sent explicitly rather than inferred from `session.items.isEmpty`, because the
    /// client must distinguish this from the different case where items arrived but none
    /// resolved to a local exercise — one is normal, the other is a bug worth reporting.
    let nothingToRecommend: Bool?
    /// False when the free-text note was withheld from the generator — flagged by
    /// moderation, or unscreenable because the service was down.
    ///
    /// Deliberately one boolean with no reason code. Both causes are "couldn't be used" to
    /// the user, and distinguishing them would tell anyone probing the filter which of the
    /// two they hit. Optional so older responses decode as "used".
    let noteUsed: Bool?

    enum CodingKeys: String, CodingKey {
        case session
        case nothingToRecommend = "nothing_to_recommend"
        case noteUsed = "note_used"
    }
}

struct GeneratedSession: Decodable {
    let summary: String
    let items: [GeneratedSessionItem]
}

struct GeneratedSessionItem: Decodable {
    /// `exerciseItemId`. Guaranteed to be one we sent — the backend rejects its own
    /// generation with a 502 rather than returning an id that resolves to nothing.
    let exerciseId: String
    let exerciseName: String
    let setPlanId: String
    let setPlanName: String
    let rationale: String

    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case exerciseName = "exercise_name"
        case setPlanId = "set_plan_id"
        case setPlanName = "set_plan_name"
        case rationale
    }
}
