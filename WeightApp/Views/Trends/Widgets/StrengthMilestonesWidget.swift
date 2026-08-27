//
//  StrengthMilestonesWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/13/26.
//

import SwiftUI

struct StrengthMilestonesWidget: View {
    let allEstimated1RM: [Estimated1RM]
    let exercises: [Exercise]
    let bodyweight: Double?
    let biologicalSex: String?
    var isPremium: Bool = true
    var weightUnit: WeightUnit = .lbs
    @Binding var showUpsell: Bool

    @State private var milestoneResult: TrendsCalculator.MilestoneResult?
    /// Whether `.task` has run at all.
    ///
    /// Needed as a SEPARATE flag because nil already means two different things here: the
    /// task also assigns nil when `bodyweight` or `biologicalSex` is missing, and that user
    /// is genuinely pre-unlock and should still see the sample. Keying "unknown" off nil
    /// alone would silently downgrade them to the empty state.
    @State private var hasEvaluated = false

    @ObservedObject private var syncService = SyncService.shared

    /// Same rule as `StrengthTierWidget.canTrustVerdict`, and for the same reason: a
    /// milestone result computed over an incomplete `allEstimated1RM` reports
    /// `currentTier == .none`, which is indistinguishable from a genuinely locked user.
    private var canTrustVerdict: Bool {
        syncService.initialSyncComplete || !allEstimated1RM.isEmpty
    }

    var body: some View {
        if isPremium {
            unlockedContent
                .task(id: "\(exercises.compactMap(\.currentE1RMLocalCache).count)-\(allEstimated1RM.count)-\(syncService.initialSyncComplete)") {
                    // Stay unevaluated rather than record a verdict from absent data.
                    // `hasEvaluated` deliberately stays false, so `isPreUnlock` keeps
                    // returning false and the sample card is not reachable yet.
                    guard canTrustVerdict else { return }
                    if let bw = bodyweight, let sex = biologicalSex {
                        milestoneResult = TrendsCalculator.strengthMilestones(from: allEstimated1RM, exercises: exercises, bodyweight: bw, biologicalSex: sex)
                    } else {
                        milestoneResult = nil
                    }
                    // Both branches: the question "has this been worked out yet" is now
                    // answered, whatever the answer turned out to be.
                    hasEvaluated = true
                }
        } else {
            lockedContent
        }
    }

    // MARK: - Unlocked Content

    /// True until every fundamental has an e1RM — the same condition that leaves the
    /// tier widget unlocked, so the two cards flip to real data together.
    ///
    /// Returns FALSE before evaluation, not true. It used to return true while
    /// `milestoneResult` was nil, so the sample card rendered on the first frame for every
    /// user and `StrengthUnlockFooter.onAppear` fired `strengthSampleShown` — including for
    /// users who had long since unlocked, on every visit to the tab.
    private var isPreUnlock: Bool {
        guard hasEvaluated else { return false }
        // Evaluated but resultless means no bodyweight/sex on file. That user cannot be
        // scored yet, which IS pre-unlock — keep showing them the sample.
        guard let result = milestoneResult else { return true }
        return result.currentTier == .none
    }

    @ViewBuilder
    private var unlockedContent: some View {
        if isPreUnlock {
            // Before unlock the real grid renders every one of its 30 badges at 0%,
            // which is technically accurate and completely inert. Show the sample
            // instead — same component, sample numbers.
            preUnlockSampleCard
        } else if let result = milestoneResult {
            MilestoneContentView(result: result, weightUnit: weightUnit)
        } else {
            // Reached only before `.task` has run. The old copy nudged the user to log
            // their five lifts, which is a false statement to the unlocked user who now
            // passes through here for a frame — so it is loading-shaped instead.
            WidgetCard(title: "Strength Milestones") {
                EmptyWidgetState(
                    icon: "medal.fill",
                    message: "Checking your milestones…"
                )
            }
        }
    }

    // MARK: - Pre-unlock Sample

