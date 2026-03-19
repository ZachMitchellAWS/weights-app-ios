import SwiftUI

enum EffortMode: Int, CaseIterable {
    case easy = 0, moderate = 1, hard = 2, progress = 3

    var title: String {
        switch self {
        case .easy: return "Easy Options"
        case .moderate: return "Moderate Options"
        case .hard: return "Hard Options"
        case .progress: return "Progress Options"
        }
    }

    var chipLabel: String {
        switch self {
        case .easy: return "Easy Options"
        case .moderate: return "Moderate Options"
        case .hard: return "Hard Options"
        case .progress: return "e1RM Progress Options"
        }
    }

    var subtitle: String {
        switch self {
        case .easy: return "< 70% e1RM"
        case .moderate: return "70-82% e1RM"
        case .hard: return "82-92% e1RM"
        case .progress: return "Sets to ↑ e1RM"
        }
    }

    var targetPercent1RMs: [Double]? {
        switch self {
        case .easy: return [0.55, 0.60, 0.65]
        case .moderate: return [0.73, 0.76, 0.79]
        case .hard: return [0.84, 0.87, 0.90]
        case .progress: return nil
        }
    }

    func repRange(from props: UserProperties) -> ClosedRange<Int> {
        switch self {
        case .easy: return props.easyMinReps...props.easyMaxReps
        case .moderate: return props.moderateMinReps...props.moderateMaxReps
        case .hard: return props.hardMinReps...props.hardMaxReps
        case .progress: return props.minReps...props.maxReps
        }
    }

    /// The valid %1RM range for this effort category (values are percentages, e.g. 70 = 70%).
    /// Suggestions whose recalculated %1RM falls outside this range are filtered out.
    var percent1RMBounds: ClosedRange<Double>? {
        switch self {
        case .easy: return 0...70
        case .moderate: return 70...82
        case .hard: return 82...92
        case .progress: return nil
        }
    }

    var calibrationMidpoint: Double? {
        switch self {
        case .easy: return 0.60
        case .moderate: return 0.76
        case .hard: return 0.87
        case .progress: return 0.96
        }
    }

    var tileColor: Color {
        switch self {
        case .easy: return .setEasy
        case .moderate: return .setModerate
        case .hard: return .setHard
        case .progress: return .setPR
        }
    }

    var defaultMinReps: Int {
        switch self {
        case .easy: return UserProperties.defaultEasyMinReps
        case .moderate: return UserProperties.defaultModerateMinReps
        case .hard: return UserProperties.defaultHardMinReps
        case .progress: return UserProperties.defaultMinReps
        }
    }

    var defaultMaxReps: Int {
        switch self {
        case .easy: return UserProperties.defaultEasyMaxReps
        case .moderate: return UserProperties.defaultModerateMaxReps
        case .hard: return UserProperties.defaultHardMaxReps
        case .progress: return UserProperties.defaultMaxReps
        }
    }

    var effortKey: String {
        switch self {
        case .easy: return "easy"
        case .moderate: return "moderate"
        case .hard: return "hard"
        case .progress: return "pr"
        }
    }

    static func from(effort: String) -> EffortMode {
        switch effort {
        case "easy": return .easy
        case "moderate": return .moderate
        case "hard": return .hard
        case "pr": return .progress
        default: return .easy
        }
    }
}
