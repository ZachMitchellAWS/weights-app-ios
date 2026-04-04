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
    var currentE1RM: Double?
    var currentE1RMDate: Date?

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
        2.5
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
    static let standingCalfRaisesId                     = UUID(uuidString: "00000000-0000-0000-0001-000000000039")!
    static let cableRowsId                              = UUID(uuidString: "00000000-0000-0000-0001-000000000040")!
    static let closeGripBenchPressId                    = UUID(uuidString: "00000000-0000-0000-0001-000000000041")!
    static let rearDeltFlysId                           = UUID(uuidString: "00000000-0000-0000-0001-000000000042")!
    static let cableYRaisesId                           = UUID(uuidString: "00000000-0000-0000-0001-000000000043")!
    static let frontSquatsId                            = UUID(uuidString: "00000000-0000-0000-0001-000000000044")!
    static let backExtensionsId                         = UUID(uuidString: "00000000-0000-0000-0001-000000000045")!
    static let hangingLegRaisesId                       = UUID(uuidString: "00000000-0000-0000-0001-000000000046")!

    // Batch 1 — Shoulders / Raises
    static let backPressesId                            = UUID(uuidString: "00000000-0000-0000-0001-000000000047")!
    static let seatedFrontPressesId                     = UUID(uuidString: "00000000-0000-0000-0001-000000000048")!
    static let seatedDumbbellPressesId                  = UUID(uuidString: "00000000-0000-0000-0001-000000000049")!
    static let arnoldPressesId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000050")!
    static let bentOverLateralRaisesId                  = UUID(uuidString: "00000000-0000-0000-0001-000000000051")!
    static let alternatingFrontRaisesId                 = UUID(uuidString: "00000000-0000-0000-0001-000000000052")!
    static let barbellFrontRaisesId                     = UUID(uuidString: "00000000-0000-0000-0001-000000000053")!
    static let uprightRowsId                            = UUID(uuidString: "00000000-0000-0000-0001-000000000054")!
    static let machineLateralRaisesId                   = UUID(uuidString: "00000000-0000-0000-0001-000000000055")!
    static let pecDeckRearDeltLateralsId                = UUID(uuidString: "00000000-0000-0000-0001-000000000056")!
    static let pulleyExternalArmRotationsId             = UUID(uuidString: "00000000-0000-0000-0001-000000000057")!
    static let lowPulleyBentOverLateralRaisesId         = UUID(uuidString: "00000000-0000-0000-0001-000000000058")!
    static let lowPulleyLateralRaisesId                 = UUID(uuidString: "00000000-0000-0000-0001-000000000059")!
    static let oneDumbbellFrontRaisesId                 = UUID(uuidString: "00000000-0000-0000-0001-000000000060")!

    // Batch 2 — Chest / Back / Traps / Deadlift Variants
    static let inclineBenchPressId                      = UUID(uuidString: "00000000-0000-0000-0001-000000000061")!
    static let declineBenchPressId                      = UUID(uuidString: "00000000-0000-0000-0001-000000000062")!
    static let machineBenchPressId                      = UUID(uuidString: "00000000-0000-0000-0001-000000000063")!
    static let pushUpsId                                = UUID(uuidString: "00000000-0000-0000-0001-000000000064")!
    static let dumbbellBenchPressId                     = UUID(uuidString: "00000000-0000-0000-0001-000000000065")!
    static let inclineDumbbellPressesId                 = UUID(uuidString: "00000000-0000-0000-0001-000000000066")!
    static let inclineDumbbellFlysId                    = UUID(uuidString: "00000000-0000-0000-0001-000000000067")!
    static let pecDeckFlysId                            = UUID(uuidString: "00000000-0000-0000-0001-000000000068")!
    static let cableFlysId                              = UUID(uuidString: "00000000-0000-0000-0001-000000000069")!
    static let barbellPulloversId                       = UUID(uuidString: "00000000-0000-0000-0001-000000000070")!
    static let chinUpsId                                = UUID(uuidString: "00000000-0000-0000-0001-000000000071")!
    static let latPullDownsId                           = UUID(uuidString: "00000000-0000-0000-0001-000000000072")!
    static let closeGripLatPullDownsId                  = UUID(uuidString: "00000000-0000-0000-0001-000000000073")!
    static let straightArmPullDownsId                   = UUID(uuidString: "00000000-0000-0000-0001-000000000074")!
    static let closeGripSeatedRowsId                    = UUID(uuidString: "00000000-0000-0000-0001-000000000075")!
    static let wideGripSeatedRowsId                     = UUID(uuidString: "00000000-0000-0000-0001-000000000076")!
    static let singleArmDumbbellRowsId                  = UUID(uuidString: "00000000-0000-0000-0001-000000000077")!
    static let bentOverDumbbellRowsId                   = UUID(uuidString: "00000000-0000-0000-0001-000000000078")!
    static let closeGripUprightRowsId                   = UUID(uuidString: "00000000-0000-0000-0001-000000000079")!
    static let tBarRowsId                               = UUID(uuidString: "00000000-0000-0000-0001-000000000080")!
    static let supportedTBarRowsId                      = UUID(uuidString: "00000000-0000-0000-0001-000000000081")!
    static let sumoDeadliftsId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000082")!
    static let trapBarDeadliftsId                       = UUID(uuidString: "00000000-0000-0000-0001-000000000083")!
    static let machineBackExtensionsId                  = UUID(uuidString: "00000000-0000-0000-0001-000000000084")!
    static let dumbbellShrugsId                         = UUID(uuidString: "00000000-0000-0000-0001-000000000085")!
    static let trapBarShrugsId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000086")!
    static let machineShrugsId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000087")!
    static let highPulleyNeckPullsId                    = UUID(uuidString: "00000000-0000-0000-0001-000000000088")!
    static let highPulleyNeckExtensionsId               = UUID(uuidString: "00000000-0000-0000-0001-000000000089")!

    // Batch 3 — Legs / Glutes / Calves / Core
    static let dumbbellSquatsId                         = UUID(uuidString: "00000000-0000-0000-0001-000000000090")!
    static let powerSquatsId                            = UUID(uuidString: "00000000-0000-0000-0001-000000000091")!
    static let hackSquatsId                             = UUID(uuidString: "00000000-0000-0000-0001-000000000092")!
    static let legPressId                               = UUID(uuidString: "00000000-0000-0000-0001-000000000093")!
    static let boxSquatsId                              = UUID(uuidString: "00000000-0000-0000-0001-000000000094")!
    static let legExtensionsId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000095")!
    static let lyingLegCurlsId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000096")!
    static let seatedLegCurlsId                         = UUID(uuidString: "00000000-0000-0000-0001-000000000097")!
    static let goodMorningsId                           = UUID(uuidString: "00000000-0000-0000-0001-000000000098")!
    static let cableHipAdductionsId                     = UUID(uuidString: "00000000-0000-0000-0001-000000000099")!
    static let seatedMachineHipAdductionsId             = UUID(uuidString: "00000000-0000-0000-0001-000000000100")!
    static let standingMachineCalfRaisesId              = UUID(uuidString: "00000000-0000-0000-0001-000000000101")!
    static let donkeyCalfRaisesId                       = UUID(uuidString: "00000000-0000-0000-0001-000000000102")!
    static let seatedMachineCalfRaisesId                = UUID(uuidString: "00000000-0000-0000-0001-000000000103")!
    static let barbellLungesId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000104")!
    static let dumbbellLungesId                         = UUID(uuidString: "00000000-0000-0000-0001-000000000105")!
    static let cableKickbacksId                         = UUID(uuidString: "00000000-0000-0000-0001-000000000106")!
    static let machineHipExtensionsId                   = UUID(uuidString: "00000000-0000-0000-0001-000000000107")!
    static let gluteBridgesId                           = UUID(uuidString: "00000000-0000-0000-0001-000000000108")!
    static let cableHipAbductionsId                     = UUID(uuidString: "00000000-0000-0000-0001-000000000109")!
    static let standingMachineHipAbductionsId           = UUID(uuidString: "00000000-0000-0000-0001-000000000110")!
    static let seatedMachineHipAbductionsId             = UUID(uuidString: "00000000-0000-0000-0001-000000000111")!
    static let crunchesId                               = UUID(uuidString: "00000000-0000-0000-0001-000000000112")!
    static let sitUpsId                                 = UUID(uuidString: "00000000-0000-0000-0001-000000000113")!
    static let cableCrunchesId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000114")!
    static let machineCrunchesId                        = UUID(uuidString: "00000000-0000-0000-0001-000000000115")!
    static let legRaisesId                              = UUID(uuidString: "00000000-0000-0000-0001-000000000116")!
    static let dumbbellSideBendsId                      = UUID(uuidString: "00000000-0000-0000-0001-000000000117")!
    static let machineTorsoRotationsId                  = UUID(uuidString: "00000000-0000-0000-0001-000000000118")!

    // Batch 4 — Miscellaneous / Gaps
    static let facePullsId                              = UUID(uuidString: "00000000-0000-0000-0001-000000000119")!
    static let pendlayRowsId                            = UUID(uuidString: "00000000-0000-0000-0001-000000000120")!
    static let ezBarCurlsId                             = UUID(uuidString: "00000000-0000-0000-0001-000000000121")!
    static let spiderCurlsId                            = UUID(uuidString: "00000000-0000-0000-0001-000000000122")!
    static let hipThrustsId                             = UUID(uuidString: "00000000-0000-0000-0001-000000000123")!
    static let gobletSquatsId                           = UUID(uuidString: "00000000-0000-0000-0001-000000000124")!
    static let stepUpsId                                = UUID(uuidString: "00000000-0000-0000-0001-000000000125")!
    static let abWheelRolloutsId                        = UUID(uuidString: "00000000-0000-0000-0001-000000000126")!
    static let pallofPressId                            = UUID(uuidString: "00000000-0000-0000-0001-000000000127")!
    static let cableWoodchopsId                         = UUID(uuidString: "00000000-0000-0000-0001-000000000128")!
    static let powerCleansId                            = UUID(uuidString: "00000000-0000-0000-0001-000000000129")!
    static let farmersCarriesId                         = UUID(uuidString: "00000000-0000-0000-0001-000000000130")!
    static let cableLateralRaisesId                     = UUID(uuidString: "00000000-0000-0000-0001-000000000131")!
    static let landminePressId                          = UUID(uuidString: "00000000-0000-0000-0001-000000000132")!

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
        bulgarianSplitSquatsId, barbellShrugsId, highPulleyLateralExtensionsId, pulloversId,
        standingCalfRaisesId, cableRowsId, closeGripBenchPressId, rearDeltFlysId,
        cableYRaisesId, frontSquatsId, backExtensionsId, hangingLegRaisesId,
        // Batch 1
        backPressesId, seatedFrontPressesId, seatedDumbbellPressesId, arnoldPressesId,
        bentOverLateralRaisesId, alternatingFrontRaisesId, barbellFrontRaisesId, uprightRowsId,
        machineLateralRaisesId, pecDeckRearDeltLateralsId, pulleyExternalArmRotationsId,
        lowPulleyBentOverLateralRaisesId, lowPulleyLateralRaisesId, oneDumbbellFrontRaisesId,
        // Batch 2
        inclineBenchPressId, declineBenchPressId, machineBenchPressId, pushUpsId,
        dumbbellBenchPressId, inclineDumbbellPressesId, inclineDumbbellFlysId,
        pecDeckFlysId, cableFlysId, barbellPulloversId, chinUpsId,
        latPullDownsId, closeGripLatPullDownsId, straightArmPullDownsId,
        closeGripSeatedRowsId, wideGripSeatedRowsId, singleArmDumbbellRowsId,
        bentOverDumbbellRowsId, closeGripUprightRowsId, tBarRowsId, supportedTBarRowsId,
        sumoDeadliftsId, trapBarDeadliftsId, machineBackExtensionsId,
        dumbbellShrugsId, trapBarShrugsId, machineShrugsId,
        highPulleyNeckPullsId, highPulleyNeckExtensionsId,
        // Batch 3
        dumbbellSquatsId, powerSquatsId, hackSquatsId, legPressId, boxSquatsId,
        legExtensionsId, lyingLegCurlsId, seatedLegCurlsId, goodMorningsId,
        cableHipAdductionsId, seatedMachineHipAdductionsId,
        standingMachineCalfRaisesId, donkeyCalfRaisesId, seatedMachineCalfRaisesId,
        barbellLungesId, dumbbellLungesId, cableKickbacksId, machineHipExtensionsId,
        gluteBridgesId, cableHipAbductionsId, standingMachineHipAbductionsId,
        seatedMachineHipAbductionsId, crunchesId, sitUpsId, cableCrunchesId,
        machineCrunchesId, legRaisesId, dumbbellSideBendsId, machineTorsoRotationsId,
        // Batch 4
        facePullsId, pendlayRowsId, ezBarCurlsId, spiderCurlsId, hipThrustsId,
        gobletSquatsId, stepUpsId, abWheelRolloutsId, pallofPressId, cableWoodchopsId,
        powerCleansId, farmersCarriesId, cableLateralRaisesId, landminePressId
    ]

    // MARK: - Built-in Definitions

    static let builtInTemplates: [(id: UUID, name: String, loadType: ExerciseLoadType, movementType: ExerciseMovementType, icon: String)] = [
        (deadliftsId,                              "Deadlifts",                                      .barbell,    .hinge, "DeadliftIcon"),
        (squatsId,                                 "Squats",                                         .barbell,    .squat, "SquatIcon"),
        (benchPressId,                             "Bench Press",                                    .barbell,    .push,  "BenchPressIcon"),
        (overheadPressId,                          "Overhead Press",                                 .barbell,    .push,  "OverheadPressIcon"),
        (barbellRowId,                             "Barbell Rows",                                    .barbell,    .pull,  "BarbellRowIcon"),
        (pullUpsId,                                "Pull Ups",                                       .bodyweightPlusSingleLoad, .pull,  "PullUpIcon"),
        (dipsId,                                   "Weighted Dips",                                  .bodyweightPlusSingleLoad, .push,  "DipsIcon"),
        (barbellCurlsId,                           "Barbell Curls",                                  .barbell,    .pull,  "CurlsIcon"),
        (romanianDeadliftsId,                      "Romanian Deadlifts",                             .barbell,    .hinge, "RomanianDeadliftsIcon"),
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
        (flyesId,                                  "Dumbbell Flys",                                  .singleLoad, .push,  "DumbbellFlysIcon"),
        (sideRaisesId,                             "Side Raises",                                    .singleLoad, .push,  "SideRaisesIcon"),
        (bulgarianSplitSquatsId,                   "Bulgarian Split Squats",                         .singleLoad, .squat, "BulgarianSplitSquatsIcon"),
        (barbellShrugsId,                          "Barbell Shrugs",                                 .barbell,    .pull,  "BarbellShrugsIcon"),
        (highPulleyLateralExtensionsId,            "High Pulley Lateral Extensions",                 .singleLoad, .pull,  "HighPulleyLateralExtensionsIcon"),
        (pulloversId,                              "Dumbbell Pullovers",                             .singleLoad, .pull,  "DumbbellPulloversIcon"),
        (standingCalfRaisesId,                     "Standing Calf Raises",                           .singleLoad, .other, "StandingCalfRaisesIcon"),
        (cableRowsId,                              "Cable Rows",                                     .singleLoad, .pull,  "CableRowsIcon"),
        (closeGripBenchPressId,                    "Close Grip Bench Press",                         .barbell,    .push,  "CloseGripBenchPressIcon"),
        (rearDeltFlysId,                           "Rear Delt Flys",                                 .singleLoad, .pull,  "RearDeltFlysIcon"),
        (cableYRaisesId,                           "Cable Y Raises",                                 .singleLoad, .pull,  "CableYRaisesIcon"),
        (frontSquatsId,                            "Front Squats",                                   .barbell,    .squat, "FrontSquatsIcon"),
        (backExtensionsId,                         "Back Extensions",                                .singleLoad, .hinge, "BackExtensionsIcon"),
        (hangingLegRaisesId,                       "Hanging Leg Raises",                             .bodyweightPlusSingleLoad, .core,  "HangingLegRaisesIcon"),

        // Batch 1 — Shoulders / Raises
        (backPressesId,                            "Back Presses",                                   .barbell,    .push,  "BackPressesIcon"),
        (seatedFrontPressesId,                     "Seated Front Presses",                           .barbell,    .push,  "SeatedFrontPressesIcon"),
        (seatedDumbbellPressesId,                  "Seated Dumbbell Presses",                        .singleLoad, .push,  "SeatedDumbbellPressesIcon"),
        (arnoldPressesId,                          "Arnold Presses",                                 .singleLoad, .push,  "ArnoldPressesIcon"),
        (bentOverLateralRaisesId,                  "Bent Over Lateral Raises",                       .singleLoad, .pull,  "BentOverLateralRaisesIcon"),
        (alternatingFrontRaisesId,                 "Alternating Front Raises",                       .singleLoad, .push,  "AlternatingFrontRaisesIcon"),
        (barbellFrontRaisesId,                     "Barbell Front Raises",                           .barbell,    .push,  "BarbellFrontRaisesIcon"),
        (uprightRowsId,                            "Upright Rows",                                   .barbell,    .pull,  "UprightRowsIcon"),
        (machineLateralRaisesId,                   "Machine Lateral Raises",                         .singleLoad, .push,  "MachineLateralRaisesIcon"),
        (pecDeckRearDeltLateralsId,                "Pec Deck Rear Delt Laterals",                    .singleLoad, .pull,  "PecDeckRearDeltLateralsIcon"),
        (pulleyExternalArmRotationsId,             "Pulley External Arm Rotations",                  .singleLoad, .pull,  "PulleyExternalArmRotationsIcon"),
        (lowPulleyBentOverLateralRaisesId,         "Low Pulley Bent-Over Lateral Raises",            .singleLoad, .pull,  "LowPulleyBentOverLateralRaisesIcon"),
        (lowPulleyLateralRaisesId,                 "Low Pulley Lateral Raises",                      .singleLoad, .push,  "LowPulleyLateralRaisesIcon"),
        (oneDumbbellFrontRaisesId,                 "One Dumbbell Front Raises",                      .singleLoad, .push,  "OneDumbbellFrontRaisesIcon"),

        // Batch 2 — Chest / Back / Traps / Deadlift Variants
        (inclineBenchPressId,                      "Incline Bench Press",                            .barbell,    .push,  "InclineBenchPressIcon"),
        (declineBenchPressId,                      "Decline Bench Press",                            .barbell,    .push,  "DeclineBenchPressIcon"),
        (machineBenchPressId,                      "Machine Bench Press",                            .singleLoad, .push,  "MachineBenchPressIcon"),
        (pushUpsId,                                "Push-Ups",                                       .bodyweightPlusSingleLoad, .push,  "PushUpsIcon"),
        (dumbbellBenchPressId,                     "Dumbbell Bench Press",                           .singleLoad, .push,  "DumbbellBenchPressIcon"),
        (inclineDumbbellPressesId,                 "Incline Dumbbell Presses",                       .singleLoad, .push,  "InclineDumbbellPressesIcon"),
        (inclineDumbbellFlysId,                    "Incline Dumbbell Flys",                          .singleLoad, .push,  "InclineDumbbellFlysIcon"),
        (pecDeckFlysId,                            "Pec Deck Flys",                                  .singleLoad, .push,  "PecDeckFlysIcon"),
        (cableFlysId,                              "Cable Flys",                                     .singleLoad, .push,  "CableFlysIcon"),
        (barbellPulloversId,                       "Barbell Pullovers",                              .barbell,    .pull,  "BarbellPulloversIcon"),
        (chinUpsId,                                "Chin-Ups",                                       .bodyweightPlusSingleLoad, .pull,  "ChinUpsIcon"),
        (latPullDownsId,                           "Lat Pull-Downs",                                 .singleLoad, .pull,  "LatPullDownsIcon"),
        (closeGripLatPullDownsId,                  "Close Grip Lat Pull-Downs",                      .singleLoad, .pull,  "CloseGripLatPullDownsIcon"),
        (straightArmPullDownsId,                   "Straight Arm Pull-Downs",                        .singleLoad, .pull,  "StraightArmPullDownsIcon"),
        (closeGripSeatedRowsId,                    "Close Grip Seated Rows",                         .singleLoad, .pull,  "CloseGripSeatedRowsIcon"),
        (wideGripSeatedRowsId,                     "Wide Grip Seated Rows",                          .singleLoad, .pull,  "WideGripSeatedRowsIcon"),
        (singleArmDumbbellRowsId,                  "Single Arm Dumbbell Rows",                       .singleLoad, .pull,  "SingleArmDumbbellRowsIcon"),
        (bentOverDumbbellRowsId,                   "Bent Over Dumbbell Rows",                        .singleLoad, .pull,  "BentOverDumbbellRowsIcon"),
        (closeGripUprightRowsId,                   "Close Grip Upright Rows",                        .barbell,    .pull,  "CloseGripUprightRowsIcon"),
        (tBarRowsId,                               "T-Bar Rows",                                     .barbell,    .pull,  "TBarRowsIcon"),
        (supportedTBarRowsId,                      "Supported T-Bar Rows",                           .barbell,    .pull,  "SupportedTBarRowsIcon"),
        (sumoDeadliftsId,                          "Sumo Deadlifts",                                 .barbell,    .hinge, "SumoDeadliftsIcon"),
        (trapBarDeadliftsId,                       "Trap Bar Deadlifts",                             .barbell,    .hinge, "TrapBarDeadliftsIcon"),
        (machineBackExtensionsId,                  "Machine Back Extensions",                        .singleLoad, .hinge, "MachineBackExtensionsIcon"),
        (dumbbellShrugsId,                         "Dumbbell Shrugs",                                .singleLoad, .pull,  "DumbbellShrugsIcon"),
        (trapBarShrugsId,                          "Trap Bar Shrugs",                                .barbell,    .pull,  "TrapBarShrugsIcon"),
        (machineShrugsId,                          "Machine Shrugs",                                 .singleLoad, .pull,  "MachineShrugsIcon"),
        (highPulleyNeckPullsId,                    "High Pulley Neck Pulls",                         .singleLoad, .pull,  "HighPulleyNeckPullsIcon"),
        (highPulleyNeckExtensionsId,               "High Pulley Neck Extensions",                    .singleLoad, .push,  "HighPulleyNeckExtensionsIcon"),

        // Batch 3 — Legs / Glutes / Calves / Core
        (dumbbellSquatsId,                         "Dumbbell Squats",                                .singleLoad, .squat, "DumbbellSquatsIcon"),
        (powerSquatsId,                            "Power Squats",                                   .singleLoad, .squat, "PowerSquatsIcon"),
        (hackSquatsId,                             "Hack Squats",                                    .singleLoad, .squat, "HackSquatsIcon"),
        (legPressId,                               "Leg Press",                                      .singleLoad, .squat, "LegPressIcon"),
        (boxSquatsId,                              "Box Squats",                                     .barbell,    .squat, "BoxSquatsIcon"),
        (legExtensionsId,                          "Leg Extensions",                                 .singleLoad, .squat, "LegExtensionsIcon"),
        (lyingLegCurlsId,                          "Lying Leg Curls",                                .singleLoad, .hinge, "LyingLegCurlsIcon"),
        (seatedLegCurlsId,                         "Seated Leg Curls",                               .singleLoad, .hinge, "SeatedLegCurlsIcon"),
        (goodMorningsId,                           "Good Mornings",                                  .barbell,    .hinge, "GoodMorningsIcon"),
        (cableHipAdductionsId,                     "Cable Hip Adductions",                           .singleLoad, .other, "CableHipAdductionsIcon"),
        (seatedMachineHipAdductionsId,             "Seated Machine Hip Adductions",                  .singleLoad, .other, "SeatedMachineHipAdductionsIcon"),
        (standingMachineCalfRaisesId,              "Standing Machine Calf Raises",                   .singleLoad, .other, "StandingMachineCalfRaisesIcon"),
        (donkeyCalfRaisesId,                       "Donkey Calf Raises",                             .singleLoad, .other, "DonkeyCalfRaisesIcon"),
        (seatedMachineCalfRaisesId,                "Seated Machine Calf Raises",                     .singleLoad, .other, "SeatedMachineCalfRaisesIcon"),
        (barbellLungesId,                          "Barbell Lunges",                                 .barbell,    .squat, "BarbellLungesIcon"),
        (dumbbellLungesId,                         "Dumbbell Lunges",                                .singleLoad, .squat, "DumbbellLungesIcon"),
        (cableKickbacksId,                         "Cable Kickbacks",                                .singleLoad, .other, "CableKickbacksIcon"),
        (machineHipExtensionsId,                   "Machine Hip Extensions",                         .singleLoad, .hinge, "MachineHipExtensionsIcon"),
        (gluteBridgesId,                           "Glute Bridges",                                  .barbell,    .hinge, "GluteBridgesIcon"),
        (cableHipAbductionsId,                     "Cable Hip Abductions",                           .singleLoad, .other, "CableHipAbductionsIcon"),
        (standingMachineHipAbductionsId,           "Standing Machine Hip Abductions",                .singleLoad, .other, "StandingMachineHipAbductionsIcon"),
        (seatedMachineHipAbductionsId,             "Seated Machine Hip Abductions",                  .singleLoad, .other, "SeatedMachineHipAbductionsIcon"),
        (crunchesId,                               "Crunches",                                       .bodyweightPlusSingleLoad, .core, "CrunchesIcon"),
        (sitUpsId,                                 "Sit-Ups",                                        .bodyweightPlusSingleLoad, .core, "SitUpsIcon"),
        (cableCrunchesId,                          "Cable Crunches",                                 .singleLoad, .core,  "CableCrunchesIcon"),
        (machineCrunchesId,                        "Machine Crunches",                               .singleLoad, .core,  "MachineCrunchesIcon"),
        (legRaisesId,                              "Leg Raises",                                     .bodyweightPlusSingleLoad, .core, "LegRaisesIcon"),
        (dumbbellSideBendsId,                      "Dumbbell Side Bends",                            .singleLoad, .core,  "DumbbellSideBendsIcon"),
        (machineTorsoRotationsId,                  "Machine Torso Rotations",                        .singleLoad, .core,  "MachineTorsoRotationsIcon"),

        // Batch 4 — Miscellaneous / Gaps
        (facePullsId,                              "Face Pulls",                                     .singleLoad, .pull,  "FacePullsIcon"),
        (pendlayRowsId,                            "Pendlay Rows",                                   .barbell,    .pull,  "PendlayRowsIcon"),
        (ezBarCurlsId,                             "EZ-Bar Curls",                                   .barbell,    .pull,  "EZBarCurlsIcon"),
        (spiderCurlsId,                            "Spider Curls",                                   .singleLoad, .pull,  "SpiderCurlsIcon"),
        (hipThrustsId,                             "Hip Thrusts",                                    .barbell,    .hinge, "HipThrustsIcon"),
        (gobletSquatsId,                           "Goblet Squats",                                  .singleLoad, .squat, "GobletSquatsIcon"),
        (stepUpsId,                                "Step-Ups",                                       .singleLoad, .squat, "StepUpsIcon"),
        (abWheelRolloutsId,                        "Ab Wheel Rollouts",                              .bodyweightPlusSingleLoad, .core, "AbWheelRolloutsIcon"),
        (pallofPressId,                            "Pallof Press",                                   .singleLoad, .core,  "PallofPressIcon"),
        (cableWoodchopsId,                         "Cable Woodchops",                                .singleLoad, .core,  "CableWoodchopsIcon"),
        (powerCleansId,                            "Power Cleans",                                   .barbell,    .hinge, "PowerCleansIcon"),
        (farmersCarriesId,                         "Farmer's Carries",                               .singleLoad, .other, "FarmersCarriesIcon"),
        (cableLateralRaisesId,                     "Cable Lateral Raises",                           .singleLoad, .push,  "CableLateralRaisesIcon"),
        (landminePressId,                          "Landmine Press",                                 .barbell,    .push,  "LandminePressIcon"),
    ]
}
