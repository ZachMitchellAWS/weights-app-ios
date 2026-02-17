import Foundation

// MARK: - Data Transfer Object

struct SequenceDTO: Codable {
    let sequenceId: UUID
    let name: String
    let exerciseIds: [UUID]
    let createdTimezone: String
    let createdDatetime: Date?
    let deleted: Bool?

    init(from sequence: WorkoutSequence) {
        self.sequenceId = sequence.id
        self.name = sequence.name
        self.exerciseIds = sequence.exerciseIds
        self.createdTimezone = sequence.createdTimezone
        self.createdDatetime = sequence.createdAt
        self.deleted = sequence.deleted
    }

    init(sequenceId: UUID, name: String, exerciseIds: [UUID], createdTimezone: String, createdDatetime: Date? = nil, deleted: Bool? = nil) {
        self.sequenceId = sequenceId
        self.name = name
        self.exerciseIds = exerciseIds
        self.createdTimezone = createdTimezone
        self.createdDatetime = createdDatetime
        self.deleted = deleted
    }
}

// MARK: - Request Models

struct UpsertSequencesRequest: Codable {
    let sequences: [SequenceDTO]
}

struct DeleteSequencesRequest: Codable {
    let sequenceIds: [UUID]
}

// MARK: - Response Models

struct GetSequencesResponse: Codable {
    let sequences: [SequenceDTO]
}

struct UpsertSequencesResponse: Codable {
    let sequences: [SequenceDTO]?
    let created: Int?
    let updated: Int?
}

struct DeleteSequencesResponse: Codable {
    let message: String
}

// MARK: - WorkoutSequence Extension

extension WorkoutSequence {
    func toDTO() -> SequenceDTO {
        return SequenceDTO(from: self)
    }
}
