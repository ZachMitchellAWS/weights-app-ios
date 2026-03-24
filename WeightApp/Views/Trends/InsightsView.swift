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
    @State private var audioPlayer = AudioPlayerManager()
    @Query private var entitlementRecords: [EntitlementGrant]
    @Query private var allLiftSets: [LiftSet]
    @Query(filter: #Predicate<Estimated1RM> { !$0.deleted }, sort: \Estimated1RM.createdAt) private var allEstimated1RM: [Estimated1RM]
    @Query private var userPropertiesItems: [UserProperties]
    @State private var showUpsell = false

    private var userProperties: UserProperties { userPropertiesItems.first ?? UserProperties() }

    private var overallTier: StrengthTier {
        TrendsCalculator.strengthTierAssessment(
            from: allEstimated1RM,
            bodyweight: userProperties.bodyweight ?? 0,
            biologicalSex: userProperties.biologicalSex ?? "male"
        ).overallTier
    }

    private static let headerColors: [Color] = [
        Color(red: 0x21/255, green: 0xB7/255, blue: 0xC9/255),  // teal (Training Volume)
        Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255),  // green (Strength Highlights)
        Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255),  // amber (Areas to Watch)
        Color(red: 0x5B/255, green: 0x3B/255, blue: 0xE8/255),  // violet (Accessory Goals)
        Color.appAccent,                                          // light amber (Next Week)
    ]

    private var isPremium: Bool {
        if FreeOverride.isEnabled { return false }
        return PremiumOverride.isEnabled || EntitlementGrant.isPremium(entitlementRecords)
    }

    private var hasLocalSetsThisWeek: Bool {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return false }
        return allLiftSets.contains { $0.createdAt >= weekStart }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                insightsHeader

                switch viewModel.state {
                case .idle:
                    EmptyView()
                case .locked:
                    lockedContent
                case .freeNoTier:
                    freeNoTierContent
                case .freeWithTier(let tier, let starterResponse):
                    freeWithTierContent(tier: tier, response: starterResponse)
                case .loading:
                    loadingContent
                case .empty(let reason):
                    emptyContent(reason: reason)
                case .processing:
                    processingContent
                case .loaded(let response):
                    populatedContent(response: response)
                case .error(let message):
                    errorContent(message: message)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 70)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            guard isPremium else { return }
            await viewModel.fetchInsights(force: true, isPremium: isPremium, hasLocalSetsThisWeek: hasLocalSetsThisWeek)
        }
        .task {
            await viewModel.onAppear(isPremium: isPremium, hasLocalSetsThisWeek: hasLocalSetsThisWeek, overallTier: overallTier)
            PushNotificationService.shared.requestPermissionIfNeeded()
            if case .loaded(let response) = viewModel.state,
               let weekStart = response.weekStartDate {
                NarrativeBadgeService.shared.markViewed(weekStart: weekStart)
            }
        }
        .onChange(of: viewModel.state) {
            if case .loaded(let response) = viewModel.state,
               let weekStart = response.weekStartDate {
                NarrativeBadgeService.shared.markViewed(weekStart: weekStart)
            }
        }
        .fullScreenCover(isPresented: $showUpsell) {
            UpsellView(initialPage: 1) { _ in showUpsell = false }
        }
    }

    // MARK: - Header

    private var insightsHeader: some View {
        VStack(spacing: 6) {
            PhaseAnimator(InsightsView.headerColors, trigger: true) { phase in
                Image(systemName: "brain.fill")
                    .font(.title)
                    .foregroundStyle(phase)
                    .shadow(color: phase.opacity(0.5), radius: 8)
            } animation: { _ in
                .easeInOut(duration: 1.2)
            }

            Text("Progress Narratives")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            if case .loaded(let response) = viewModel.state,
               let start = response.weekStartDate,
               let end = response.weekEndDate {
                Text(InsightsView.formatDateRange(start: start, end: end))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                Text("Next available \(InsightsView.formatNextAvailable(weekEnd: end))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Locked State (legacy fallback)

    private var lockedContent: some View {
        freeNoTierContent
    }

    // MARK: - Free User, No Tier

    private var freeNoTierContent: some View {
        VStack(spacing: 20) {
            gettingStartedCard
            weeklyInsightsPremiumSection
        }
    }

    // MARK: - Free User, Tier Unlocked

    @ViewBuilder
    private func freeWithTierContent(tier: StrengthTier, response: StarterInsightResponse?) -> some View {
        VStack(spacing: 20) {
            StarterInsightCard(tier: tier, response: response, audioPlayer: audioPlayer)
            weeklyInsightsPremiumSection
        }
    }

    // MARK: - Getting Started Card

    private var gettingStartedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .foregroundStyle(Color.appAccent)
                    .font(.subheadline)
                Text("Getting Started")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Text("Unlock your Strength Tier by logging all 5 fundamental exercises to receive your first personalized insight.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appAccent)
                .frame(width: 3)
        }
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Weekly Insights Premium Section

    private var weeklyInsightsPremiumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255))
                    .font(.subheadline)
                Text("Weekly Insights")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Text("Premium")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.appAccent)
                    .clipShape(Capsule())
            }

            VStack(spacing: 12) {
                ForEach(InsightSectionStyle.allCases) { style in
                    placeholderCard(style: style)
                }
            }
            .premiumLocked(
                title: "Premium Feature",
                subtitle: "Unlock AI-powered weekly training insights with Premium.",
                ctaText: "Learn More",
                blurRadius: 6,
                showUpsell: $showUpsell
            )
        }
    }

    // MARK: - Loading State

    private var loadingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white.opacity(0.6))
            Text("Loading insights...")
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
                Text("Log at least one set to unlock your weekly insight.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

            case .setsLoggedWeekInProgress(let sundayDate):
                Text("Your insight will be ready after \(sundayDate).")
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
            Text("Generating your insights...")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Text("This usually takes about a minute.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Populated State

    @ViewBuilder
    private func populatedContent(response: WeeklyInsightsResponse) -> some View {
        // Show starter insight card for premium users who have one cached
        if let starter = viewModel.starterInsight, starter.body != nil {
            StarterInsightCard(tier: overallTier, response: starter, audioPlayer: audioPlayer)
        }

        if let sections = response.sections {
            ForEach(sections, id: \.title) { section in
                let style = InsightSectionStyle.from(title: section.title)
                InsightSectionCard(section: section, style: style, audioPlayer: audioPlayer)
            }

            // AI Disclaimer
            Text("This analysis is AI-generated and may contain inaccuracies.\nConsult a qualified professional before making changes to your training program.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.top, 16)
        }
    }

    // MARK: - Error State

    private func errorContent(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.4))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await viewModel.fetchInsights(force: true, isPremium: isPremium, hasLocalSetsThisWeek: hasLocalSetsThisWeek)
                }
            } label: {
                Text("Try Again")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.appAccent)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Placeholder Card (for blurred locked state)

    private func placeholderCard(style: InsightSectionStyle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: style.icon)
                    .foregroundStyle(style.color)
                    .font(.subheadline)
                Text(style.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

// MARK: - Starter Insight Card

struct StarterInsightCard: View {
    let tier: StrengthTier
    let response: StarterInsightResponse?
    var audioPlayer: AudioPlayerManager

    private static let amberAccent = Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255)
    private static let starterAudioTitle = "Starter Insight"

    private var isPlaying: Bool {
        audioPlayer.currentlyPlayingSectionTitle == Self.starterAudioTitle && audioPlayer.isPlaying
    }

    private var bodyText: String {
        response?.body ?? "Based on your initial lifts, you're showing solid foundation strength. Focus on consistent progressive overload across your compound movements — even small incremental increases add up significantly over time."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your First Insight")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Self.amberAccent)
                    .textCase(.uppercase)
                    .tracking(0.5)

                if response?.audioUrl != nil {
                    Spacer()
                    Button {
                        guard let urlString = response?.audioUrl,
                              let url = URL(string: urlString) else { return }
                        audioPlayer.toggle(url: url, sectionTitle: Self.starterAudioTitle)
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(tier.color)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "brain.fill")
                    .font(.title2)
                    .foregroundStyle(tier.color)
                    .shadow(color: tier.color.opacity(0.6), radius: 8)

                Text("Congratulations on reaching \(tier.title)!")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text(bodyText)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(tier.color)
                .frame(width: 3)
        }
        .background {
            ZStack {
                Color(white: 0.14)
                tier.color.opacity(0.05)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Self.amberAccent.opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: - Insight Section Card

struct InsightSectionCard: View {
    let section: InsightSection
    let style: InsightSectionStyle
    var audioPlayer: AudioPlayerManager

    private var isSectionPlaying: Bool {
        audioPlayer.currentlyPlayingSectionTitle == section.title && audioPlayer.isPlaying
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: style.icon)
                    .foregroundStyle(style.color)
                    .font(.subheadline)
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))

                if section.audioUrl != nil {
                    Spacer()
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
