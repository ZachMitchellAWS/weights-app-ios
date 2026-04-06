//
//  EntitlementGrant.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/4/26.
//

import Foundation
import SwiftData

@Model
final class EntitlementGrant {
    var entitlementName: String
    var startUtc: Date
    var endUtc: Date

    var isActive: Bool {
        let now = Date()
        return startUtc <= now && endUtc > now
    }

    static func isPremium(_ grants: [EntitlementGrant]) -> Bool {
        return grants.contains { $0.entitlementName.hasPrefix("com.weightapp.premium") && $0.isActive }
    }

    init(entitlementName: String, startUtc: Date, endUtc: Date) {
        self.entitlementName = entitlementName
        self.startUtc = startUtc
        self.endUtc = endUtc
    }
}
