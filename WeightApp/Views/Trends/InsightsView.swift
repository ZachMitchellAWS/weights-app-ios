//
//  InsightsView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/8/26.
//

import SwiftUI
import SwiftData

struct InsightsView: View {
    @State private var viewModel = InsightsViewModel()
    var audioPlayer: AudioPlayerManager
    @Query private var entitlementRecords: [EntitlementGrant]
    private static var thisWeekSetsDescriptor: FetchDescriptor<LiftSet> {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return FetchDescriptor<LiftSet>(
            predicate: #Predicate { !$0.deleted && $0.createdAt >= weekStart }
        )
    }
    @Query(thisWeekSetsDescriptor) private var thisWeekSets: [LiftSet]
    private static var estimated1RMsDescriptor: FetchDescriptor<Estimated1RM> {
        let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: Date())!
        return FetchDescriptor<Estimated1RM>(
            predicate: #Predicate { !$0.deleted && $0.createdAt >= cutoff }
        )
    }
    @Query(estimated1RMsDescriptor) private var allEstimated1RM: [Estimated1RM]
    @Query private var userPropertiesItems: [UserProperties]
    @State private var showUpsell = false

    private var userProperties: UserProperties { userPropertiesItems.first ?? UserProperties() }

    @State private var overallTier: StrengthTier = .none

    private var isPremium: Bool {
        if FreeOverride.isEnabled { return false }
        return PremiumOverride.isEnabled || EntitlementGrant.isPremium(entitlementRecords)
    }

    private var hasLocalSetsThisWeek: Bool { !thisWeekSets.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                weeklySection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 70)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.fetchInsights(force: true, isPremium: isPremium, hasLocalSetsThisWeek: hasLocalSetsThisWeek)
        }
        .task(id: allEstimated1RM.count) {
            overallTier = TrendsCalculator.strengthTierAssessment(
                from: allEstimated1RM,
                bodyweight: userProperties.bodyweight ?? 0,
                biologicalSex: userProperties.biologicalSex ?? "male"
            ).overallTier
        }
        .task {
            await viewModel.onAppear(isPremium: isPremium, hasLocalSetsThisWeek: hasLocalSetsThisWeek, overallTier: overallTier)
            PushNotificationService.shared.requestPermissionIfNeeded()
        }
        .onAppear {
            // Throttled auto-refresh: re-fetch if 5+ minutes since last tab visit
            let key = "narratives_tab_last_auto_refreshed"
            let last = UserDefaults.standard.double(forKey: key)
            let elapsed = last > 0 ? Date().timeIntervalSince1970 - last : .infinity
            if elapsed > 5 * 60 {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
                Task {
                    await viewModel.fetchInsights(force: true, isPremium: isPremium, hasLocalSetsThisWeek: hasLocalSetsThisWeek)
                }
            }
        }
        .onDisappear {
            viewModel.cancelAudioPoll()
        }
        .fullScreenCover(isPresented: $showUpsell) {
            UpsellView(initialPage: 1) { _ in showUpsell = false }
        }
    }

    // MARK: - Weekly Section

    @ViewBuilder
    private var weeklySection: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .loading:
            loadingContent
        case .empty(let reason):
            emptyContent(reason: reason)
        case .processing:
            processingContent
        case .loaded(let response):
            // Top-level header
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.appAccent)
                    Text("WEEKLY PROGRESS NARRATIVES")
                        .font(.bebasNeue(size: 22))
                        .foregroundStyle(.white)
                }

                if let start = response.weekStartDate, let end = response.weekEndDate {
                    Text(InsightsView.formatDateRange(start: start, end: end))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)

            if let sections = response.sections {
                ForEach(Array(sections.enumerated()), id: \.element.title) { index, section in
                    let style = InsightSectionStyle.from(title: section.title)
                    InsightSectionCard(section: section, style: style, audioPlayer: audioPlayer, sectionNumber: index + 1)

                    if index < sections.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)
                            .padding(.horizontal, 8)
                    }
                }

                Text("This analysis is AI-generated and may contain inaccuracies.\nConsult a qualified professional before making changes to your training program.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
            }

            Color.clear.frame(height: 0)
                .onAppear {
                    if let weekStart = response.weekStartDate {
                        NarrativeBadgeService.shared.markWeeklyViewed(weekStart: weekStart)
                    }
                }
        case .error(let message):
            errorContent(message: message)
        case .locked, .freeNoTier, .freeWithTier:
            weeklyInsightsPremiumSection
        }
    }

    // MARK: - Weekly Insights Premium Section

    private var weeklyInsightsPremiumSection: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                ForEach(InsightSectionStyle.allCases) { style in
                    placeholderCard(style: style)
                }
            }
            .premiumLocked(
                title: "Unlock Progress Narratives",
                subtitle: "AI-powered analysis of your training each week",
                showUpsell: $showUpsell
            )
        }
    }

    private func placeholderCard(style: InsightSectionStyle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: style.icon)
                    .foregroundStyle(style.color)
                    .font(.subheadline)
                Text(style.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }

            Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(style.color)
                .frame(width: 3)
        }
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Loading State

    private var loadingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white.opacity(0.6))
            Text("Loading narratives...")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Empty State

    @ViewBuilder
    private func emptyContent(reason: InsightsViewModel.EmptyReason) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 40))
                .foregroundStyle(Color.appAccent.opacity(0.5))

            switch reason {
            case .noSetsLogged:
                Text("No narratives yet.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))

                Text("Log at least one set to unlock your weekly narrative. Keep training!")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

            case .setsLoggedWeekInProgress(let sundayDate):
                Text("No narratives yet.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))

                Text("Your narrative will be ready after \(sundayDate). Keep training in the meantime!")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                Text("Pull to refresh to check.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Processing State

    private var processingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.appAccent)
            Text("Generating your narrative...")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Text("This usually takes about a minute.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Error State

    private func errorContent(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))

            Text("Your narrative isn't available right now")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))

            Text("Pull down to refresh")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    // MARK: - Date Range Formatting

    static func formatNextAvailable(weekEnd: String) -> String {
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        guard let endDate = isoFormatter.date(from: weekEnd),
              let nextMonday = Calendar.current.date(byAdding: .day, value: 8, to: endDate) else { return "" }
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "EEE, MMM d"
        return displayFormatter.string(from: nextMonday)
    }

    static func formatDateRange(start: String, end: String) -> String {
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d"

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"

        guard let startDate = isoFormatter.date(from: start),
              let endDate = isoFormatter.date(from: end) else {
            return "\(start) – \(end)"
        }

        let startStr = displayFormatter.string(from: startDate)
        let endStr = displayFormatter.string(from: endDate)
        let year = yearFormatter.string(from: endDate)
        return "\(startStr) – \(endStr), \(year)"
    }
}

