import Foundation
import SwiftData

@Model
final class SetPlan {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var createdTimezone: String
    var name: String
    var planDescription: String?
    var effortSequence: [String]
    var isCustom: Bool
    var deleted: Bool

    init(id: UUID = UUID(), name: String, effortSequence: [String], isCustom: Bool = true, planDescription: String? = nil) {
        self.id = id
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.name = name
        self.planDescription = planDescription
        self.effortSequence = effortSequence
        self.isCustom = isCustom
        self.deleted = false
    }

    init(id: UUID, name: String, effortSequence: [String], isCustom: Bool, planDescription: String?,
         createdAt: Date, createdTimezone: String, deleted: Bool = false) {
        self.id = id
        self.name = name
        self.effortSequence = effortSequence
        self.isCustom = isCustom
        self.planDescription = planDescription
        self.createdAt = createdAt
        self.createdTimezone = createdTimezone
        self.deleted = deleted
    }

    // MARK: - Built-in Plan IDs (deterministic)

    static let standardId        = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let greaseId          = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    static let maintenanceId     = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    static let deloadId          = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
    static let pyramidId         = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
    static let topSetBackoffId   = UUID(uuidString: "00000000-0000-0000-0000-000000000106")!
    static let reversePyramidId  = UUID(uuidString: "00000000-0000-0000-0000-000000000107")!
    static let waveLoadingId     = UUID(uuidString: "00000000-0000-0000-0000-000000000108")!
    static let clusterSetsId     = UUID(uuidString: "00000000-0000-0000-0000-000000000109")!
    static let restPauseId       = UUID(uuidString: "00000000-0000-0000-0000-000000000110")!
    static let dropSetsId        = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
    static let laddersId         = UUID(uuidString: "00000000-0000-0000-0000-000000000112")!
    static let pauseRepsId       = UUID(uuidString: "00000000-0000-0000-0000-000000000113")!
    static let speedWorkId       = UUID(uuidString: "00000000-0000-0000-0000-000000000114")!
    static let emomId            = UUID(uuidString: "00000000-0000-0000-0000-000000000115")!
    static let techniqueId       = UUID(uuidString: "00000000-0000-0000-0000-000000000116")!

    static let builtInIds: Set<UUID> = [
        standardId, greaseId, maintenanceId, deloadId, pyramidId, topSetBackoffId,
        reversePyramidId, waveLoadingId, clusterSetsId, restPauseId, dropSetsId,
        laddersId, pauseRepsId, speedWorkId, emomId, techniqueId
    ]

    /// IDs of presets available in free tier
    static let freePresetIds: Set<UUID> = [standardId, maintenanceId, deloadId]

    // MARK: - Built-in Definitions

    static let builtInPlans: [(id: UUID, name: String, sequence: [String], description: String)] = [
        (standardId,       "Standard",            ["easy", "easy", "moderate", "moderate", "hard", "pr"],                      "Progressive warmup to PR attempt"),
        (maintenanceId,    "Maintenance",         ["moderate", "moderate", "hard"],                                            "Moderate volume, hold strength"),
        (deloadId,         "Deload",              ["easy", "easy", "easy"],                                                    "Recovery phase"),
        (greaseId,         "Grease the Groove",   ["easy", "easy", "easy", "easy", "moderate", "moderate", "moderate", "hard"],"High volume, low intensity"),
        (pyramidId,        "Pyramid",             ["easy", "moderate", "hard", "pr", "hard", "moderate"],                      "Build up then back off"),
        (topSetBackoffId,  "Top Set + Backoff",   ["easy", "moderate", "hard", "pr", "moderate", "moderate"],                  "Work up to max, drop intensity"),
        (reversePyramidId, "Reverse Pyramid",     ["hard", "pr", "hard", "moderate", "moderate", "easy"],                      "Heaviest set first, then reduce"),
        (waveLoadingId,    "Wave Loading",        ["moderate", "hard", "pr", "moderate", "hard", "pr"],                        "Ascending waves of intensity"),
        (clusterSetsId,    "Cluster Sets",        ["hard", "hard", "hard", "hard", "hard"],                                    "Short rest between heavy singles/doubles"),
        (restPauseId,      "Rest-Pause",          ["hard", "pr", "hard", "hard"],                                              "Near-failure set, brief rest, continue"),
        (dropSetsId,       "Drop Sets",           ["pr", "hard", "moderate", "easy"],                                          "Reduce weight each set, rep to failure"),
        (laddersId,        "Ladders",             ["easy", "easy", "moderate", "moderate", "hard", "moderate", "hard", "pr"],   "Ascending rep ladder pattern"),
        (pauseRepsId,      "Pause Reps",          ["moderate", "moderate", "hard", "hard"],                                    "Paused reps to build positional strength"),
        (speedWorkId,      "Speed / Dynamic",     ["easy", "easy", "easy", "easy", "easy", "easy", "easy", "easy"],            "Submaximal weight, max velocity"),
        (emomId,           "EMOM",                ["moderate", "moderate", "moderate", "moderate", "moderate", "moderate"],     "Every minute on the minute"),
        (techniqueId,      "Technique",           ["easy", "easy", "easy", "moderate", "moderate"],                            "Light load, focus on form"),
    ]

}
