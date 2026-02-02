//
//  OnboardingView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/29/26.
//

import SwiftUI
import Charts

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage = 0
    @State private var buttonEnabled = false
    @State private var isExiting = false

    private let totalPages = 3

    var body: some View {
        ZStack {
            // Background matching widget style
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                // Page content with transition
                Group {
                    switch currentPage {
                    case 0:
                        OnboardingPageOne()
                    case 1:
                        OnboardingPageTwo()
                    case 2:
                        OnboardingPageThree()
                    default:
                        EmptyView()
                    }
                }
                .id(currentPage)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.appAccent : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 24)

                // Continue button
                Button {
                    if currentPage < totalPages - 1 {
                        buttonEnabled = false
                        withAnimation(.easeInOut(duration: 0.4)) {
                            currentPage += 1
                        }
                        // Enable button again after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                buttonEnabled = true
                            }
                        }
                    } else {
                        // Smooth exit transition
                        withAnimation(.easeOut(duration: 0.3)) {
                            isExiting = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onComplete()
                        }
                    }
                } label: {
                    Text(currentPage < totalPages - 1 ? "Continue" : "Get Started")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black.opacity(buttonEnabled ? 1 : 0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(buttonEnabled ? Color.appAccent : Color.gray)
                        .cornerRadius(12)
                        .animation(.easeInOut(duration: 0.3), value: buttonEnabled)
                }
                .buttonStyle(.plain)
                .disabled(!buttonEnabled || isExiting)
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
            .opacity(isExiting ? 0 : 1)
            .scaleEffect(isExiting ? 0.95 : 1)
        }
        .onAppear {
            // Enable button after 1.5 second delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    buttonEnabled = true
                }
            }
        }
    }
}

// MARK: - Page One: Track Your Lifts (Set Intensity with Rounded Squares)

private struct OnboardingPageOne: View {
    @State private var scrollOffset: CGFloat = 0

    private let green = Color(red: 0x84/255, green: 0xCC/255, blue: 0x16/255)
    private let yellow = Color(red: 0xEA/255, green: 0xB3/255, blue: 0x08/255)
    private let orange = Color(red: 0xF9/255, green: 0x73/255, blue: 0x16/255)
    private let red = Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255)
    private let cyan = Color(red: 0x06/255, green: 0xB6/255, blue: 0xD4/255)

    // Sample sets for "Today" row - many more sets
    private var todaySets: [(reps: String, weight: String, color: Color)] {
        [
            ("10", "135", green),
            ("8", "155", green),
            ("8", "175", yellow),
            ("6", "195", yellow),
            ("6", "205", orange),
            ("5", "215", orange),
            ("4", "225", red),
            ("3", "235", red),
            ("2", "245", cyan),
            ("6", "205", orange),
            ("8", "185", yellow),
            ("10", "165", green),
            ("8", "175", yellow),
            ("6", "195", orange),
            ("5", "210", red),
            ("3", "230", cyan),
        ]
    }

    // Sample sets for "Previous Day" row - many more sets
    private var previousSets: [(reps: String, weight: String, color: Color)] {
        [
            ("12", "115", green),
            ("10", "135", green),
            ("8", "155", yellow),
            ("8", "165", yellow),
            ("6", "185", orange),
            ("6", "195", orange),
            ("5", "205", red),
            ("4", "215", red),
            ("3", "225", cyan),
            ("6", "195", orange),
            ("8", "175", yellow),
            ("10", "155", green),
            ("8", "165", yellow),
            ("6", "185", orange),
            ("4", "210", red),
            ("2", "225", cyan),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Text
            VStack(spacing: 12) {
                Text("Track Your Lifts")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Log sets and watch your progress grow")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 32)

            // Set Intensity visualization with rounded squares
            VStack(alignment: .leading, spacing: 16) {
                // Today's Sets
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    GeometryReader { _ in
                        HStack(spacing: 6) {
                            ForEach(0..<todaySets.count, id: \.self) { index in
                                let set = todaySets[index]
                                SetSquareOnboarding(reps: set.reps, weight: set.weight, color: set.color)
                            }
                        }
                        .offset(x: -scrollOffset)
                    }
                    .frame(height: 42)
                    .clipped()
                }

                // Previous Day Sets
                VStack(alignment: .leading, spacing: 8) {
                    Text("Previous Day")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    GeometryReader { _ in
                        HStack(spacing: 6) {
                            ForEach(0..<previousSets.count, id: \.self) { index in
                                let set = previousSets[index]
                                SetSquareOnboarding(reps: set.reps, weight: set.weight, color: set.color)
                            }
                        }
                        .offset(x: -scrollOffset * 0.7) // Slightly different speed
                    }
                    .frame(height: 42)
                    .clipped()
                }

                // Legend
                HStack(spacing: 10) {
                    LegendDot(color: green, label: "Easy")
                    LegendDot(color: yellow, label: "Moderate")
                    LegendDot(color: orange, label: "Hard")
                    LegendDot(color: red, label: "Redline")
                    LegendDot(color: cyan, label: "PR")
                }
                .padding(.top, 12)
            }
            .padding(20)
            .background(Color(white: 0.12))
            .cornerRadius(16)
            .padding(.horizontal, 24)
            .onAppear {
                startAutoScroll()
            }
        }
    }

    private func startAutoScroll() {
        withAnimation(.linear(duration: 40).repeatForever(autoreverses: true)) {
            scrollOffset = 450
        }
    }
}

