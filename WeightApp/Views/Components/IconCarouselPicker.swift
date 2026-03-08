//
//  IconCarouselPicker.swift
//  WeightApp
//
//  Created by Claude on 2/9/26.
//

import SwiftUI

/// Snaps aggressively: any scroll commits to moving, hard swipes skip multiple items.
private struct AggressiveSnapBehavior: ScrollTargetBehavior {
    let itemWidth: CGFloat
    let itemSpacing: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let step = itemWidth + itemSpacing
        let currentIndex = round(context.originalTarget.rect.origin.x / step)
        let proposedIndex = target.rect.origin.x / step
        let delta = proposedIndex - currentIndex

        // Round to nearest snap point, but ensure at least 1 step in scroll direction
        let snappedIndex: CGFloat
        if delta > 0.01 {
            snappedIndex = max(currentIndex + 1, round(proposedIndex))
        } else if delta < -0.01 {
            snappedIndex = min(currentIndex - 1, round(proposedIndex))
        } else {
            snappedIndex = currentIndex
        }

        target.rect.origin.x = snappedIndex * step
    }
}

struct IconCarouselPicker: View {
    @Binding var selectedIcon: String

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    private let iconSize: CGFloat = 160
    private let iconSpacing: CGFloat = 20

    @State private var scrolledIcon: String?
    @State private var hasAppeared = false

