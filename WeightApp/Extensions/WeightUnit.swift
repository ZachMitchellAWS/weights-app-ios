import Foundation

enum WeightUnit: String, Codable, CaseIterable {
    case lbs, kg

    var label: String { rawValue }

    /// Convert a value stored in lbs to this unit
    func fromLbs(_ lbs: Double) -> Double {
        switch self {
        case .lbs: return lbs
        case .kg: return lbs * 0.45359237
        }
    }

    /// Convert a value in this unit back to lbs for storage
    func toLbs(_ value: Double) -> Double {
        switch self {
        case .lbs: return value
        case .kg: return value / 0.45359237
        }
    }

    /// Format a weight value stored in lbs for display in this unit.
    /// Shows integer if whole, otherwise 1 decimal place.
    func formatWeight(_ lbsValue: Double) -> String {
        let converted = fromLbs(lbsValue)
        if converted.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(converted))"
        } else {
            return converted.formatted(.number.precision(.fractionLength(1)))
        }
    }

    /// Format with 2 decimal places (for deltas, precise displays)
    func formatWeight2dp(_ lbsValue: Double) -> String {
        let converted = fromLbs(lbsValue)
        return converted.formatted(.number.precision(.fractionLength(2)))
    }

    /// Bodyweight picker range appropriate for this unit
    var bodyweightPickerRange: ClosedRange<Double> {
        switch self {
        case .lbs: return 50...500
        case .kg: return 23...227
        }
    }

    /// Bodyweight picker stride
    var bodyweightPickerStride: Double { 1.0 }
}
