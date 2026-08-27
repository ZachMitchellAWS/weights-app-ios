import Foundation
import SwiftData

@Model
final class SetPlan {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var createdTimezone: String
    /// UTC offset in effect where and when this record was created, in seconds EAST of
    /// UTC (negative in the Americas). Captured on device, where the OS has current
    /// timezone rules — strictly more accurate than re-deriving it later from a bundled
    /// tzdata snapshot, and immune to retroactive revisions of historical offset rules.
    ///
    /// Optional because records written before this field existed have none; readers fall
    /// back to resolving `createdTimezone` against `createdAt`. Note `0` is a legal value
    /// (UTC, London in winter), so presence checks must test for nil, not falsiness.
    var createdUtcOffsetSeconds: Int?
    var name: String
    var planDescription: String?
    var effortSequence: [String]
    var isCustom: Bool
    var deleted: Bool

    init(id: UUID = UUID(), name: String, effortSequence: [String], isCustom: Bool = true, planDescription: String? = nil) {
        self.id = id
        let now = Date()
        self.createdAt = now
        self.createdTimezone = TimeZone.current.identifier
        // `now`, not `self.createdAt` — Swift forbids reading a stored property back until
        // every one of them is initialised, and several are assigned after this point.
        self.createdUtcOffsetSeconds = TimeZone.current.secondsFromGMT(for: now)
        self.name = name
        self.planDescription = planDescription
        self.effortSequence = effortSequence
        self.isCustom = isCustom
        self.deleted = false
    }

    init(id: UUID, name: String, effortSequence: [String], isCustom: Bool, planDescription: String?,
         createdAt: Date, createdTimezone: String, createdUtcOffsetSeconds: Int? = nil,
         deleted: Bool = false) {
        self.id = id
        self.name = name
        self.effortSequence = effortSequence
        self.isCustom = isCustom
        self.planDescription = planDescription
        self.createdAt = createdAt
        self.createdTimezone = createdTimezone
        self.createdUtcOffsetSeconds = createdUtcOffsetSeconds ?? TimeZone.current.secondsFromGMT(for: createdAt)
        self.deleted = deleted
    }

    // MARK: - Effort Key Display

    /// Display label for a persisted `effortSequence` key.
    ///
    /// These keys are storage/wire values and deliberately do NOT match what the UI
    /// calls them: "redline" is the legacy key for what the app now displays as
    /// "Near Max". Deriving a label with `key.capitalized` therefore resurrects
    /// retired naming, which is exactly how "Redline" survived the rename in the
    /// set-plan catalog legend. Always route key → label through here.
    static func effortLabel(for key: String) -> String {
        switch key {
        case "easy": return "Easy"
        case "moderate": return "Moderate"
        case "hard": return "Hard"
        case "redline": return "Near Max"
        case "pr": return "Progress"
        default: return key.capitalized
        }
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
    static let quickAttemptId    = UUID(uuidString: "00000000-0000-0000-0000-000000000117")!
    static let primerId          = UUID(uuidString: "00000000-0000-0000-0000-000000000118")!
    static let openersId         = UUID(uuidString: "00000000-0000-0000-0000-000000000119")!
    static let compactStandardId = UUID(uuidString: "00000000-0000-0000-0000-000000000120")!
    static let rebuildId         = UUID(uuidString: "00000000-0000-0000-0000-000000000121")!

    static let builtInIds: Set<UUID> = [
        standardId, greaseId, maintenanceId, deloadId, pyramidId, topSetBackoffId,
        reversePyramidId, waveLoadingId, clusterSetsId, restPauseId, dropSetsId,
        laddersId, pauseRepsId, speedWorkId, emomId, techniqueId,
        quickAttemptId, primerId, openersId, compactStandardId, rebuildId
    ]

    /// IDs of presets available in free tier
    static let freePresetIds: Set<UUID> = [standardId, maintenanceId, deloadId]

    // MARK: - Built-in Definitions

    static let builtInPlans: [(id: UUID, name: String, sequence: [String], description: String)] = [
        (standardId,       "Standard",            ["easy", "easy", "moderate", "moderate", "hard", "pr"],                      "Warm-up sets followed by a progress set"),
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
        // Appended, never inserted. The picker sorts by `createdAt`, and an existing user
        // seeds these today, so they land last for them regardless — adding them at the
        // end here makes a new user see the same order.
        //
        // "redline" is the STORED spelling of what the product calls Near Max. The sessions
        // payload uses "near_max" and the backend translates on the way in; writing
        // "near_max" here would seed locally and then 400 on every set-plan sync, since
        // POST /checkin/set-plans validates against [easy, moderate, hard, redline, pr].
        (quickAttemptId,    "Quick Attempt",      ["easy", "moderate", "hard", "pr"],                                          "Fast ramp to a progress attempt when time is short"),
        (primerId,          "Primer",             ["easy", "moderate", "hard", "redline", "redline"],                          "Heavy exposure without spending an attempt; rehearsal before a future attempt"),
        (openersId,         "Openers",            ["moderate", "hard", "redline"],                                             "Short feel-heavy day at near-max intensity"),
        (compactStandardId, "Compact Standard",   ["easy", "moderate", "moderate", "hard", "pr"],                              "Standard's structure with one less warm-up set"),
        (rebuildId,         "Rebuild",            ["easy", "moderate", "moderate", "moderate", "hard"],                        "Moderate-volume builder for a stalled lift; accumulate without attempting"),
    ]

    /// Bump whenever `builtInPlans` changes.
    ///
    /// Existing users already get new plans LOCALLY for free — `SeedService.seedSetPlans`
    /// runs every launch and inserts whatever is missing. This version exists only for the
    /// backend, which is otherwise written to exactly once, at account creation.
    static let builtInCatalogVersion = 2

}
