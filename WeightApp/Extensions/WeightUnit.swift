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

    /// Format with up to 2 decimal places, stripping trailing zeros.
    /// 210 → "210", 210.5 → "210.5", 210.53 → "210.53"
    func formatWeightTrimmed(_ lbsValue: Double) -> String {
        let converted = fromLbs(lbsValue)
        return converted.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Convert an lbs value to this unit and round to the nearest whole number.
    /// Use for tier-threshold-derived displays — tier range bounds, milestone
    /// targets, distance-to-next-tier — where the value should be a whole
    /// number and must match across every surface that references the same
    /// threshold. (Unlike `Int(fromLbs(x))`, this rounds rather than truncates,
    /// so 263.7 → "264" instead of "263".)
    func formatWeightRounded(_ lbsValue: Double) -> String {
        let converted = fromLbs(lbsValue)
        return "\(Int(converted.rounded()))"
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

    /// Smallest practical plate-pair step for the log-set +/- buttons.
    /// 2.5 lbs (a pair of 1.25 lb plates) / 1.25 kg.
    var stepSize: Double {
        switch self {
        case .lbs: return 2.5
        case .kg: return 1.25
        }
    }

    /// Snap a value (already in this unit) UP to the next `stepSize` multiple.
    /// If the value is already on a multiple, advances by one full step.
    /// Off-multiple values (e.g. 47.3 lbs) snap to the nearest multiple above
    /// (50 lbs) rather than naively adding the step.
    func snappedUp(_ value: Double) -> Double {
        let step = stepSize
        // Floor-with-epsilon absorbs floating-point error from lb↔kg conversion.
        let units = (value / step + 1e-4).rounded(.down)
        return (units + 1) * step
    }

    /// Snap a value DOWN to the next `stepSize` multiple at or below.
    /// Mirror of `snappedUp` — on-multiple values retreat by one step, off-
    /// multiple values snap to the nearest multiple below. Clamped at 0.
    func snappedDown(_ value: Double) -> Double {
        let step = stepSize
        let units = (value / step - 1e-4).rounded(.up)
        return max(0, (units - 1) * step)
    }
}