// MARK: - Section Styling

enum InsightSectionStyle: String, CaseIterable, Identifiable {
    case trainingVolume
    case strengthHighlights
    case areasToWatch
    case accessoryGoals
    case nextWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trainingVolume: return "Training Volume"
        case .strengthHighlights: return "Strength Highlights"
        case .areasToWatch: return "Areas to Watch"
        case .accessoryGoals: return "Accessory Goals"
        case .nextWeek: return "Next Week"
        }
    }

    var icon: String {
        switch self {
        case .trainingVolume: return "chart.bar.fill"
        case .strengthHighlights: return "trophy.fill"
        case .areasToWatch: return "exclamationmark.triangle.fill"
        case .accessoryGoals: return "target"
        case .nextWeek: return "arrow.right.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .trainingVolume: return Color(red: 0x21/255, green: 0xB7/255, blue: 0xC9/255)
        case .strengthHighlights: return Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255)
        case .areasToWatch: return Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255)
        case .accessoryGoals: return Color(red: 0x5B/255, green: 0x3B/255, blue: 0xE8/255)
        case .nextWeek: return Color.appAccent
        }
    }

    static func from(title: String) -> InsightSectionStyle {
        switch title {
        case "Training Volume": return .trainingVolume
        case "Strength Highlights": return .strengthHighlights
        case "Areas to Watch": return .areasToWatch
        case "Accessory Goals": return .accessoryGoals
        case "Next Week": return .nextWeek
        default: return .trainingVolume
        }
    }
}

// MARK: - Insight Section Card

struct InsightSectionCard: View {
    let section: InsightSection
    let style: InsightSectionStyle
    var audioPlayer: AudioPlayerManager
    var sectionNumber: Int = 1

    private var isSectionPlaying: Bool {
        audioPlayer.currentlyPlayingSectionTitle == section.title && audioPlayer.isPlaying
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 8) {
                Image(systemName: style.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(style.color)
                    .frame(width: 24, height: 24)
                    .background(style.color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                if section.audioUrl != nil {
                    Button {
                        guard let urlString = section.audioUrl,
                              let url = URL(string: urlString) else { return }
                        audioPlayer.toggle(url: url, sectionTitle: section.title)
                    } label: {
                        Image(systemName: isSectionPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(style.color)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Body text
            Text(section.body)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(style.color)
                .frame(width: 3)
        }
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
