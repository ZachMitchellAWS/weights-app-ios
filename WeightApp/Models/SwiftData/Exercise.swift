//
//  Exercise.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import Foundation
import SwiftData

enum ExerciseLoadType: String, Codable, CaseIterable {
    case barbell = "Barbell"
    case singleLoad = "Single Load"
    case bodyweightPlusSingleLoad = "Bodyweight + Single Load"

    var allowsZeroWeight: Bool {
        switch self {
        case .barbell: return false
        case .singleLoad, .bodyweightPlusSingleLoad: return true
        }
    }

    var plateMultiplier: Double {
        switch self {
        case .barbell: return 2.0
        case .singleLoad, .bodyweightPlusSingleLoad: return 1.0
        }
    }

    var isBarbell: Bool { self == .barbell }
}

enum BodyweightProgressionStage {
    case foundation   // No set with reps >= 10 at 0 lbs AND no set with weight > 0
    case guidedLoad   // Foundation passed but not all effort tiers ready
    case organic      // Full suggestion algorithm
}

enum ExerciseMovementType: String, Codable, CaseIterable {
    case push = "Push"
    case pull = "Pull"
    case hinge = "Hinge"
    case squat = "Squat"
    case core = "Core"
    case other = "Other"
}

@Model
final class Exercise {
    #Index<Exercise>([\.deleted])

    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var createdTimezone: String
    var name: String
    var isCustom: Bool
    var loadType: String // Store as String for SwiftData compatibility
    var notes: String?
    var deleted: Bool
    var icon: String
    var movementType: String?
    var weightIncrement: Double?
    var barbellWeight: Double?

    var effectiveBarbellWeight: Double {
        barbellWeight ?? 45.0
    }

    init(name: String, isCustom: Bool, loadType: ExerciseLoadType = .barbell, movementType: ExerciseMovementType = .other, icon: String = "LiftTheBullIcon") {
        self.id = UUID()
        self.name = name
        self.isCustom = isCustom
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.loadType = loadType.rawValue
        self.movementType = movementType.rawValue
        self.notes = nil
        self.deleted = false
        self.icon = icon
    }

    init(id: UUID? = nil, name: String, isCustom: Bool, loadType: ExerciseLoadType = .barbell,
         movementType: ExerciseMovementType = .other,
         createdAt: Date = Date(), createdTimezone: String = TimeZone.current.identifier,
         notes: String? = nil, deleted: Bool = false, icon: String = "LiftTheBullIcon") {
        self.id = id ?? UUID()
        self.name = name
        self.isCustom = isCustom
        self.createdAt = createdAt
        self.createdTimezone = createdTimezone
        self.loadType = loadType.rawValue
        self.movementType = movementType.rawValue
        self.notes = notes
        self.deleted = deleted
        self.icon = icon
    }

    var exerciseLoadType: ExerciseLoadType {
        get {
            return ExerciseLoadType(rawValue: loadType) ?? .barbell
        }
        set { loadType = newValue.rawValue }
    }

    var exerciseMovementType: ExerciseMovementType {
        get {
            guard let raw = movementType else { return .other }
            return ExerciseMovementType(rawValue: raw) ?? .other
        }
        set { movementType = newValue.rawValue }
    }

    var defaultWeightIncrement: Double {
        exerciseLoadType.isBarbell ? 5.0 : 2.5
    }

    func bodyweightStage(sets: [LiftSet], allEffortTiersReady: Bool) -> BodyweightProgressionStage {
        guard exerciseLoadType == .bodyweightPlusSingleLoad else { return .organic }
        let hasFoundationSet = sets.contains { $0.reps >= 10 && $0.weight == 0 }
        let hasWeightedSet = sets.contains { $0.weight > 0 }
        if !hasFoundationSet && !hasWeightedSet { return .foundation }
        if allEffortTiersReady { return .organic }
        return .guidedLoad
    }

    var effectiveWeightIncrement: Double {
        weightIncrement ?? defaultWeightIncrement
    }

    var isBuiltIn: Bool { Exercise.builtInIds.contains(id) }

    // MARK: - Built-in Exercise IDs (deterministic)

