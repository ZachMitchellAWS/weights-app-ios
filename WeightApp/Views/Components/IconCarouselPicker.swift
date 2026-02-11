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
        "figure.stand",
        "OverheadPressIcon",
        "BenchPressIcon",
        "BarbellRowIcon",
        "PullUpIcon"
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

        if icon == "figure.stand" {
            Image(systemName: icon)
                .font(.system(size: size * 0.9))
                .foregroundStyle(color)
        } else if icon == "OverheadPressIcon" {
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

    /// Suggests an icon based on exercise name keywords
    static func suggestedIcon(for name: String) -> String {
        let lowered = name.lowercased()

        if lowered.contains("overhead") && lowered.contains("press") {
            return "OverheadPressIcon"
        } else if lowered.contains("bench") {
            return "BenchPressIcon"
        } else if lowered.contains("row") {
            return "BarbellRowIcon"
        } else if lowered.contains("pull") && lowered.contains("up") {
            return "PullUpIcon"
        }

        return "figure.stand"
    }
}
