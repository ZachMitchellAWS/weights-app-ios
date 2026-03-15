//
//  Color+Theme.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/25/26.
//

import SwiftUI
import UIKit

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

    /// Cycling palette for split day chips
    static let dayChipColors: [Color] = [.setEasy, .setModerate, .setHard, .setNearMax, .setPR]

    // MARK: - Balance Spectrum Colors

    /// Warm coral — needs attention (score < 0.85)
    static let balanceWeak = Color(red: 0xEF/255, green: 0x6B/255, blue: 0x4A/255) // #EF6B4A

    /// Warm amber — slightly weak (score 0.85–0.92)
    static let balanceMild = Color(red: 0xF5/255, green: 0xA6/255, blue: 0x23/255) // #F5A623

    /// Green — balanced (score 0.92–1.08)
    static let balanceGood = Color.setEasy // #22C55E

    /// Cool teal — slightly strong (score 1.08–1.15)
    static let balanceCoolMild = Color.setModerate // #21B7C9

    /// Cool blue — relative strength (score > 1.15)
    static let balanceStrong = Color(red: 0x4A/255, green: 0x90/255, blue: 0xD9/255) // #4A90D9

    // MARK: - Balance Trend Colors

    /// Declining — delta ≤ -0.05
    static let trendDeclining = Color(red: 0xE5/255, green: 0x3E/255, blue: 0x3E/255) // #E53E3E

    /// Dipping — delta -0.05 to -0.02
    static let trendDipping = Color(red: 0xED/255, green: 0x89/255, blue: 0x36/255) // #ED8936

    /// Stable — delta -0.02 to +0.02
    static let trendStable = Color(red: 0xA0/255, green: 0xAE/255, blue: 0xC0/255) // #A0AEC0

    /// Rising — delta +0.02 to +0.05
    static let trendRising = Color(red: 0x68/255, green: 0xD3/255, blue: 0x91/255) // #68D391

    /// Surging — delta ≥ +0.05
    static let trendSurging = Color(red: 0x38/255, green: 0xA1/255, blue: 0x69/255) // #38A169

    /// Interpolate balance score to a color on the warm-to-cool spectrum
    static func balanceColor(for score: Double) -> Color {
        switch score {
        case ..<0.85:
            let t = max(0, (score - 0.70) / 0.15)
            return interpolate(from: .balanceWeak, to: .balanceMild, t: t)
        case 0.85..<0.92:
            let t = (score - 0.85) / 0.07
            return interpolate(from: .balanceMild, to: .balanceGood, t: t)
        case 0.92..<1.08:
            return .balanceGood
        case 1.08..<1.15:
            let t = (score - 1.08) / 0.07
            return interpolate(from: .balanceCoolMild, to: .balanceStrong, t: t)
        default:
            let t = min(1, (score - 1.15) / 0.15)
            return interpolate(from: .balanceStrong, to: .balanceStrong, t: t)
        }
    }

    private static func interpolate(from c1: Color, to c2: Color, t: Double) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(c1).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(c2).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let clampedT = max(0, min(1, t))
        return Color(
            red: r1 + (r2 - r1) * clampedT,
            green: g1 + (g2 - g1) * clampedT,
            blue: b1 + (b2 - b1) * clampedT
        )
    }
}
