//
//  Color+Theme.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/25/26.
//

import SwiftUI

extension Color {
    // MARK: - App Theme Colors

    /// Primary accent color used throughout the app for interactive elements, buttons, and highlights
    /// Change this single value to test different color schemes
    /// Current: #adc178 (sage green)
    static let appAccent = Color(red: 173/255, green: 193/255, blue: 120/255)

    // MARK: - Semantic Color Aliases

    /// Used for primary buttons and interactive elements
    static let appPrimary = appAccent

    /// Used for text labels and headers that should match the accent color
    static let appLabel = appAccent.opacity(0.7)
}
