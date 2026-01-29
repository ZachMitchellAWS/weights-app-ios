//
//  UserProperties.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/27/26.
//

import Foundation
import SwiftData

@Model
final class UserProperties {
    // Static singleton ID to ensure only one instance exists
    static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Attribute(.unique) var id: UUID
    var bodyweight: Double?
    var plateWeights: [Double] = []

    init() {
        self.id = UserProperties.singletonID
        self.bodyweight = nil
        self.plateWeights = []
    }

    static let defaultPlateWeights: [Double] = [2.5]
}
