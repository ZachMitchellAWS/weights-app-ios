//
//  StrengthTierWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/12/26.
//

import SwiftUI
import SwiftData

struct StrengthTierWidget: View {
    let allEstimated1RM: [Estimated1RM]
    @Bindable var userProperties: UserProperties
    var isPremium: Bool = true
    @Binding var showUpsell: Bool
    @Environment(\.modelContext) private var modelContext

    @State private var showWeightPicker = false
    @State private var tempBodyweight: Double = 180

    private var biologicalSex: String? { userProperties.biologicalSex }
    private var bodyweight: Double? { userProperties.bodyweight }

    private var hasBothPrerequisites: Bool {
        biologicalSex != nil && bodyweight != nil
    }

    private var tierResult: TrendsCalculator.StrengthTierResult? {
        guard let sex = biologicalSex, let bw = bodyweight else { return nil }
        return TrendsCalculator.strengthTierAssessment(
            from: allEstimated1RM,
            bodyweight: bw,
            biologicalSex: sex
        )
    }

    var body: some View {
        if isPremium {
            VStack(alignment: .leading, spacing: 12) {
                if hasBothPrerequisites, let result = tierResult {
                    resultsView(result)
                } else {
                    // Show title manually for prerequisite view
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Strength Tier")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Overall assessment based on your 5 fundamental lifts")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    prerequisiteView
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.4), lineWidth: 1.5))
        } else {
            lockedContent
        }
    }

    // MARK: - Locked Content (Free Users)

    private var lockedContent: some View {
        // Fake results view — static, non-interactive
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 4) {
                Text("STRENGTH TIER")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1.2)
                HStack(spacing: 10) {
                    Image("LiftTheBullIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .foregroundStyle(StrengthTier.elite.color)
                    Text("Advanced")
                        .font(.title.weight(.bold))
                        .foregroundStyle(StrengthTier.advanced.color)
                }
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.white.opacity(0.15))
                    .frame(width: 180, height: 1)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Fake progress bar
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.appAccent)
                            .frame(width: geo.size.width * 0.72, height: 6)
                    }
                }
                .frame(height: 6)

                Text("72% to Elite")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)

            // Fake exercise rows — each a different tier for maximum color variety
            VStack(spacing: 0) {
                fakeExerciseRow(name: "Squat", lbs: 315, tier: .elite)
                Divider().background(.white.opacity(0.1))
                fakeExerciseRow(name: "Bench Press", lbs: 225, tier: .advanced)
                Divider().background(.white.opacity(0.1))
                fakeExerciseRow(name: "Deadlift", lbs: 405, tier: .legend)
                Divider().background(.white.opacity(0.1))
                fakeExerciseRow(name: "Overhead Press", lbs: 135, tier: .intermediate)
                Divider().background(.white.opacity(0.1))
                fakeExerciseRow(name: "Barbell Row", lbs: 185, tier: .beginner)
            }

        }
        .padding()
        .premiumLocked(
            title: "Unlock Strength Tiers",
            subtitle: "Discover your strength level across your lifts",
            showUpsell: $showUpsell
        )
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func fakeExerciseRow(name: String, lbs: Int, tier: StrengthTier) -> some View {
        HStack(spacing: 10) {
            Image("LiftTheBullIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(StrengthTier.elite.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(lbs) lbs")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Text(tier.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tier == .rookie ? .white.opacity(0.6) : tier.color)
                .frame(width: 90)
                .padding(.vertical, 3)
                .background(tier == .rookie ? Color.white.opacity(0.1) : tier.color.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.vertical, 8)
    }

    // MARK: - Prerequisite View

    private var prerequisiteView: some View {
        VStack(spacing: 16) {
            // Biological Sex
            VStack(alignment: .leading, spacing: 6) {
                Text("Biological Sex")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 0) {
                    sexButton("Male", value: "male")
                    sexButton("Female", value: "female")
                }
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Bodyweight
            if bodyweight == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bodyweight")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))

                    Button {
                        tempBodyweight = 180
                        showWeightPicker = true
                    } label: {
                        HStack {
                            Text("Tap to set bodyweight")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            if biologicalSex != nil && bodyweight == nil {
                Text("Set your bodyweight to see your strength tier")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            } else if biologicalSex == nil {
                Text("Select biological sex to begin")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
        }
        .sheet(isPresented: $showWeightPicker) {
            weightPickerSheet
        }
    }

    private func sexButton(_ label: String, value: String) -> some View {
        Button {
            userProperties.biologicalSex = value
            Task { await SyncService.shared.updateBiologicalSex(value) }
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(biologicalSex == value ? .black : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(biologicalSex == value ? Color.appAccent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Weight Picker Sheet

    private var weightPickerSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    Spacer().frame(height: 8)

                    Text("Set Bodyweight")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer().frame(height: 20)

                    HStack(spacing: 0) {
                        Picker("Weight", selection: $tempBodyweight) {
                            ForEach(Array(stride(from: 50.0, through: 500.0, by: 1.0)), id: \.self) { weight in
                                Text("\(Int(weight))")
                                    .tag(weight)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)

                        Text("lbs")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.trailing, 40)
                    }
                    .frame(height: 200)

                    Spacer()

                    Button {
                        userProperties.bodyweight = tempBodyweight
                        try? modelContext.save()
                        showWeightPicker = false
                        Task { await SyncService.shared.updateBodyweight(tempBodyweight) }
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.appAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Results View

    @State private var expandedExercises: Set<String> = []

    private func resultsView(_ result: TrendsCalculator.StrengthTierResult) -> some View {
        VStack(spacing: 16) {
            // Centered header
            VStack(spacing: 6) {
                Text("STRENGTH TIER")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .tracking(1.5)

                HStack(spacing: 10) {
                    Image(result.overallTier.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .foregroundStyle(StrengthTier.elite.color)

                    Text(result.overallTier.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(result.overallTier.color)
                }

            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Overall tier progress bar
            if result.overallTier != .legend {
                let overallProgress = overallTierProgress(result)
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.appAccent)
                                .frame(width: geo.size.width * overallProgress, height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("\(Int(overallProgress * 100))% to \(result.overallTier.next?.title ?? "next tier")")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 16)
            }

            // Exercise rows
            VStack(spacing: 0) {
                ForEach(Array(result.exerciseTiers.enumerated()), id: \.element.exercise.id) { index, item in
                    VStack(spacing: 0) {
                        exerciseRow(item: item, isExpanded: expandedExercises.contains(item.exercise.name))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    if expandedExercises.contains(item.exercise.name) {
                                        expandedExercises.remove(item.exercise.name)
                                    } else {
                                        expandedExercises.insert(item.exercise.name)
                                    }
                                }
                            }

                        if expandedExercises.contains(item.exercise.name) {
                            exerciseExpansion(for: item.exercise.name)
                                .transition(.opacity)
                        }

                        if index < result.exerciseTiers.count - 1 {
                            Divider()
                                .background(.white.opacity(0.1))
                        }
                    }
                }
            }

            // Static tier legend
            tierLegendBar

            // Explanation
            Text("Your overall tier is determined by your lowest lift. All five exercises must reach a tier for it to apply.")
                .font(.caption2)
                .italic()
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func exerciseRow(item: (exercise: TrendsCalculator.FundamentalExercise, e1rm: Double?, tier: StrengthTier), isExpanded: Bool) -> some View {
        let progress = progressToNextTier(item: item)

        return HStack(spacing: 10) {
            Image(item.exercise.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(StrengthTier.elite.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.exercise.name)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                if let e1rm = item.e1rm {
                    HStack(spacing: 0) {
                        Text("\(Int(e1rm)) lbs")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))

                        if item.tier > .rookie, let bw = bodyweight, bw > 0 {
                            Text(" | ")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.2))
                            Text(String(format: "%.2f× BW", e1rm / bw))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                } else {
                    Text("No data")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            Spacer()

            // Progress bar — fixed position before fixed-width pill
            if let progress = progress {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 36, height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.tier.color)
                        .frame(width: 36 * progress, height: 4)
                }
                .frame(width: 36, height: 4)
            } else {
                Spacer().frame(width: 36)
            }

            // Tier pill — fixed width so all rows align
            Text(item.tier.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.tier == .rookie ? .white.opacity(0.6) : item.tier.color)
                .frame(width: 90)
                .padding(.vertical, 3)
                .background(
                    item.tier == .rookie ? Color.white.opacity(0.1) : item.tier.color.opacity(0.15)
                )
                .clipShape(Capsule())

            // Expand/collapse indicator
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .padding(.vertical, 8)
    }

    // MARK: - Per-Row Expansion

    private func exerciseExpansion(for exerciseName: String) -> some View {
        let sex = biologicalSex.flatMap { BiologicalSex(rawValue: $0) } ?? .male
        let bw = bodyweight ?? 0

        return VStack(alignment: .leading, spacing: 5) {
            ForEach(StrengthTier.allCases, id: \.rawValue) { tier in
                if let threshold = StrengthTierData.thresholds[exerciseName]?[sex]?[tier] {
                    HStack(spacing: 0) {
                        Circle().fill(tier.color).frame(width: 6, height: 6)
                            .padding(.trailing, 6)

                        Text(tier.title)
                            .font(.caption2)
                            .foregroundStyle(tier.color)
                            .frame(width: 80, alignment: .leading)

                        Spacer().frame(width: 8)

                        Text(expansionRangeLabel(threshold, bodyweight: bw))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
        }
        .padding(.leading, 8)
        .padding(.vertical, 6)
    }

    private func expansionRangeLabel(_ threshold: TierThreshold, bodyweight: Double) -> String {
        if threshold.isAbsolute {
            let maxStr = threshold.max.map { "\(Int($0))" } ?? "+"
            return "\(Int(threshold.min))–\(maxStr) lbs"
        } else {
            let minLbs = Int(threshold.min * bodyweight)
            if let max = threshold.max {
                let maxLbs = Int(max * bodyweight)
                return "\(minLbs)–\(maxLbs) lbs (\(String(format: "%.2g", threshold.min))–\(String(format: "%.2g", max))× BW)"
            } else {
                return "\(minLbs)+ lbs (\(String(format: "%.2g", threshold.min))× BW+)"
            }
        }
    }

    // MARK: - Tier Legend

    private var tierLegendBar: some View {
        let tiers = StrengthTier.allCases
        let topRow = Array(tiers.prefix(3))
        let bottomRow = Array(tiers.suffix(3))

        return VStack(spacing: 8) {
            HStack(spacing: 16) {
                ForEach(topRow, id: \.rawValue) { tier in
                    tierLegendItem(tier)
                }
            }
            HStack(spacing: 16) {
                ForEach(bottomRow, id: \.rawValue) { tier in
                    tierLegendItem(tier)
                }
            }
        }
    }

    private func tierLegendItem(_ tier: StrengthTier) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tier.color).frame(width: 7, height: 7)
            Text(tier.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tier.color)
        }
    }

    // MARK: - Progress Calculation

    private func overallTierProgress(_ result: TrendsCalculator.StrengthTierResult) -> Double {
        guard let bw = bodyweight, let sex = biologicalSex.flatMap({ BiologicalSex(rawValue: $0) }) else { return 0 }
        guard let nextTier = result.overallTier.next else { return 0 }

        // For each exercise, calculate progress toward the next overall tier
        // Exercises already at or above the target tier count as 100%
        var progresses: [Double] = []
        for item in result.exerciseTiers {
            if item.tier >= nextTier {
                progresses.append(1.0)
                continue
            }
            guard let e1rm = item.e1rm else {
                progresses.append(0)
                continue
            }
            let currentMin = StrengthTierData.currentTierMinimum(
                name: item.exercise.name, tier: item.tier, bodyweight: bw, sex: sex
            )
            guard let targetMin = StrengthTierData.nextTierMinimum(
                name: item.exercise.name, currentTier: item.tier, bodyweight: bw, sex: sex
            ) else {
                progresses.append(0)
                continue
            }
            let range = targetMin - currentMin
            guard range > 0 else { progresses.append(1.0); continue }
            progresses.append(min(max((e1rm - currentMin) / range, 0), 1.0))
        }

        guard !progresses.isEmpty else { return 0 }
        // Average across all exercises — reflects overall completion toward next tier
        return progresses.reduce(0, +) / Double(progresses.count)
    }

    private func progressToNextTier(item: (exercise: TrendsCalculator.FundamentalExercise, e1rm: Double?, tier: StrengthTier)) -> Double? {
        guard let bw = bodyweight, let sex = biologicalSex.flatMap({ BiologicalSex(rawValue: $0) }) else { return nil }
        guard item.tier != .legend else { return nil }
        guard let e1rm = item.e1rm else { return 0 }

        let currentMin = StrengthTierData.currentTierMinimum(
            name: item.exercise.name,
            tier: item.tier,
            bodyweight: bw,
            sex: sex
        )
        guard let nextMin = StrengthTierData.nextTierMinimum(
            name: item.exercise.name,
            currentTier: item.tier,
            bodyweight: bw,
            sex: sex
        ) else { return nil }

        let range = nextMin - currentMin
        guard range > 0 else { return 1.0 }
        return min(max((e1rm - currentMin) / range, 0), 1.0)
    }
}

