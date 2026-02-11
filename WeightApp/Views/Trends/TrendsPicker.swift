//
//  TrendsPicker.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI

enum TrendsTab: Int, CaseIterable {
    case analytics = 0
    case history = 1

    var title: String {
        switch self {
        case .analytics: return "Analytics"
        case .history: return "History"
        }
    }
}

struct TrendsPicker: View {
    @Binding var selectedTab: TrendsTab
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack(alignment: .center) {
            // Background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.14))
                .frame(height: 40)

            // Sliding indicator
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appAccent)
                    .frame(width: geometry.size.width / 2 - 6, height: 32)
                    .offset(x: selectedTab == .analytics ? 4 : geometry.size.width / 2 + 2, y: 4)
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
