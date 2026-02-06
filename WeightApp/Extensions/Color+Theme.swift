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

    //static let appAccent = Color(red: 173/255, green: 193/255, blue: 120/255) // #adc178 Sage Green
    //static let appAccent = Color(red: 76/255, green: 201/255, blue: 240/255) // #4CC9F0 Neon Cyan
    // static let appAccent = Color(red: 33/255, green: 183/255, blue: 201/255) // #21B7C9

    /// Vivid amber for logo/branding
    static let appLogoColor = Color(red: 255/255, green: 176/255, blue: 0/255) // Vivid Amber (#FFB000)

    /// Lighter amber for UI elements
    static let appAccent = Color(red: 255/255, green: 200/255, blue: 80/255) // Light Amber (#FFC850)


    // MARK: - Semantic Color Aliases

    /// Used for primary buttons and interactive elements
    static let appPrimary = appAccent

    /// Used for text labels and headers that should match the accent color
    static let appLabel = appAccent.opacity(0.7)
}