private struct SetSquareOnboarding: View {
    let reps: String
    let weight: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(reps)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
            Text(weight)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(width: 42, height: 42)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.4), color.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(0.6), lineWidth: 1.5)
        )
    }
}

// MARK: - Page Two: Estimate Your 1RM (Estimated 1RM Chart with more variety)

private struct OnboardingPageTwo: View {
    @State private var scrollOffset: CGFloat = 0

    private let green = Color(red: 0x84/255, green: 0xCC/255, blue: 0x16/255)
    private let yellow = Color(red: 0xEA/255, green: 0xB3/255, blue: 0x08/255)
    private let orange = Color(red: 0xF9/255, green: 0x73/255, blue: 0x16/255)
    private let red = Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255)
    private let cyan = Color(red: 0x06/255, green: 0xB6/255, blue: 0xD4/255)

    // Sample 1RM data - cycles through intensity colors, each PR slightly higher than last
    private var sampleData: [(value: Double, color: Color)] {
        [
            // Cycle 1: work up to first PR at 170
            (155, green),
            (158, green),
            (162, yellow),
            (165, yellow),
            (167, orange),
            (169, red),
            (170, cyan),      // PR 1

            // Cycle 2: start lower, work up to PR at 175
            (160, green),
            (164, yellow),
            (168, orange),
            (171, orange),
            (173, red),
            (175, cyan),      // PR 2

            // Cycle 3: start lower, work up to PR at 182
            (165, green),
            (169, green),
            (173, yellow),
            (176, orange),
            (179, red),
            (182, cyan),      // PR 3

            // Cycle 4: start lower, work up to PR at 188
            (172, green),
            (176, yellow),
            (180, yellow),
            (183, orange),
            (186, red),
            (188, cyan),      // PR 4

            // Cycle 5: start lower, work up to PR at 195
            (178, green),
            (182, yellow),
            (186, orange),
            (189, orange),
            (192, red),
            (195, cyan),      // PR 5

            // Cycle 6: start lower, work up to PR at 202
            (184, green),
            (188, green),
            (192, yellow),
            (196, orange),
            (199, red),
            (202, cyan),      // PR 6

            // Cycle 7: start lower, work up to PR at 208
            (190, green),
            (194, yellow),
            (198, yellow),
            (202, orange),
            (205, red),
            (208, cyan),      // PR 7

            // Cycle 8: start lower, work up to PR at 215
            (196, green),
            (200, green),
            (204, yellow),
            (208, orange),
            (212, red),
            (215, cyan),      // PR 8

            // Cycle 9: start lower, work up to PR at 222
            (202, green),
            (206, yellow),
            (210, yellow),
            (214, orange),
            (218, red),
            (222, cyan),      // PR 9

            // Cycle 10: start lower, work up to PR at 228
            (208, green),
            (212, green),
            (216, yellow),
            (220, orange),
            (225, red),
            (228, cyan),      // PR 10

            // Cycle 11 partial: starting the next cycle
            (214, green),
        ]
    }

    private let barWidth: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            // Text
            VStack(spacing: 12) {
                Text("Estimate Your 1RM")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("See your estimated one-rep max for each exercise")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 32)

            // Chart visualization with horizontal scroll and fixed y-axis
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    // Fixed Y-axis labels
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("225")
                        Spacer()
                        Text("200")
                        Spacer()
                        Text("175")
                        Spacer()
                        Text("150")
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 28, height: 140)
                    .padding(.trailing, 4)

                    // Scrolling chart area
                    GeometryReader { _ in
                        Chart {
                            ForEach(0..<sampleData.count, id: \.self) { index in
                                let data = sampleData[index]
                                RectangleMark(
                                    xStart: .value("Start", Double(index)),
                                    xEnd: .value("End", Double(index) + 0.75),
                                    yStart: .value("Base", 140),
                                    yEnd: .value("Height", data.value)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [data.color, data.color.opacity(0.6)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .cornerRadius(2)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartXScale(domain: 0...Double(sampleData.count))
                        .chartYScale(domain: 140...230)
                        .frame(width: CGFloat(sampleData.count) * barWidth, height: 140)
                        .offset(x: -scrollOffset)
                    }
                    .frame(height: 140)
                    .clipped()
                }

                // Legend
                HStack(spacing: 10) {
                    LegendDot(color: green, label: "Easy")
                    LegendDot(color: yellow, label: "Moderate")
                    LegendDot(color: orange, label: "Hard")
                    LegendDot(color: red, label: "Redline")
                    LegendDot(color: cyan, label: "PR")
                }
                .padding(.top, 16)
            }
            .padding(20)
            .background(Color(white: 0.12))
            .cornerRadius(16)
            .padding(.horizontal, 24)
            .onAppear {
                startAutoScroll()
            }
        }
    }

    private func startAutoScroll() {
        let totalWidth = CGFloat(sampleData.count) * barWidth
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: true)) {
            scrollOffset = totalWidth - 280
        }
    }
}