    static let deadliftsId                              = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!
    static let squatsId                                 = UUID(uuidString: "00000000-0000-0000-0001-000000000002")!
    static let benchPressId                             = UUID(uuidString: "00000000-0000-0000-0001-000000000003")!
    static let overheadPressId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000004")!
    static let barbellRowId                             = UUID(uuidString: "00000000-0000-0000-0001-000000000005")!
    static let pullUpsId                                = UUID(uuidString: "00000000-0000-0000-0001-000000000006")!
    static let dipsId                                   = UUID(uuidString: "00000000-0000-0000-0001-000000000007")!
    static let barbellCurlsId                           = UUID(uuidString: "00000000-0000-0000-0001-000000000008")!
    static let romanianDeadliftsId                      = UUID(uuidString: "00000000-0000-0000-0001-000000000009")!
    static let dumbbellCurlsId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000010")!
    static let concentrationCurlsId                     = UUID(uuidString: "00000000-0000-0000-0001-000000000011")!
    static let inclineDumbbellCurlsId                   = UUID(uuidString: "00000000-0000-0000-0001-000000000012")!
    static let hammerCurlsId                            = UUID(uuidString: "00000000-0000-0000-0001-000000000013")!
    static let lowPulleyCurlsId                         = UUID(uuidString: "00000000-0000-0000-0001-000000000014")!
    static let highPulleyCurlsId                        = UUID(uuidString: "00000000-0000-0000-0001-000000000015")!
    static let machineCurlsId                           = UUID(uuidString: "00000000-0000-0000-0001-000000000016")!
    static let preacherCurlsId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000017")!
    static let standingReverseCurlsId                   = UUID(uuidString: "00000000-0000-0000-0001-000000000018")!
    static let seatedReverseCurlsId                     = UUID(uuidString: "00000000-0000-0000-0001-000000000019")!
    static let wristCurlsId                             = UUID(uuidString: "00000000-0000-0000-0001-000000000020")!
    static let fingerCurlsId                            = UUID(uuidString: "00000000-0000-0000-0001-000000000021")!
    static let reverseBarbellCurlsId                    = UUID(uuidString: "00000000-0000-0000-0001-000000000022")!
    static let tricepPushdownsId                        = UUID(uuidString: "00000000-0000-0000-0001-000000000023")!
    static let reverseTricepPushdownsId                 = UUID(uuidString: "00000000-0000-0000-0001-000000000024")!
    static let standingCableOverheadTricepExtensionsId  = UUID(uuidString: "00000000-0000-0000-0001-000000000025")!
    static let lyingBarbellTricepExtensionsId           = UUID(uuidString: "00000000-0000-0000-0001-000000000026")!
    static let lyingDumbbellTricepExtensionsId          = UUID(uuidString: "00000000-0000-0000-0001-000000000027")!
    static let oneArmOverheadDumbbellTricepExtensionsId = UUID(uuidString: "00000000-0000-0000-0001-000000000028")!
    static let tricepKickbacksId                        = UUID(uuidString: "00000000-0000-0000-0001-000000000029")!
    static let seatedDumbbellTricepExtensionsId         = UUID(uuidString: "00000000-0000-0000-0001-000000000030")!
    static let seatedEZBarTricepExtensionsId            = UUID(uuidString: "00000000-0000-0000-0001-000000000031")!
    static let lateralRaisesId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000032")!
    static let flyesId                                  = UUID(uuidString: "00000000-0000-0000-0001-000000000033")!
    static let sideRaisesId                             = UUID(uuidString: "00000000-0000-0000-0001-000000000034")!
    static let bulgarianSplitSquatsId                   = UUID(uuidString: "00000000-0000-0000-0001-000000000035")!
    static let barbellShrugsId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000036")!
    static let highPulleyLateralExtensionsId            = UUID(uuidString: "00000000-0000-0000-0001-000000000037")!
    static let pulloversId                              = UUID(uuidString: "00000000-0000-0000-0001-000000000038")!

    static let builtInIds: Set<UUID> = [
        deadliftsId, squatsId, benchPressId, overheadPressId, barbellRowId,
        pullUpsId, dipsId, barbellCurlsId, romanianDeadliftsId,
        dumbbellCurlsId, concentrationCurlsId, inclineDumbbellCurlsId, hammerCurlsId,
        lowPulleyCurlsId, highPulleyCurlsId, machineCurlsId, preacherCurlsId,
        standingReverseCurlsId, seatedReverseCurlsId, wristCurlsId, fingerCurlsId,
        reverseBarbellCurlsId, tricepPushdownsId, reverseTricepPushdownsId,
        standingCableOverheadTricepExtensionsId, lyingBarbellTricepExtensionsId,
        lyingDumbbellTricepExtensionsId, oneArmOverheadDumbbellTricepExtensionsId,
        tricepKickbacksId, seatedDumbbellTricepExtensionsId, seatedEZBarTricepExtensionsId,
        lateralRaisesId, flyesId, sideRaisesId,
        bulgarianSplitSquatsId, barbellShrugsId, highPulleyLateralExtensionsId, pulloversId
    ]

    // MARK: - Built-in Definitions