    /// The real milestone UI driven by `StrengthSampleData`, so this card and the tier
    /// card describe the same imaginary lifter. Both derive from one set of e1RMs run
    /// through the production algorithm, so they cannot drift apart.
    ///
    /// Deliberately shares no vocabulary with the premium lock — no blur, no scrim, no
    /// CTA. Milestones are free; obscuring them would read as a paywall.
    @ViewBuilder
    private var preUnlockSampleCard: some View {
        if let sample = StrengthSampleData.milestoneResult {
            MilestoneContentView(
                result: sample,
                weightUnit: weightUnit,
                unlockFooter: StrengthUnlockFooter(
                    loggedFlags: realLoggedFlags,
                    widget: "strength_milestones"
                )
            )
            // No blanket `allowsHitTesting(false)` here — it would swallow the footer's
            // tap. `MilestoneContentView` disables only the sample grid itself.
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.appAccent.opacity(0.25), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                StrengthSampleBadge().padding(10)
            }
        }
    }

    /// The user's genuine per-lift logged state, taken from the real result's Novice
    /// batch — its milestone is literally "≥1 set", so `achieved` per lift is exactly
    /// the unlock checklist, already computed and in fundamentals order.
    private var realLoggedFlags: [Bool] {
        guard let novice = milestoneResult?.batches.first(where: { $0.tier == .novice }) else {
            return Array(repeating: false, count: TrendsCalculator.fundamentalExercises.count)
        }
        return novice.milestones.map(\.achieved)
    }

    // MARK: - Locked Content

    // MARK: - Locked Content

    // Fake achieved pattern per tier row — ensures every color is well-represented
    // [Deadlifts, Squats, Bench, Row, OHP]
    private static let fakeAchievedPattern: [[Bool]] = [
        [true,  true,  true,  true,  true ],  // Novice — all done
        [true,  true,  true,  true,  true ],  // Beginner — all done
        [true,  true,  true,  true,  false],  // Intermediate — 4/5
        [true,  true,  false, true,  false],  // Advanced — 3/5
        [true,  false, false, false, false],  // Elite — 1/5
        [false, false, false, false, false],  // Legend — none
    ]

    private static let fakeExerciseNames = ["Deadlifts", "Squats", "Bench", "Row", "OHP"]

    private var lockedContent: some View {
        let tiers: [StrengthTier] = [.novice, .beginner, .intermediate, .advanced, .elite, .legend]

        return VStack(spacing: 10) {
            // Fake header
            VStack(spacing: 6) {
                Text("STRENGTH MILESTONES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .tracking(1.5)

                Text("17 / 30 Achieved")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // 6 compact rows — one per tier, no headers
            ForEach(Array(tiers.enumerated()), id: \.element.rawValue) { tierIndex, tier in
                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { i in
                        let achieved = Self.fakeAchievedPattern[tierIndex][i]
                        VStack(spacing: 3) {
                            ZStack {
                                Circle()
                                    .stroke(tier.color.opacity(achieved ? 0.7 : 0.25), lineWidth: 2.5)
                                    .frame(width: 40, height: 40)

                                if achieved {
                                    Circle()
                                        .fill(tier.color.opacity(0.2))
                                        .frame(width: 40, height: 40)

                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(tier.color)
                                }
                            }

                            Text(Self.fakeExerciseNames[i])
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumLocked(
            title: "Unlock Strength Milestones",
            subtitle: "Track tier-based milestones for every fundamental lift",
            blurRadius: 6,
            feature: "strength_milestones",
            showUpsell: $showUpsell
        )
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Milestone Content View

private struct MilestoneContentView: View {
    let result: TrendsCalculator.MilestoneResult
    var weightUnit: WeightUnit = .lbs
    /// Real unlock progress, appended inside the card. Only the sample variant passes
    /// this — an earned card has nothing left to unlock.
    var unlockFooter: StrengthUnlockFooter? = nil

    /// Only the sample card supplies a footer, so its presence identifies that variant.
    private var isSample: Bool { unlockFooter != nil }

    @State private var expandedTiers: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(spacing: 6) {
                Text("STRENGTH MILESTONES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .tracking(1.5)

                Text("\(result.achievedCount) / \(result.totalCount) Achieved")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.appAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Tier batches
            ForEach(result.batches) { batch in
                TierBatchSection(
                    batch: batch,
                    isExpanded: expandedTiers.contains(batch.id),
                    isLegendAchieved: batch.tier == .legend && batch.allAchieved,
                    weightUnit: weightUnit
                ) {
                    toggleTier(batch.id)
                }
            }
            // Sample tier rows must not expand; the footer above stays tappable.
            .allowsHitTesting(!isSample)

            if let unlockFooter {
                StrengthSampleDivider()
                unlockFooter
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            expandedTiers = defaultExpandedTiers()
        }
    }

    private func defaultExpandedTiers() -> Set<Int> {
        let batches = result.batches
        guard !batches.isEmpty else { return [] }

        // Find the index of the current tier batch
        let tierIndex = batches.firstIndex(where: { $0.tier == result.currentTier }) ?? 0

        // Sliding window of 3, clamped at edges
        let windowStart = max(0, min(tierIndex - 1, batches.count - 3))
        let windowEnd = min(windowStart + 3, batches.count)

        var expanded = Set<Int>()
        for i in windowStart..<windowEnd {
            expanded.insert(batches[i].id)
        }
        return expanded
    }

    private func toggleTier(_ id: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedTiers.contains(id) {
                expandedTiers.remove(id)
            } else {
                expandedTiers.insert(id)
            }
        }
    }
}

// MARK: - Tier Batch Section

private struct TierBatchSection: View {
    let batch: TrendsCalculator.TierMilestoneBatch
    let isExpanded: Bool
    let isLegendAchieved: Bool
    var weightUnit: WeightUnit = .lbs
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(batch.tier.color)
                        .frame(width: 10, height: 10)

                    Text(batch.tier.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    if isLegendAchieved {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(Color.appAccent)
                            .font(.caption)
                    } else if batch.allAchieved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.appAccent)
                            .font(.caption)
                    } else {
                        Text("\(batch.achievedCount)/\(batch.milestones.count)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    // Right when collapsed, down when expanded.
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            // Expanded content — badge grid
            if isExpanded {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(batch.milestones) { milestone in
                        TierMilestoneBadge(
                            milestone: milestone,
                            tierColor: batch.tier.color,
                            isLegend: batch.tier == .legend,
                            weightUnit: weightUnit
                        )
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tier Milestone Badge

private struct TierMilestoneBadge: View {
    let milestone: TrendsCalculator.TierMilestone
    let tierColor: Color
    let isLegend: Bool
    var weightUnit: WeightUnit = .lbs

    private var badgeSize: CGFloat { 48 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if milestone.achieved {
                    // Achieved: filled circle with checkmark + icon
                    Circle()
                        .fill(tierColor.opacity(0.2))
                        .frame(width: badgeSize, height: badgeSize)

                    Circle()
                        .stroke(tierColor.opacity(0.7), lineWidth: 2.5)
                        .frame(width: badgeSize, height: badgeSize)

                    if isLegend {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(tierColor)
                    } else {
                        Image(milestone.exerciseIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .foregroundStyle(tierColor)
                    }
                } else {
                    // Progress ring
                    Circle()
                        .stroke(tierColor.opacity(0.25), lineWidth: 2.5)
                        .frame(width: badgeSize, height: badgeSize)

                    Circle()
                        .trim(from: 0, to: milestone.progress)
                        .stroke(tierColor.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: badgeSize, height: badgeSize)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(milestone.progress * 100))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            // Exercise name
            Text(shortName(milestone.exerciseName))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Target label
            Text(milestone.isAbsoluteTarget
                 ? "\(Int(weightUnit.fromLbs(milestone.targetLbs))) \(weightUnit.label)"
                 : milestone.targetLabel)
                .font(.system(size: 8, weight: .regular))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func shortName(_ name: String) -> String {
        switch name {
        case "Bench Press": return "Bench"
        case "Overhead Press": return "OHP"
        case "Barbell Rows": return "Row"
        default: return name
        }
    }
}