// MARK: - Page Three: Get Stronger (Options Scroll View)

private struct OnboardingPageThree: View {
    @State private var scrollOffset: CGFloat = 0

    // Sample suggestions data - sorted by GAIN ascending
    private let sampleSuggestions: [(weight: String, reps: String, est1RM: String, gain: String)] = [
        ("210.00", "10", "273.33", "+1.08"),
        ("220.00", "7", "270.47", "+1.72"),
        ("212.50", "10", "276.58", "+2.33"),
        ("217.50", "8", "271.88", "+2.63"),
        ("225.00", "6", "267.57", "+2.82"),
        ("215.00", "10", "279.17", "+2.92"),
        ("227.50", "6", "270.54", "+3.29"),
        ("220.00", "9", "279.84", "+3.59"),
        ("222.50", "8", "278.13", "+3.88"),
        ("230.00", "6", "273.51", "+4.26"),
        ("217.50", "10", "283.42", "+4.67"),
        ("225.00", "8", "281.25", "+5.00"),
        ("235.00", "6", "279.46", "+6.21"),
        ("220.00", "10", "286.67", "+6.42"),
        ("227.50", "8", "284.38", "+6.63"),
        ("222.50", "9", "283.01", "+6.76"),
        ("230.00", "7", "282.56", "+7.31"),
        ("242.50", "5", "280.37", "+7.62"),
        ("232.50", "7", "285.73", "+7.98"),
        ("225.00", "9", "286.05", "+8.30"),
        ("235.00", "7", "288.84", "+8.59"),
        ("227.50", "9", "289.22", "+8.97"),
        ("237.50", "6", "282.39", "+9.14"),
        ("230.00", "8", "287.50", "+9.48"),
        ("240.00", "6", "285.36", "+10.11"),
        ("232.50", "8", "290.63", "+10.38"),
        ("247.50", "5", "286.31", "+11.06"),
        ("235.00", "8", "293.75", "+12.50"),
        ("237.50", "7", "292.09", "+12.84"),
        ("242.50", "6", "288.30", "+13.05"),
        ("240.00", "7", "295.35", "+14.10"),
        ("245.00", "6", "291.27", "+15.02"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Text
            VStack(spacing: 12) {
                Text("Get Stronger")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Follow suggestions to progressively overload")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Spacer()
                .frame(height: 32)

            // Options visualization
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 8) {
                    Text("WEIGHT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(white: 0.5))
                        .frame(maxWidth: .infinity)

                    Text("REPS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(white: 0.5))
                        .frame(maxWidth: .infinity)

                    Text("EST. 1RM")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(white: 0.5))
                        .frame(maxWidth: .infinity)

                    Text("GAIN")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.appAccent)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                // Auto-scrolling rows
                GeometryReader { geometry in
                    VStack(spacing: 8) {
                        ForEach(0..<sampleSuggestions.count, id: \.self) { index in
                            OnboardingSuggestionRow(suggestion: sampleSuggestions[index], isHighlighted: index == sampleSuggestions.count - 1)
                        }
                    }
                    .offset(y: -scrollOffset)
                }
                .frame(height: 180)
                .clipped()
            }
            .padding(20)
            .background(Color(white: 0.12))
            .cornerRadius(16)
            .padding(.horizontal, 24)
            .onAppear {
                startAutoScroll()
            }
        }
    }

    private func startAutoScroll() {
        // Very slow continuous scroll animation
        withAnimation(.linear(duration: 90).repeatForever(autoreverses: true)) {
            scrollOffset = 1100
        }
    }
}

private struct OnboardingSuggestionRow: View {
    let suggestion: (weight: String, reps: String, est1RM: String, gain: String)
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(suggestion.weight)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Text(suggestion.reps)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Text(suggestion.est1RM)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Text(suggestion.gain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isHighlighted ? Color.appAccent : Color.white.opacity(0.15), lineWidth: isHighlighted ? 2 : 1)
                )
        )
    }
}

// MARK: - Helper Views

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