    static let builtInTemplates: [(id: UUID, name: String, loadType: ExerciseLoadType, movementType: ExerciseMovementType, icon: String)] = [
        (deadliftsId,                              "Deadlifts",                                      .barbell,    .hinge, "DeadliftIcon"),
        (squatsId,                                 "Squats",                                         .barbell,    .squat, "SquatIcon"),
        (benchPressId,                             "Bench Press",                                    .barbell,    .push,  "BenchPressIcon"),
        (overheadPressId,                          "Overhead Press",                                 .barbell,    .push,  "OverheadPressIcon"),
        (barbellRowId,                             "Barbell Row",                                    .barbell,    .pull,  "BarbellRowIcon"),
        (pullUpsId,                                "Pull Ups",                                       .bodyweightPlusSingleLoad, .pull,  "PullUpIcon"),
        (dipsId,                                   "Dips",                                           .bodyweightPlusSingleLoad, .push,  "DipsIcon"),
        (barbellCurlsId,                           "Barbell Curls",                                  .barbell,    .pull,  "CurlsIcon"),
        (romanianDeadliftsId,                      "Romanian Deadlifts",                             .barbell,    .hinge, "DeadliftIcon"),
        (dumbbellCurlsId,                          "Dumbbell Curls",                                 .singleLoad, .pull,  "DumbbellCurlsIcon"),
        (concentrationCurlsId,                     "Concentration Curls",                            .singleLoad, .pull,  "ConcentrationCurlsIcon"),
        (inclineDumbbellCurlsId,                   "Incline Dumbbell Curls",                         .singleLoad, .pull,  "InclineDumbbellCurlsIcon"),
        (hammerCurlsId,                            "Hammer Curls",                                   .singleLoad, .pull,  "HammerCurlsIcon"),
        (lowPulleyCurlsId,                         "Low Pulley Curls",                               .singleLoad, .pull,  "LowPulleyCurlsIcon"),
        (highPulleyCurlsId,                        "High Pulley Curls",                              .singleLoad, .pull,  "HighPulleyCurlsIcon"),
        (machineCurlsId,                           "Machine Curls",                                  .singleLoad, .pull,  "MachineCurlsIcon"),
        (preacherCurlsId,                          "Preacher Curls",                                 .singleLoad, .pull,  "PreacherCurlsIcon"),
        (standingReverseCurlsId,                   "Standing Reverse Curls",                         .singleLoad, .pull,  "StandingReverseCurlsIcon"),
        (seatedReverseCurlsId,                     "Seated Reverse Curls",                           .singleLoad, .pull,  "SeatedReverseCurlsIcon"),
        (wristCurlsId,                             "Wrist Curls",                                    .singleLoad, .pull,  "WristCurlsIcon"),
        (fingerCurlsId,                            "Finger Curls",                                   .singleLoad, .pull,  "FingerCurlsIcon"),
        (reverseBarbellCurlsId,                    "Reverse Barbell Curls",                          .barbell,    .pull,  "ReverseBarbellCurlsIcon"),
        (tricepPushdownsId,                        "Tricep Pushdowns",                               .singleLoad, .push,  "TricepPushdownsIcon"),
        (reverseTricepPushdownsId,                 "Reverse Tricep Pushdowns",                       .singleLoad, .push,  "ReverseTricepPushdownsIcon"),
        (standingCableOverheadTricepExtensionsId,  "Standing Cable Overhead Tricep Extensions",      .singleLoad, .push,  "StandingCableOverheadTricepExtensionsIcon"),
        (lyingBarbellTricepExtensionsId,           "Lying Barbell Tricep Extensions",                .barbell,    .push,  "LyingBarbellTricepExtensionsIcon"),
        (lyingDumbbellTricepExtensionsId,          "Lying Dumbbell Tricep Extensions",               .singleLoad, .push,  "LyingDumbbellTricepExtensionsIcon"),
        (oneArmOverheadDumbbellTricepExtensionsId, "One-Arm Overhead Dumbbell Tricep Extensions",    .singleLoad, .push,  "OneArmOverheadDumbbellTricepExtensionsIcon"),
        (tricepKickbacksId,                        "Tricep Kickbacks",                               .singleLoad, .push,  "TricepKickbacksIcon"),
        (seatedDumbbellTricepExtensionsId,         "Seated Dumbbell Tricep Extensions",              .singleLoad, .push,  "SeatedDumbbellTricepExtensionsIcon"),
        (seatedEZBarTricepExtensionsId,            "Seated EZ-Bar Tricep Extensions",                .barbell,    .push,  "SeatedEZBarTricepExtensionsIcon"),
        (lateralRaisesId,                          "Lateral Raises",                                 .singleLoad, .push,  "LateralRaisesIcon"),
        (flyesId,                                  "Flys",                                          .singleLoad, .push,  "FlyesIcon"),
        (sideRaisesId,                             "Side Raises",                                    .singleLoad, .push,  "SideRaisesIcon"),
        (bulgarianSplitSquatsId,                   "Bulgarian Split Squats",                         .singleLoad, .squat, "BulgarianSplitSquatsIcon"),
        (barbellShrugsId,                          "Barbell Shrugs",                                 .barbell,    .pull,  "BarbellShrugsIcon"),
        (highPulleyLateralExtensionsId,            "High Pulley Lateral Extensions",                 .singleLoad, .pull,  "HighPulleyLateralExtensionsIcon"),
        (pulloversId,                              "Pullovers",                                      .singleLoad, .pull,  "PulloversIcon"),
    ]
}
