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
    var userBodyweight: Double?

    init() {
        self.id = UUID()
        self.userBodyweight = nil
    }
}
