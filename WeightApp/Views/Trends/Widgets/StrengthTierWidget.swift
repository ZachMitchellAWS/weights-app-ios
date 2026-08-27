//
//  StrengthTierWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/12/26.
//

import SwiftUI

struct StrengthTierWidget: View {
    let allEstimated1RM: [Estimated1RM]
    let exercises: [Exercise]
    @Bindable var userProperties: UserProperties
    var isPremium: Bool = true
    @Binding var showUpsell: Bool
    var onSettingsTapped: (() -> Void)? = nil

    @ObservedObject private var syncService = SyncService.shared

    /// Whether a `.none` verdict can be TRUSTED to mean "not unlocked".
    ///
    /// `strengthTierAssessment` over an incomplete `allEstimated1RM` returns `.none` — the
    /// same value a genuinely locked user produces. So computing before the data has landed
    /// manufactures a locked verdict for everybody, which is what kept firing
    /// `strengthSampleShown` for unlocked users even after the nil-state fix.
    ///
    /// Sync complete is authoritative. Failing that, the presence of any local e1RM means
    /// there is real data to assess. Neither → we do not know yet, so do not guess.
    /// Mirrors the `syncComplete || !hasData` idiom at `CheckInView.evaluateTierJourney`.
    private var canTrustVerdict: Bool {
        syncService.initialSyncComplete || !allEstimated1RM.isEmpty
    }

    private var biologicalSex: String { userProperties.biologicalSex ?? "male" }
    private var bodyweight: Double { userProperties.bodyweight ?? 200.0 }

    /// Optional so that "not computed yet" is a state the view can SEE.
    ///
    /// This used to be seeded by running the real assessment over empty arrays, which
    /// necessarily returns `.none` — the same value the gate below reads as "not yet
    /// unlocked". Every user therefore rendered the sample card on their first frame, and
    /// `StrengthUnlockFooter.onAppear` fired `strengthSampleShown` before `.task` had a
    /// chance to compute the truth. Unlocked users emitted it on every visit to this tab.
    ///
    /// `.task` assigns unconditionally, so nil here means exactly one thing: it has not run.
    @State private var tierResult: TrendsCalculator.StrengthTierResult?

