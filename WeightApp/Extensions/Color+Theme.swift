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

    // MARK: - Set Intensity Colors

    /// Easy set (RIR 5+ or <6 reps for bodyweight)
    static let setEasy = Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255) // #22C55E

    /// Moderate set (RIR 3–4 or 6-8 reps for bodyweight)
    static let setModerate = Color(red: 0x21/255, green: 0xB7/255, blue: 0xC9/255) // #21B7C9

    /// Hard set (RIR 1–2 or 9-11 reps for bodyweight)
    static let setHard = Color(red: 0x5B/255, green: 0x3B/255, blue: 0xE8/255) // #5B3BE8

    /// Near max / redline set (RIR ≤0 or 12+ reps for bodyweight)
    static let setNearMax = Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255) // #EF4444

    /// Personal record set
    static let setPR = Color(red: 0xFF/255, green: 0xB0/255, blue: 0x00/255) // #FFB000
}
