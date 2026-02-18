//
//  Entitlements.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/4/26.
//

import Foundation
import SwiftData

@Model
final class Entitlements {
    // Static singleton ID to ensure only one instance exists
    static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Attribute(.unique) var id: UUID
    var isPremium: Bool
    var subscriptionType: String?  // "monthly" or "yearly"
    var expiresAt: Date?
    var transactionId: String?

    /// Computed property for active status
    /// Premium is active if isPremium is true AND either no expiry is set or expiry is in the future
    var isActive: Bool {
        guard isPremium else { return false }
        guard let expiresAt = expiresAt else { return true }  // No expiry means manually enabled (dev toggle)
        return expiresAt > Date()
    }

    init() {
        self.id = Entitlements.singletonID
        self.isPremium = false
        self.subscriptionType = nil
        self.expiresAt = nil
        self.transactionId = nil
    }
}
