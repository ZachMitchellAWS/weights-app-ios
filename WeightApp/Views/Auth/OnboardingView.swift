//
//  OnboardingView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/29/26.
//

import SwiftUI
import SwiftData
import Charts

struct OnboardingView: View {
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            // Background matching widget style
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            OnboardingChangePlatesStep(onComplete: onComplete)
        }
    }
}

// MARK: - Change Plates Onboarding Step

private struct OnboardingChangePlatesStep: View {
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var userPropertiesItems: [UserProperties]

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    private let allPlateOptions: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 2.0]

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var plateWeights: [Double] {
        userProperties.availableChangePlates.filter { $0 < 5 }.sorted()
    }

    private var hasSelection: Bool {
        !plateWeights.isEmpty
    }

    private func isPlateActive(_ plate: Double) -> Bool {
        return plateWeights.contains { abs($0 - plate) < 0.01 }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 60)

            // Title
            VStack(spacing: 12) {
                Text("Available Change Plates")
                    .font(.bebasNeue(size: 32))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Select any smaller plates you have access to")
                    .font(.inter(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 24)

            // Barbell plate icon
            BarbellPlateIcon(size: 48)
                .foregroundStyle(Color.appAccent.opacity(0.8))

            Spacer()
                .frame(height: 24)

            // Content card — 2 rows of 3
            VStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { col in
                            let index = row * 3 + col
                            let plate = allPlateOptions[index]
                            ChangePlateBubble(
                                plate: plate,
                                isActive: isPlateActive(plate),
                                onToggle: {
                                    hapticFeedback.impactOccurred()
                                    togglePlate(plate)
                                }
                            )
                            .fixedSize()
                        }
                    }
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .background(Color(white: 0.12))
            .cornerRadius(16)
            .padding(.horizontal, 24)

            Spacer()

            // Bottom button
            Button {
                onComplete()
            } label: {
                Text("Continue")
                    .font(.interSemiBold(size: 16))
                    .foregroundStyle(hasSelection ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(hasSelection ? Color.appAccent : Color(white: 0.3))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
    }

    private func togglePlate(_ plate: Double) {
        if isPlateActive(plate) {
            userProperties.availableChangePlates.removeAll { abs($0 - plate) < 0.01 }
        } else {
            userProperties.availableChangePlates.append(plate)
        }
        try? modelContext.save()

        Task {
            await SyncService.shared.updateChangePlates(userProperties.availableChangePlates)
        }
    }
}

// MARK: - Original Onboarding Pages (preserved for future use)

/*
// Old multi-page coordinator logic:
//
// @Query(filter: #Predicate<Exercises> { !$0.deleted }, sort: \Exercises.createdAt) private var exercises: [Exercises]
// @State private var currentPage = 0
// @State private var isExiting = false
// @State private var selectedExerciseId: UUID? = nil
// private let totalPages = 4
//
// Page content switch:
//   case 0: OnboardingPageOne()
//   case 1: OnboardingPageTwo()
//   case 2: OnboardingPageThree()
//   case 3: OnboardingExerciseSelection(...)
//
// Page indicators and continue button logic was here.
*/

// MARK: - Page One: Track Your Lifts (Set Intensity with Rounded Squares)

private struct OnboardingPageOne: View {
    @State private var scrollOffset: CGFloat = 0

    // Sample sets for "Today" row - many more sets
    private var todaySets: [(reps: String, weight: String, color: Color)] {
        [
            ("10", "135", .setEasy),
            ("8", "155", .setEasy),
            ("8", "175", .setModerate),
            ("6", "195", .setModerate),
            ("6", "205", .setHard),
            ("5", "215", .setHard),
            ("4", "225", .setNearMax),
            ("3", "235", .setNearMax),
            ("2", "245", .setPR),
            ("6", "205", .setHard),
            ("8", "185", .setModerate),
            ("10", "165", .setEasy),
            ("8", "175", .setModerate),
            ("6", "195", .setHard),
            ("5", "210", .setNearMax),
            ("3", "230", .setPR),
        ]
    }

    // Sample sets for "Previous Day" row - many more sets
    private var previousSets: [(reps: String, weight: String, color: Color)] {
        [
            ("12", "115", .setEasy),
            ("10", "135", .setEasy),
            ("8", "155", .setModerate),
            ("8", "165", .setModerate),
            ("6", "185", .setHard),
            ("6", "195", .setHard),
            ("5", "205", .setNearMax),
            ("4", "215", .setNearMax),
            ("3", "225", .setPR),
            ("6", "195", .setHard),
            ("8", "175", .setModerate),
            ("10", "155", .setEasy),
            ("8", "165", .setModerate),
            ("6", "185", .setHard),
            ("4", "210", .setNearMax),
            ("2", "225", .setPR),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Text
            VStack(spacing: 12) {
                Text("Track Your Lifts")
                    .font(.bebasNeue(size: 32))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Log sets and watch your progress grow")
                    .font(.inter(size: 16))
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
                        .font(.interSemiBold(size: 12))
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
                        .font(.interSemiBold(size: 12))
                        .foregroundStyle(.white.opacity(0.7))

                    GeometryReader { _ in
                        HStack(spacing: 6) {
                            ForEach(0..<previousSets.count, id: \.self) { index in
                                let set = previousSets[index]
                                SetSquareOnboarding(reps: set.reps, weight: set.weight, color: set.color)
                            }
                        }
                        .offset(x: -scrollOffset) // Same speed as top row
                    }
                    .frame(height: 42)
                    .clipped()
                }

                // Legend
                HStack(spacing: 10) {
                    LegendDot(color: .setEasy, label: "Easy")
                    LegendDot(color: .setModerate, label: "Moderate")
                    LegendDot(color: .setHard, label: "Hard")
                    LegendDot(color: .setNearMax, label: "Redline")
                    LegendDot(color: .setPR, label: "PR")
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
                .font(.interSemiBold(size: 12))
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

    // Sample 1RM data - cycles through intensity colors, each PR slightly higher than last
    private var sampleData: [(value: Double, color: Color)] {
        [
            // Cycle 1: work up to first PR at 170
            (155, .setEasy),
            (158, .setEasy),
            (162, .setModerate),
            (165, .setModerate),
            (167, .setHard),
            (169, .setNearMax),
            (170, .setPR),      // PR 1

            // Cycle 2: start lower, work up to PR at 175
            (160, .setEasy),
            (164, .setModerate),
            (168, .setHard),
            (171, .setHard),
            (173, .setNearMax),
            (175, .setPR),      // PR 2

            // Cycle 3: start lower, work up to PR at 182
            (165, .setEasy),
            (169, .setEasy),
            (173, .setModerate),
            (176, .setHard),
            (179, .setNearMax),
            (182, .setPR),      // PR 3

            // Cycle 4: start lower, work up to PR at 188
            (172, .setEasy),
            (176, .setModerate),
            (180, .setModerate),
            (183, .setHard),
            (186, .setNearMax),
            (188, .setPR),      // PR 4

            // Cycle 5: start lower, work up to PR at 195
            (178, .setEasy),
            (182, .setModerate),
            (186, .setHard),
            (189, .setHard),
            (192, .setNearMax),
            (195, .setPR),      // PR 5

            // Cycle 6: start lower, work up to PR at 202
            (184, .setEasy),
            (188, .setEasy),
            (192, .setModerate),
            (196, .setHard),
            (199, .setNearMax),
            (202, .setPR),      // PR 6

            // Cycle 7: start lower, work up to PR at 208
            (190, .setEasy),
            (194, .setModerate),
            (198, .setModerate),
            (202, .setHard),
            (205, .setNearMax),
            (208, .setPR),      // PR 7

            // Cycle 8: start lower, work up to PR at 215
            (196, .setEasy),
            (200, .setEasy),
            (204, .setModerate),
            (208, .setHard),
            (212, .setNearMax),
            (215, .setPR),      // PR 8

            // Cycle 9: start lower, work up to PR at 222
            (202, .setEasy),
            (206, .setModerate),
            (210, .setModerate),
            (214, .setHard),
            (218, .setNearMax),
            (222, .setPR),      // PR 9

            // Cycle 10: start lower, work up to PR at 228
            (208, .setEasy),
            (212, .setEasy),
            (216, .setModerate),
            (220, .setHard),
            (225, .setNearMax),
            (228, .setPR),      // PR 10

            // Cycle 11 partial: starting the next cycle
            (214, .setEasy),
        ]
    }

    private let barWidth: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            // Text
            VStack(spacing: 12) {
                Text("Measure Your Progress")
                    .font(.bebasNeue(size: 32))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Watch your estimated 1RM grow over time")
                    .font(.inter(size: 16))
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
                    .font(.inter(size: 10))
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
                    LegendDot(color: .setEasy, label: "Easy")
                    LegendDot(color: .setModerate, label: "Moderate")
                    LegendDot(color: .setHard, label: "Hard")
                    LegendDot(color: .setNearMax, label: "Redline")
                    LegendDot(color: .setPR, label: "PR")
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
                    .font(.bebasNeue(size: 32))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Follow suggestions to progressively overload")
                    .font(.inter(size: 16))
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
                        .font(.interSemiBold(size: 10))
                        .foregroundStyle(Color(white: 0.5))
                        .frame(maxWidth: .infinity)

                    Text("REPS")
                        .font(.interSemiBold(size: 10))
                        .foregroundStyle(Color(white: 0.5))
                        .frame(maxWidth: .infinity)

                    Text("EST. 1RM")
                        .font(.interSemiBold(size: 10))
                        .foregroundStyle(Color(white: 0.5))
                        .frame(maxWidth: .infinity)

                    Text("GAIN")
                        .font(.interSemiBold(size: 10))
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
                .font(.interSemiBold(size: 14))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Text(suggestion.reps)
                .font(.interSemiBold(size: 14))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Text(suggestion.est1RM)
                .font(.interSemiBold(size: 14))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Text(suggestion.gain)
                .font(.interSemiBold(size: 14))
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
                .font(.inter(size: 10))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Page Four: Exercise Selection

private struct OnboardingExerciseSelection: View {
    let exercises: [Exercises]
    @Binding var selectedExerciseId: UUID?
    let onSelect: (UUID) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var sortedExercises: [Exercises] {
        exercises.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header text
            VStack(spacing: 12) {
                Text("Try It Out")
                    .font(.bebasNeue(size: 32))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Pick any exercise to get started")
                    .font(.inter(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 24)

            // Exercise grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(sortedExercises) { exercise in
                        OnboardingExerciseCard(
                            exercise: exercise,
                            isSelected: selectedExerciseId == exercise.id,
                            onSelect: {
                                onSelect(exercise.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }
}

private struct OnboardingExerciseCard: View {
    let exercise: Exercises
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(spacing: 12) {
                ExerciseIconView(exercise: exercise, size: 90)
                    .foregroundStyle(Color.appAccent)

                Text(exercise.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(height: 36, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(
                LinearGradient(
                    colors: [Color(white: 0.18), Color(white: 0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.appAccent : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