    var body: some View {
        Group {
            if !isPremium {
                lockedContent
            } else if let tierResult {
                if tierResult.overallTier == .none {
                    // Any missing fundamental forces `.none` (the overall tier is the
                    // lowest of the five), so this is precisely "not yet unlocked".
                    // Derived from data rather than `hasMetStrengthTierConditions`, so it
                    // self-corrects if sets are later deleted.
                    preUnlockSampleCard(tierResult)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        resultsView(tierResult)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                // Unknown, not locked. Copy is loading-shaped on purpose: the pre-unlock
                // nudge ("log your five lifts") would be a false statement to the unlocked
                // user who passes through here for a frame.
                WidgetCard(title: "Strength Tier") {
                    EmptyWidgetState(
                        icon: "figure.strengthtraining.traditional",
                        message: "Calculating your strength tier…"
                    )
                }
            }
        }
        .task(id: "\(exercises.compactMap(\.currentE1RMLocalCache).count)-\(allEstimated1RM.count)-\(syncService.initialSyncComplete)") {
            // Leave `tierResult` nil rather than writing a verdict we cannot stand behind.
            // The id above includes `initialSyncComplete`, so this re-runs the moment sync
            // lands and the real assessment replaces the loading state.
            guard canTrustVerdict else { return }
            tierResult = TrendsCalculator.strengthTierAssessment(
                from: allEstimated1RM,
                exercises: exercises,
                bodyweight: bodyweight,
                biologicalSex: biologicalSex
            )
        }
    }

    // MARK: - Sample content
    //
    // One fake, two chromes: the pre-unlock card wraps it in sample chrome, and
    // `lockedContent` wraps the same thing in `.premiumLocked`. Previously this existed
    // only inside `lockedContent`, which is unreachable while `isPremium` is hardcoded
    // true at the call site — so it was never actually seen. It ships now, which is why
    // the values below are internally consistent rather than merely plausible.

    private var sampleTierContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("STRENGTH TIER")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .tracking(1.5)

                HStack(spacing: 10) {
                    Image(StrengthSampleData.overallTier.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .foregroundStyle(StrengthTier.elite.color)
                    Text(StrengthSampleData.overallTier.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(StrengthSampleData.overallTier.color)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            VStack(spacing: 4) {
                let progress = StrengthSampleData.progressToNextTier
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.appAccent)
                            .frame(width: geo.size.width * progress, height: 6)
                    }
                }
                .frame(height: 6)

                if let next = StrengthSampleData.overallTier.next {
                    (
                        Text("\(Int(progress * 100))% to ")
                            .foregroundStyle(.white.opacity(0.4))
                        + Text(next.title).foregroundStyle(next.color).bold()
                    )
                    .font(.caption2)
                }
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(Array(TrendsCalculator.fundamentalExercises.enumerated()), id: \.offset) { index, fundamental in
                    sampleExerciseRow(fundamental)
                    if index < TrendsCalculator.fundamentalExercises.count - 1 {
                        Divider().background(.white.opacity(0.1))
                    }
                }
            }
        }
    }

    private func sampleExerciseRow(_ fundamental: TrendsCalculator.FundamentalExercise) -> some View {
        let unit = userProperties.preferredWeightUnit
        let tier = StrengthSampleData.tier(for: fundamental.name)
        let e1rm = StrengthSampleData.e1rm(for: fundamental.name)
        let progress = StrengthSampleData.tierProgress(for: fundamental.name)

        return HStack(spacing: 10) {
            Image(fundamental.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(StrengthTier.elite.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(fundamental.name)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                // Converted, so a kg user isn't shown lbs numbers labelled "kg".
                Text("\(unit.formatWeightTrimmed(e1rm)) \(unit.label)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            // Mini bar, matching the real rows — without it the sample looks less
            // complete than the card it's advertising.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 36, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(tier.color)
                    .frame(width: 36 * progress, height: 4)
            }
            .frame(width: 36, height: 4)

            Text(tier.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tier <= .novice ? .white.opacity(0.6) : tier.color)
                .frame(width: 90)
                .padding(.vertical, 3)
                .background(tier <= .novice ? Color.white.opacity(0.1) : tier.color.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.vertical, 8)
    }

    // MARK: - Pre-unlock sample card

    /// Sample above, the user's REAL progress below. Deliberately shares nothing with
    /// the premium-lock treatment — no blur, no scrim, no lock, no CTA. Tiers are free,
    /// so borrowing that vocabulary would tell free users to pay for what they have.
    /// Takes the settled result rather than reading `tierResult` itself.
    ///
    /// That is the point: the footer's `loggedFlags` — and therefore the `liftsLogged` it
    /// reports — can now only be built from a computed assessment. Reading the optional here
    /// would let a nil unwrap silently to an all-false checklist, which is exactly the wrong
    /// data that made the spurious events say `liftsLogged: 0`.
    private func preUnlockSampleCard(_ result: TrendsCalculator.StrengthTierResult) -> some View {
        VStack(spacing: 16) {
            sampleTierContent
                .allowsHitTesting(false)

            StrengthSampleDivider()

            StrengthUnlockFooter(
                loggedFlags: result.exerciseTiers.map { $0.e1rm != nil },
                widget: "strength_tier"
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.appAccent.opacity(0.25), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            StrengthSampleBadge().padding(10)
        }
    }

    // MARK: - Locked Content (Free Users)

    /// Paywall variant. Unreachable while `isPremium` is hardcoded `true` at the call
    /// site (`BalanceView.swift:73`), but kept working so tiers can go premium again
    /// without rebuilding the fake. Same content as the sample card, different chrome.
    private var lockedContent: some View {
        sampleTierContent
            .padding()
            .premiumLocked(
                title: "Unlock Strength Tiers",
                subtitle: "Discover your strength level across your lifts",
                feature: "strength_tiers",
                showUpsell: $showUpsell
            )
            .background(Color(white: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Results View

    @State private var expandedExercises: Set<String> = []

    /// Only ever renders a genuinely earned tier. The pre-unlock case is handled by
    /// `preUnlockSampleCard` in `body`, so the old `isChecklistMode` fork that ran
    /// through this whole function is gone.
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

            // Progress indicator
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

                    (
                        Text("\(Int(overallProgress * 100))% to ")
                            .foregroundColor(.white.opacity(0.4))
                        +
                        Text(result.overallTier.next?.title ?? "next tier")
                            .foregroundColor(result.overallTier.next?.color ?? .white.opacity(0.4))
                            .bold()
                    )
                    .font(.caption2)
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

            // Explanation with profile settings link
            (Text("Your overall tier is determined by your lowest lift. Tier ranges are based on your ")
                .foregroundStyle(.white.opacity(0.3))
            + Text("profile settings")
                .foregroundStyle(Color.appAccent)
            + Text(".")
                .foregroundStyle(.white.opacity(0.3)))
            .font(.caption2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .onTapGesture { onSettingsTapped?() }
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
                        Text("\(userProperties.preferredWeightUnit.formatWeightTrimmed(e1rm)) \(userProperties.preferredWeightUnit.label)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))

                        if item.tier > .novice, bodyweight > 0 {
                            Text(" | ")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.2))
                            Text(String(format: "%.2f× BW", e1rm / bodyweight))
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
            .fixedSize(horizontal: true, vertical: false)

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
                .foregroundStyle(item.tier <= .novice ? .white.opacity(0.6) : item.tier.color)
                .frame(width: 90)
                .padding(.vertical, 3)
                .background(
                    item.tier <= .novice ? Color.white.opacity(0.1) : item.tier.color.opacity(0.15)
                )
                .clipShape(Capsule())

            // Expand/collapse indicator — right when collapsed, down when expanded.
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.vertical, 8)
    }

    // MARK: - Per-Row Expansion

    private func exerciseExpansion(for exerciseName: String) -> some View {
        let sex = BiologicalSex(rawValue: biologicalSex) ?? .male
        let bw = bodyweight

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
        let unit = userProperties.preferredWeightUnit
        if threshold.isAbsolute {
            let minDisplay = unit.formatWeightRounded(threshold.min)
            let maxStr = threshold.max.map { unit.formatWeightRounded($0) } ?? "+"
            return "\(minDisplay)–\(maxStr) \(unit.label)"
        } else {
            let minLbs = threshold.min * bodyweight
            let minDisplay = unit.formatWeightRounded(minLbs)
            if let max = threshold.max {
                let maxLbs = max * bodyweight
                let maxDisplay = unit.formatWeightRounded(maxLbs)
                return "\(minDisplay)–\(maxDisplay) \(unit.label) (\(String(format: "%.2g", threshold.min))–\(String(format: "%.2g", max))× BW)"
            } else {
                return "\(minDisplay)+ \(unit.label) (\(String(format: "%.2g", threshold.min))× BW+)"
            }
        }
    }

    // MARK: - Tier Legend

    private var tierLegendBar: some View {
        let tiers = StrengthTier.allCases.filter { $0 != .none }
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
        guard let sex = BiologicalSex(rawValue: biologicalSex) else { return 0 }
        let bw = bodyweight
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
        guard let sex = BiologicalSex(rawValue: biologicalSex) else { return nil }
        let bw = bodyweight
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