    static let availableIcons: [String] = [
        "LiftTheBullIcon",
        "DeadliftIcon",
        "SquatIcon",
        "DipsIcon",
        "OverheadPressIcon",
        "BenchPressIcon",
        "BarbellRowIcon",
        "PullUpIcon",
        "CurlsIcon",
        // Arms – Biceps / Forearms
        "DumbbellCurlsIcon",
        "ConcentrationCurlsIcon",
        "InclineDumbbellCurlsIcon",
        "HammerCurlsIcon",
        "LowPulleyCurlsIcon",
        "HighPulleyCurlsIcon",
        "MachineCurlsIcon",
        "PreacherCurlsIcon",
        "StandingReverseCurlsIcon",
        "SeatedReverseCurlsIcon",
        "WristCurlsIcon",
        "FingerCurlsIcon",
        "ReverseBarbellCurlsIcon",
        // Arms – Triceps
        "TricepPushdownsIcon",
        "ReverseTricepPushdownsIcon",
        "StandingCableOverheadTricepExtensionsIcon",
        "LyingBarbellTricepExtensionsIcon",
        "LyingDumbbellTricepExtensionsIcon",
        "OneArmOverheadDumbbellTricepExtensionsIcon",
        "TricepKickbacksIcon",
        "SeatedDumbbellTricepExtensionsIcon",
        "SeatedEZBarTricepExtensionsIcon"
    ]

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding = (geometry.size.width - iconSize) / 2

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: iconSpacing) {
                        ForEach(Self.availableIcons, id: \.self) { icon in
                            iconTile(for: icon)
                                .id(icon)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, horizontalPadding)
                }
                .scrollTargetBehavior(AggressiveSnapBehavior(itemWidth: iconSize, itemSpacing: iconSpacing))
                .scrollPosition(id: $scrolledIcon, anchor: .center)
                .onAppear {
                    if !hasAppeared {
                        hasAppeared = true
                        // Set scroll position immediately and with delays to ensure centering
                        scrolledIcon = selectedIcon
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(selectedIcon, anchor: .center)
                            scrolledIcon = selectedIcon
                        }
                    }
                }
                .onChange(of: scrolledIcon) { _, newValue in
                    if let newValue, newValue != selectedIcon {
                        hapticFeedback.impactOccurred()
                        selectedIcon = newValue
                    }
                }
                .onChange(of: selectedIcon) { _, newValue in
                    if scrolledIcon != newValue {
                        withAnimation {
                            scrolledIcon = newValue
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(height: iconSize + 24)
    }

    @ViewBuilder
    private func iconTile(for icon: String) -> some View {
        let isSelected = selectedIcon == icon

        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
                .frame(width: iconSize, height: iconSize)

            if isSelected {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.appAccent, lineWidth: 3)
                    .frame(width: iconSize, height: iconSize)
            }

            iconView(for: icon, size: iconSize * 0.65, isSelected: isSelected)
        }
        .frame(width: iconSize, height: iconSize)
        .onTapGesture {
            hapticFeedback.impactOccurred()
            selectedIcon = icon
        }
    }

    @ViewBuilder
    private func iconView(for icon: String, size: CGFloat, isSelected: Bool) -> some View {
        let color: Color = isSelected ? .appAccent : .white

        if icon == "OverheadPressIcon" {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .scaleEffect(1.2)
                .foregroundStyle(color)
        } else {
            // Other custom assets (BenchPressIcon, PullUpIcon)
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(color)
        }
    }

    /// Suggests an icon based on exercise name keywords.
    /// Specific name matches come first; generic keyword matches are last.
    static func suggestedIcon(for name: String) -> String {
        let lowered = name.lowercased()

        // Exact / specific name matches (arms)
        if lowered == "dumbbell curls" { return "DumbbellCurlsIcon" }
        if lowered == "concentration curls" { return "ConcentrationCurlsIcon" }
        if lowered == "incline dumbbell curls" { return "InclineDumbbellCurlsIcon" }
        if lowered == "hammer curls" { return "HammerCurlsIcon" }
        if lowered == "low pulley curls" { return "LowPulleyCurlsIcon" }
        if lowered == "high pulley curls" { return "HighPulleyCurlsIcon" }
        if lowered == "machine curls" { return "MachineCurlsIcon" }
        if lowered == "preacher curls" { return "PreacherCurlsIcon" }
        if lowered == "standing reverse curls" { return "StandingReverseCurlsIcon" }
        if lowered == "seated reverse curls" { return "SeatedReverseCurlsIcon" }
        if lowered == "wrist curls" { return "WristCurlsIcon" }
        if lowered == "finger curls" { return "FingerCurlsIcon" }
        if lowered == "reverse barbell curls" { return "ReverseBarbellCurlsIcon" }
        if lowered == "tricep pushdowns" { return "TricepPushdownsIcon" }
        if lowered == "reverse tricep pushdowns" { return "ReverseTricepPushdownsIcon" }
        if lowered == "standing cable overhead tricep extensions" { return "StandingCableOverheadTricepExtensionsIcon" }
        if lowered == "lying barbell tricep extensions" { return "LyingBarbellTricepExtensionsIcon" }
        if lowered == "lying dumbbell tricep extensions" { return "LyingDumbbellTricepExtensionsIcon" }
        if lowered == "one-arm overhead dumbbell tricep extensions" { return "OneArmOverheadDumbbellTricepExtensionsIcon" }
        if lowered == "tricep kickbacks" { return "TricepKickbacksIcon" }
        if lowered == "seated dumbbell tricep extensions" { return "SeatedDumbbellTricepExtensionsIcon" }
        if lowered == "seated ez-bar tricep extensions" { return "SeatedEZBarTricepExtensionsIcon" }

        // Generic keyword matches (original exercises)
        if lowered.contains("overhead") && lowered.contains("press") {
            return "OverheadPressIcon"
        } else if lowered.contains("bench") {
            return "BenchPressIcon"
        } else if lowered.contains("row") {
            return "BarbellRowIcon"
        } else if lowered.contains("pull") && lowered.contains("up") {
            return "PullUpIcon"
        } else if lowered.contains("deadlift") {
            return "DeadliftIcon"
        } else if lowered.contains("squat") {
            return "SquatIcon"
        } else if lowered.contains("dip") {
            return "DipsIcon"
        } else if lowered.contains("curl") {
            return "CurlsIcon"
        }

        return "LiftTheBullIcon"
    }
}
