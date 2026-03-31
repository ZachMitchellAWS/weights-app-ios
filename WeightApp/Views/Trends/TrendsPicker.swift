//
//  TrendsPicker.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI

enum TrendsTab: Int, CaseIterable {
    case narratives = 0
    case strength = 1
    case analytics = 2

    var title: String {
        switch self {
        case .narratives: return "Insights"
        case .strength: return "Strength"
        case .analytics: return "Analytics"
        }
    }
}

struct TrendsPicker: View {
    @Binding var selectedTab: TrendsTab
    var showNarrativesBadge: Bool = false
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack(alignment: .center) {
            // Background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.14))
                .frame(height: 40)

            // Sliding indicator
            GeometryReader { geometry in
                let tabCount = CGFloat(TrendsTab.allCases.count)
                let segmentWidth = geometry.size.width / tabCount
                let indicatorWidth = segmentWidth - 6

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appAccent)
                    .frame(width: indicatorWidth, height: 32)
                    .offset(
                        x: CGFloat(selectedTab.rawValue) * segmentWidth + 3,
                        y: 4
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
            }
            .frame(height: 40)

            // Tab buttons
            HStack(spacing: 0) {
                ForEach(TrendsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                        hapticFeedback.impactOccurred()
                    } label: {
                        Text(tab.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedTab == tab ? .black : .white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .overlay(alignment: .topLeading) {
                                if tab == .narratives && showNarrativesBadge && selectedTab != .narratives {
                                    PulsingBadge(color: .red, size: 8)
                                        .offset(x: 8, y: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(height: 40)
                }
            }
        }
        .frame(height: 40)
        .padding(.horizontal, 16)
    }
}

// MARK: - Pulsing Badge

struct PulsingBadge: View {
    var color: Color = .red
    var size: CGFloat = 10

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.4))
                .frame(width: size * 2, height: size * 2)
                .scaleEffect(isPulsing ? 1 : 0.5)
                .opacity(isPulsing ? 0 : 0.6)

            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}
