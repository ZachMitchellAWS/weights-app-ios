//
//  AppSettings.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import Foundation
import SwiftData

@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID

    var twoSidedIncrement: Double
    var oneSidedIncrement: Double

    // Persist as JSON string (SwiftData-friendly)
    var availableIncrementsJSON: String

    init(twoSidedIncrement: Double = 5.0, oneSidedIncrement: Double = 2.5, availableIncrements: [Double] = [2.5, 5.0]) {
        self.id = UUID()
        self.twoSidedIncrement = twoSidedIncrement
        self.oneSidedIncrement = oneSidedIncrement
        self.availableIncrementsJSON = Self.encode(availableIncrements)
    }

    var availableIncrements: [Double] {
        get { Self.decode(availableIncrementsJSON) }
        set { availableIncrementsJSON = Self.encode(newValue) }
    }

    // For backwards compatibility with old code
    var weightIncrement: Double {
        get { twoSidedIncrement }
        set { twoSidedIncrement = newValue }
    }

    private static func encode(_ values: [Double]) -> String {
        let data = (try? JSONEncoder().encode(values)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decode(_ json: String) -> [Double] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([Double].self, from: data) else { return [] }
        return arr
    }

    static let predefinedIncrements: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 2.5, 5.0]
}
