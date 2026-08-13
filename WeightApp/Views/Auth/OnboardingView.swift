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
    /// Development preview, launched from More → Developer → "Replay Onboarding (Dev)".
    /// Adds Back/Next controls to page through every screen freely, bypassing per-step
    /// gating. "Replay Onboarding (Real)" passes `false` and behaves exactly like
    /// production, which is the point of having both entries.
    var isDevelopmentPreview: Bool = false

    @State private var currentPage = 0
    @State private var showControls = false

    /// The flow as an ordered list rather than a fixed count, so a screen can be added
    /// or removed without renumbering `case` labels or recomputing indices.
    /// `currentPage` is an index INTO this array, which means the later steps'
    /// `currentPage += 1` keeps working untouched.
    private enum Screen {
        case welcome, fiveLifts, progress, milestones
        case bodyProfile, startingTier
        case sessionIntent, sessionReminder

        /// Stable snake_case analytics name. Keep these fixed once shipped — renaming
        /// one splits its history in Amplitude.
        var analyticsName: String {
            switch self {
            case .welcome: return "welcome"
            case .fiveLifts: return "five_lifts"
            case .progress: return "progress"
            case .milestones: return "milestones"
            case .bodyProfile: return "body_profile"
            case .startingTier: return "starting_tier"
            case .sessionIntent: return "session_intent"
            case .sessionReminder: return "session_reminder"
            }
        }
    }

    private let screens: [Screen] = [
        .welcome, .fiveLifts, .progress, .milestones,
        .bodyProfile, .startingTier,
        .sessionIntent, .sessionReminder,
    ]

    private var totalPages: Int { screens.count }

    /// Clamped so an out-of-range index (debug nav, a stray advance) can't trap.
    private func screen(at index: Int) -> Screen {
        screens[max(0, min(index, screens.count - 1))]
    }

    private var currentScreen: Screen { screen(at: currentPage) }

    /// Last page using the SHARED dots + Continue below; later steps render their own.
    /// An absolute index on purpose — this was `totalPages - 3`, which silently hands a
    /// second Continue to the self-managing steps the moment pages are added or removed.
    /// Indices 0-3 are welcome…milestones in every configuration.
    private let lastSharedContinuePage = 3

    /// Answer to the session question. Held on-device only: it drives the local
    /// reminder and an Amplitude user property, and the backend has no consumer.
    @State private var sessionIntent: NextSessionIntent = .tomorrow

    /// Guards the shared Continue against a double-tap advancing twice. Cleared on
    /// every page change, so each page gets exactly one advance.
    @State private var isAdvancing = false
    @State private var controlsWatchdog: Task<Void, Never>?

    /// How long a concept page may withhold its Continue button before the failsafe
    /// reveals it. Well clear of the longest animation chain (~2s), so it never fires
    /// in the happy path.
    private static let controlsWatchdogSeconds: Double = 6

    /// Guarantees a way forward on the animated concept pages.
    ///
    /// `showControls` is otherwise set ONLY by a step's `onAnimationComplete`, and the
    /// Continue button is both `opacity(0)` and `allowsHitTesting(false)` until then —
    /// so if that callback never lands, the user has no exit and no visible affordance
    /// to discover. There is no back button and no skip. This makes the dead end
    /// unreachable regardless of why the callback was missed.
    private func armControlsWatchdog(for page: Int) {
        controlsWatchdog?.cancel()
        // Page 0 always shows its CTA; pages past the shared button own their own.
        guard page > 0, page <= lastSharedContinuePage else { return }
        controlsWatchdog = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.controlsWatchdogSeconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { showControls = true }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                // Page content
                Group {
                    switch currentScreen {
                    case .welcome: OnboardingWelcome()
                    case .fiveLifts: OnboardingFiveLiftsConcept(onAnimationComplete: {
                        withAnimation(.easeOut(duration: 0.4)) {
                            showControls = true
                        }
                    })
                    case .progress: OnboardingProgressConcept(onAnimationComplete: {
                        withAnimation(.easeOut(duration: 0.4)) {
                            showControls = true
                        }
                    })
                    case .milestones: OnboardingMilestonesConcept(onAnimationComplete: {
                        withAnimation(.easeOut(duration: 0.4)) {
                            showControls = true
                        }
                    })
                    // Beyond the Basics screen removed — struct definition kept commented below in case we re-enable.
                    // Change Plates removed from the flow; users set plates in Settings.
                    case .bodyProfile: OnboardingBodyProfileStep(currentPage: $currentPage, totalPages: totalPages)
                    case .startingTier: OnboardingStartingTierStep(
                        currentPage: $currentPage,
                        totalPages: totalPages,
                        // Hands off to whatever follows; completes the flow when it's last.
                        onComplete: {
                            if currentPage < screens.count - 1 {
                                withAnimation(.easeInOut(duration: 0.3)) { currentPage += 1 }
                            } else {
                                onComplete()
                            }
                        }
                    )
                    case .sessionIntent: OnboardingSessionIntentStep(
                        pageIndex: currentPage,
                        totalPages: totalPages,
                        intent: $sessionIntent
                    ) { _ in
                        // Set here rather than on the grant path, so the property exists
                        // for users who go on to deny or skip. Otherwise the intent of
                        // everyone who said no is invisible, which is the segment most
                        // worth analysing.
                        AmplitudeService.shared.setNextSessionIntent(sessionIntent.rawValue)
                        // Every answer advances now, including "Not sure yet" — the
                        // reminder screen has its own state for that case.
                        withAnimation(.easeInOut(duration: 0.3)) { currentPage += 1 }
                    }
                    case .sessionReminder: OnboardingReminderStep(
                        pageIndex: currentPage,
                        totalPages: totalPages,
                        intent: sessionIntent
                    ) { _ in
                        onComplete()
                    }
                    }
                }
                .onAppear {
                    AmplitudeService.shared.track(.onboardingStepViewed(index: currentPage, name: currentScreen.analyticsName))
                    armControlsWatchdog(for: currentPage)
                }
                .onChange(of: currentPage) { _, page in
                    isAdvancing = false
                    AmplitudeService.shared.track(.onboardingStepViewed(index: page, name: screen(at: page).analyticsName))
                    armControlsWatchdog(for: page)
                }

                Spacer()

                // Page indicators + Continue button (not shown on plates/body profile pages — they have their own)
                if currentPage <= lastSharedContinuePage {
                    VStack(spacing: 20) {
                        // Page dots (hidden on welcome screen)
                        if currentPage > 0 {
                            HStack(spacing: 8) {
                                ForEach(0..<totalPages, id: \.self) { index in
                                    Circle()
                                        .fill(index == currentPage ? Color.appAccent : Color.white.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }

                        // Continue button — different CTA on welcome
                        Button {
                            // Same double-tap latch as the self-managing steps. Reset in
                            // `.onChange(of: currentPage)` below, so each page re-arms it.
                            guard !isAdvancing else { return }
                            isAdvancing = true
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showControls = false // Reset for E1RM animation fade-in
                                currentPage += 1
                            }
                        } label: {
                            Text(currentPage == 0 ? "Let's Begin" : "Continue")
                                .font(.interSemiBold(size: 16))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.appAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 32)
                    }
                    .padding(.bottom, 50)
                    // Welcome: always visible. Animated concept pages: fade in after animation completes.
                    .opacity(currentPage == 0 || showControls ? 1 : 0)
                    // Opacity alone leaves the button hit-testable while invisible, so a
                    // tap during the fade-out would advance a second time.
                    .allowsHitTesting(currentPage == 0 || showControls)
                }
            }
        }
        .overlay(alignment: .top) {
            if isDevelopmentPreview {
                debugNavBar
            }
        }
    }

    /// Debug-only Back/Next controls to page through the whole flow (bypasses per-step gating).
    private var debugNavBar: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showControls = false
                    if currentPage > 0 { currentPage -= 1 }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .disabled(currentPage == 0)
            .opacity(currentPage == 0 ? 0.3 : 1)

            Spacer()

            Text("\(currentPage + 1) / \(totalPages)")
                .font(.inter(size: 13))
                .foregroundStyle(.white.opacity(0.5))

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showControls = false
                    if currentPage < totalPages - 1 { currentPage += 1 }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .disabled(currentPage == totalPages - 1)
            .opacity(currentPage == totalPages - 1 ? 0.3 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Screen 1: Welcome

private struct OnboardingWelcome: View {
    var tagline: String = "Get stronger on the lifts that matter."

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            Image("LiftTheBullIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundStyle(Color.appAccent)
                .shadow(color: Color.appAccent.opacity(0.3), radius: 20, x: 0, y: 0)

            Spacer()
                .frame(height: 32)

            // Welcome
            Text("LIFT THE BULL")
                .font(.bebasNeue(size: 38))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Spacer()
                .frame(height: 12)

            // Setup message
            Text(tagline)
                .font(.inter(size: 17))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }
}

// MARK: - Screen 2: Five Fundamental Lifts

private struct OnboardingFiveLiftsConcept: View {
    var onAnimationComplete: (() -> Void)? = nil

    private let exercises = TrendsCalculator.fundamentalExercises

    // Fake tier scenario: all tier colors represented, overall = advanced (lowest)
    private let targetProgress: [CGFloat] = [0.90, 0.65, 0.80, 0.52, 0.76]
    private let exerciseTiers: [StrengthTier] = [.legend, .advanced, .elite, .intermediate, .advanced]
    private let overallTier: StrengthTier = .advanced

    /// Icons that render visually larger than the others, so we shrink them slightly to match.
    private let smallIconExercises: Set<String> = ["DeadliftIcon", "SquatIcon", "BenchPressIcon"]

    /// Per-icon display size (visual balancing across the five lift icons).
    private func iconSize(for icon: String) -> CGFloat {
        if icon == "OverheadPressIcon" { return 50 }
        if smallIconExercises.contains(icon) { return 46 }
        return 48
    }

    @State private var animatedExercise: Int = 0
    @State private var barProgress: [CGFloat] = [0, 0, 0, 0, 0]
    @State private var showOverallTier: Bool = false
    @State private var animationComplete: Bool = false
    @State private var showHeader: Bool = false
    @State private var showSubtitle: Bool = false
    @State private var showExerciseCard: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 12) {
                Text("Five Lifts. Total Strength.")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(showHeader ? 1 : 0)
                    .offset(y: showHeader ? 0 : 16)

                (Text("Master these. ").foregroundColor(.white.opacity(0.7))
                    + Text("Everything else follows.").foregroundColor(.appAccent))
                    .font(.inter(size: 17))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(showSubtitle ? 1 : 0)
                    .offset(y: showSubtitle ? 0 : 16)
            }

            Spacer()
                .frame(height: 32)

            // Exercise list card (contains bars + overall tier)
            VStack(spacing: 0) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    HStack(spacing: 18) {
                        Image(exercise.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconSize(for: exercise.icon), height: iconSize(for: exercise.icon))
                            .frame(width: 50, height: 50)
                            .foregroundStyle(barProgress[index] > 0 ? Color.appAccent : .white.opacity(0.35))

                        Text(exercise.name)
                            .font(.inter(size: 16))
                            .foregroundStyle(.white)

                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)

                    if index < exercises.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                            .padding(.leading, 88)
                            .padding(.trailing, 20)
                    }
                }

                // FEATURE FLAG: divider + overall-tier reveal hidden so the
                // onboarding card shows only the five exercise rows. To
                // re-enable, uncomment the block below. `showOverallTier`
                // state is still set in runAnimation() so the animation
                // logic is preserved; only the visual is gated here.
                /*
                // Divider before overall tier
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                // Overall tier reveal (inside the card)
                VStack(spacing: 8) {
                    Text("STRENGTH TIER")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(1.5)

                    HStack(spacing: 8) {
                        Image(overallTier.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(overallTier.color)

                        Text(overallTier.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(overallTier.color)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .opacity(showOverallTier ? 1 : 0)
                .animation(.easeOut(duration: 0.4), value: showOverallTier)
                */
            }
            .padding(.bottom, 12)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            .opacity(showExerciseCard ? 1 : 0)

            Spacer()
                .frame(height: 18)

            (Text("Short list. ").foregroundColor(.white.opacity(0.55))
                + Text("Full body.").foregroundColor(.appAccent))
                .font(.inter(size: 15))
                .multilineTextAlignment(.center)
                .opacity(showExerciseCard ? 1 : 0)
        }
        .onAppear {
            runAnimation()
        }
    }

    private func runAnimation() {
        Task {
            // Header → subtitle → exercise card, each fading up in sequence
            // before any bars start animating. Pauses between steps let each
            // element land clearly so the sequence reads as deliberate.
            withAnimation(.easeOut(duration: 0.55)) {
                showHeader = true
            }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.55)) {
                showSubtitle = true
            }
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeOut(duration: 0.45)) {
                showExerciseCard = true
            }
            try? await Task.sleep(for: .milliseconds(450))

            // Original initial delay before the bars kick in
            try? await Task.sleep(for: .milliseconds(300))
            // All five bars animate together as a single cohesive block.
            withAnimation(.easeOut(duration: 0.4)) {
                for i in 0..<5 {
                    barProgress[i] = targetProgress[i]
                }
            }
            try? await Task.sleep(for: .milliseconds(700))
            showOverallTier = true
            withAnimation(.easeOut(duration: 0.3)) {
                animationComplete = true
            }
            onAnimationComplete?()
        }
    }

}

// MARK: - Screen 3: Your Estimated 1RM

private struct OnboardingE1RMConcept: View {
    var onAnimationComplete: (() -> Void)? = nil

    @State private var visibleBars: Int = 0
    @State private var showPRIndicator: Bool = false

    private let bars: [(height: CGFloat, color: Color)] = [
        (0.30, .setEasy),
        (0.35, .setEasy),
        (0.50, .setModerate),
        (0.55, .setModerate),
        (0.70, .setHard),
        (1.00, .appAccent),
    ]

    private let maxBarHeight: CGFloat = 120
    private let barWidth: CGFloat = 32
    private let barSpacing: CGFloat = 12
    // Space reserved above bars for the PR indicator
    private let indicatorHeight: CGFloat = 56

    private let legendEntries: [(color: Color, label: String, threshold: Int)] = [
        (.setEasy, "Easy", 1),
        (.setModerate, "Moderate", 3),
        (.setHard, "Hard", 5),
        (.appAccent, "PR", 6),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 12) {
                Text("Track Your Estimated 1-Rep Max")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("New PRs are identified from each logged set.")
                    .font(.inter(size: 17))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 32)

            // Animated card
            VStack(spacing: 0) {
                // Bars with PR indicator above last bar
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(0..<bars.count, id: \.self) { index in
                        VStack(spacing: 10) {
                            // PR indicator sits above the last bar only
                            if index == bars.count - 1 {
                                VStack(spacing: 4) {
                                    Image("LiftTheBullIcon")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 24, height: 24)
                                        .foregroundStyle(Color.appAccent)
                                        .shadow(color: Color.appAccent.opacity(0.5), radius: 8, x: 0, y: 0)

                                    VStack(spacing: 1) {
                                        Text("New")
                                            .font(.inter(size: 9))
                                            .foregroundStyle(Color.appAccent)
                                        Text("Estimated 1RM")
                                            .font(.inter(size: 9))
                                            .foregroundStyle(Color.appAccent)
                                    }
                                    .fixedSize()
                                }
                                .frame(width: barWidth, height: indicatorHeight)
                                .opacity(showPRIndicator ? 1 : 0)
                                .animation(.easeOut(duration: 0.4), value: showPRIndicator)
                            } else {
                                // Invisible spacer matching indicator height to keep layout fixed
                                Color.clear
                                    .frame(width: barWidth, height: indicatorHeight)
                            }

                            RoundedRectangle(cornerRadius: 4)
                                .fill(bars[index].color)
                                .frame(width: barWidth, height: bars[index].height * maxBarHeight)
                                .opacity(index < visibleBars ? 1 : 0)
                                .animation(.easeOut(duration: 0.4), value: visibleBars)
                        }
                    }
                }
                .frame(height: maxBarHeight + indicatorHeight + 4, alignment: .bottom)

                // Legend — all entries always laid out, opacity animated
                HStack(spacing: 24) {
                    ForEach(legendEntries, id: \.label) { entry in
                        LegendDot(color: entry.color, label: entry.label)
                            .opacity(visibleBars >= entry.threshold ? 1 : 0)
                            .animation(.easeOut(duration: 0.3), value: visibleBars)
                    }
                }
                .frame(height: 16)
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            .onAppear {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        Task {
            // Stagger bars at 0.2s intervals
            for i in 1...bars.count {
                try? await Task.sleep(for: .milliseconds(200))
                visibleBars = i
            }

            // PR indicator after 0.5s pause
            try? await Task.sleep(for: .milliseconds(500))
            showPRIndicator = true

            // Notify parent that animation is done
            onAnimationComplete?()
        }
    }
}

// MARK: - Screen 4: Track Your Progress

private struct OnboardingProgressConcept: View {
    var onAnimationComplete: (() -> Void)? = nil

    @State private var visibleBars: Int = 0
    @State private var showPRIndicator: Bool = false
    @State private var showE1RM: Bool = false
    @State private var displayedE1RM: Int = 185
    @State private var showDelta: Bool = false
    @State private var animationComplete: Bool = false
    @State private var showHeader: Bool = false
    @State private var showSubtitle: Bool = false
    @State private var showCard: Bool = false

    private let bars: [(height: CGFloat, color: Color)] = [
        (0.30, .setEasy),
        (0.35, .setEasy),
        (0.50, .setModerate),
        (0.55, .setModerate),
        (0.70, .setHard),
        (1.00, .appAccent),
    ]

    private let maxBarHeight: CGFloat = 160
    private let barWidth: CGFloat = 32
    private let barSpacing: CGFloat = 12
    private let indicatorHeight: CGFloat = 56

    private let legendEntries: [(color: Color, label: String, threshold: Int)] = [
        (.setEasy, "Easy", 1),
        (.setModerate, "Moderate", 3),
        (.setHard, "Hard", 5),
        (.appAccent, "Progress", 6),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 12) {
                Text("PROGRESS, BUILT IN")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(showHeader ? 1 : 0)
                    .offset(y: showHeader ? 0 : 16)

                Text("Choose \(Text("Progress Sets").foregroundColor(.appAccent)) built to\nmove your strength forward.")
                    .font(.inter(size: 17))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(showSubtitle ? 1 : 0)
                    .offset(y: showSubtitle ? 0 : 16)
            }

            Spacer()
                .frame(height: 32)

            // Animated card — matching Five Lifts card dimensions
            VStack(spacing: 0) {
                // Bars with overlaid e1RM number
                ZStack(alignment: .topLeading) {
                    // Bars with PR indicator above last bar
                    HStack(alignment: .bottom, spacing: barSpacing) {
                        ForEach(0..<bars.count, id: \.self) { index in
                            VStack(spacing: 10) {
                                if index == bars.count - 1 {
                                    VStack(spacing: 4) {
                                        Image("LiftTheBullIcon")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 24, height: 24)
                                            .foregroundStyle(Color.appAccent)
                                            .shadow(color: Color.appAccent.opacity(0.5), radius: 8, x: 0, y: 0)

                                        VStack(spacing: 1) {
                                            Text("New")
                                                .font(.inter(size: 9))
                                                .foregroundStyle(Color.appAccent)
                                            Text("Estimated 1RM")
                                                .font(.inter(size: 9))
                                                .foregroundStyle(Color.appAccent)
                                        }
                                        .fixedSize()
                                    }
                                    .frame(width: barWidth, height: indicatorHeight)
                                    .opacity(showPRIndicator ? 1 : 0)
                                    .animation(.easeOut(duration: 0.4), value: showPRIndicator)
                                } else {
                                    Color.clear
                                        .frame(width: barWidth, height: indicatorHeight)
                                }

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(bars[index].color)
                                    .frame(width: barWidth, height: bars[index].height * maxBarHeight)
                                    .opacity(index < visibleBars ? 1 : 0)
                                    .animation(.easeOut(duration: 0.4), value: visibleBars)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: maxBarHeight + indicatorHeight + 4, alignment: .bottom)

                    // Hero e1RM number overlaid in upper-left, shifted diagonally into bar area
                    HStack(alignment: .center, spacing: 6) {
                        Text("\(displayedE1RM)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())

                        VStack(alignment: .leading, spacing: 3) {
                            Text("e1RM")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.appAccent)

                            // Green delta indicator below e1RM label
                            HStack(spacing: 3) {
                                Image(systemName: "triangle.fill")
                                    .font(.system(size: 8))
                                Text("+10")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.green)
                            .opacity(showDelta ? 1 : 0)
                            .animation(.easeOut(duration: 0.4), value: showDelta)
                        }
                    }
                    .padding(.top, indicatorHeight - 16)
                    .padding(.leading, 44)
                    .opacity(showE1RM ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: showE1RM)
                }

                // Legend
                HStack(spacing: 24) {
                    ForEach(legendEntries, id: \.label) { entry in
                        LegendDot(color: entry.color, label: entry.label)
                            .opacity(visibleBars >= entry.threshold ? 1 : 0)
                            .animation(.easeOut(duration: 0.3), value: visibleBars)
                    }
                }
                .frame(height: 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            .overlay(alignment: .bottomTrailing) {
                if animationComplete {
                    Button {
                        replayAnimation()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 28)
                    .padding(.bottom, 4)
                    .transition(.opacity)
                }
            }
            .opacity(showCard ? 1 : 0)
            .onAppear {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        Task {
            // Header → subtitle → card fade-up before the existing visualization
            // animation starts. Pacing mirrors OnboardingFiveLiftsConcept.
            withAnimation(.easeOut(duration: 0.55)) {
                showHeader = true
            }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.55)) {
                showSubtitle = true
            }
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeOut(duration: 0.45)) {
                showCard = true
            }
            try? await Task.sleep(for: .milliseconds(250))

            // Show e1RM number + first bar simultaneously
            showE1RM = true
            visibleBars = 1

            for i in 2...bars.count {
                try? await Task.sleep(for: .milliseconds(200))
                visibleBars = i
            }

            // Enable the parent's Continue button the moment the last bar
            // lands — the PR indicator + e1RM roll-up that follow are
            // flourish and shouldn't hold the user up.
            onAnimationComplete?()

            try? await Task.sleep(for: .milliseconds(300))
            showPRIndicator = true

            // Animate e1RM number rolling up from 185 → 195
            try? await Task.sleep(for: .milliseconds(250))
            for value in 186...195 {
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.easeOut(duration: 0.2)) {
                    displayedE1RM = value
                }
            }

            // Show green delta indicator
            try? await Task.sleep(for: .milliseconds(200))
            showDelta = true

            withAnimation(.easeOut(duration: 0.3)) {
                animationComplete = true
            }
        }
    }

    private func replayAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            visibleBars = 0
            showPRIndicator = false
            showE1RM = false
            displayedE1RM = 185
            showDelta = false
            animationComplete = false
            showHeader = false
            showSubtitle = false
            showCard = false
        }
        startAnimation()
    }
}

// MARK: - Screen 1 (Original Chart Version — commented out for reference)
/*
private struct OnboardingE1RMConcept_ChartVersion: View {
    @State private var scrollOffset: CGFloat = 0
    private var sampleData: [(value: Double, color: Color)] {
        [
            (155, .setEasy), (158, .setEasy), (162, .setModerate), (165, .setModerate),
            (167, .setHard), (169, .setNearMax), (170, .appAccent),
            (160, .setEasy), (164, .setModerate), (168, .setHard),
            (171, .setHard), (173, .setNearMax), (175, .appAccent),
            (165, .setEasy), (169, .setEasy), (173, .setModerate),
            (176, .setHard), (179, .setNearMax), (182, .appAccent),
            (172, .setEasy), (176, .setModerate), (180, .setModerate),
            (183, .setHard), (186, .setNearMax), (188, .appAccent),
            (178, .setEasy), (182, .setModerate), (186, .setHard),
            (189, .setHard), (192, .setNearMax), (195, .appAccent),
            (184, .setEasy), (188, .setEasy), (192, .setModerate),
            (196, .setHard), (199, .setNearMax), (202, .appAccent),
            (190, .setEasy), (194, .setModerate), (198, .setModerate),
            (202, .setHard), (205, .setNearMax), (208, .appAccent),
            (196, .setEasy), (200, .setEasy), (204, .setModerate),
            (208, .setHard), (212, .setNearMax), (215, .appAccent),
            (202, .setEasy), (206, .setModerate), (210, .setModerate),
            (214, .setHard), (218, .setNearMax), (222, .appAccent),
            (208, .setEasy), (212, .setEasy), (216, .setModerate),
            (220, .setHard), (225, .setNearMax), (228, .appAccent),
            (214, .setEasy),
        ]
    }
    private let barWidth: CGFloat = 10
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("Your Estimated 1RM").font(.bebasNeue(size: 34)).foregroundStyle(.white).multilineTextAlignment(.center)
                Text("You never need to max out").font(.inter(size: 17)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            Spacer().frame(height: 24)
            VStack(alignment: .leading, spacing: 12) {
                OnboardingBullet(text: "The app estimates your max strength from every set you log — using weight and reps")
                OnboardingBullet(text: "A set of 5 at 200 lbs tells the app as much as a single at 230")
                OnboardingBullet(text: "When a set produces a higher estimate than your previous best, that's a PR")
            }.padding(.horizontal, 32)
            Spacer().frame(height: 24)
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .trailing, spacing: 0) { Text("225"); Spacer(); Text("200"); Spacer(); Text("175"); Spacer(); Text("150") }
                        .font(.inter(size: 10)).foregroundStyle(.white.opacity(0.5)).frame(width: 28, height: 140).padding(.trailing, 4)
                    GeometryReader { _ in
                        Chart {
                            ForEach(0..<sampleData.count, id: \.self) { index in
                                let data = sampleData[index]
                                RectangleMark(xStart: .value("Start", Double(index)), xEnd: .value("End", Double(index) + 0.75), yStart: .value("Base", 140), yEnd: .value("Height", data.value))
                                    .foregroundStyle(LinearGradient(colors: [data.color, data.color.opacity(0.6)], startPoint: .top, endPoint: .bottom)).cornerRadius(2)
                            }
                        }.chartXAxis(.hidden).chartYAxis(.hidden).chartXScale(domain: 0...Double(sampleData.count)).chartYScale(domain: 140...230)
                            .frame(width: CGFloat(sampleData.count) * barWidth, height: 140).offset(x: -scrollOffset)
                    }.frame(height: 140).clipped()
                }
                HStack(spacing: 10) { LegendDot(color: .setEasy, label: "Easy"); LegendDot(color: .setModerate, label: "Moderate"); LegendDot(color: .setHard, label: "Hard"); LegendDot(color: .setNearMax, label: "Near Max"); LegendDot(color: .appAccent, label: "PR") }.padding(.top, 16)
            }.padding(20).background(Color(white: 0.12)).clipShape(RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 24)
                .onAppear { let totalWidth = CGFloat(sampleData.count) * barWidth; withAnimation(.linear(duration: 20).repeatForever(autoreverses: true)) { scrollOffset = totalWidth - 280 } }
        }
    }
}
*/

// MARK: - Screen 3: Effort-Based Training

private struct OnboardingEffortTraining: View {
    var onAnimationComplete: (() -> Void)? = nil

    @State private var currentPlanIndex: Int = 0
    @State private var filledTiles: Int = 0
    @State private var showPRIndicator: Bool = false
    @State private var showNextButton: Bool = false
    @State private var highlightPlanName: Bool = false
    @State private var isAnimating: Bool = false
    @State private var nextButtonScale: CGFloat = 1.0

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    // Set plans to cycle through (all 6 or fewer tiles)
    private let plans: [(name: String, tiles: [(weight: String, reps: String, effort: String)])] = [
        ("Standard", [
            ("135", "10", "easy"), ("155", "8", "easy"),
            ("185", "6", "moderate"), ("195", "6", "moderate"),
            ("215", "5", "hard"), ("225", "5", "pr"),
        ]),
        ("Pyramid", [
            ("135", "10", "easy"), ("185", "6", "moderate"),
            ("215", "5", "hard"), ("225", "5", "pr"),
            ("205", "6", "hard"), ("175", "8", "moderate"),
        ]),
        ("Top Set + Backoff", [
            ("135", "10", "easy"), ("185", "6", "moderate"),
            ("215", "5", "hard"), ("225", "5", "pr"),
            ("185", "6", "moderate"), ("175", "8", "moderate"),
        ]),
        ("Maintenance", [
            ("185", "6", "moderate"), ("195", "6", "moderate"),
            ("215", "5", "hard"),
        ]),
        ("Deload", [
            ("115", "12", "easy"), ("135", "10", "easy"),
            ("145", "10", "easy"),
        ]),
    ]

    private var currentPlan: (name: String, tiles: [(weight: String, reps: String, effort: String)]) {
        plans[currentPlanIndex]
    }

    private var hasPR: Bool {
        currentPlan.tiles.contains { $0.effort == "pr" }
    }

    private static func effortColor(for effort: String) -> Color {
        switch effort {
        case "easy": return .setEasy
        case "moderate": return .setModerate
        case "hard": return .setHard
        case "pr": return .appAccent
        default: return .setEasy
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 12) {
                Text("Effort-Based Training")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Each session follows a planned sequence of effort levels.")
                    .font(.inter(size: 17))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 32)

            // Mock check-in session card
            VStack(spacing: 10) {
                // Header + tiles share same width
                let tileRowWidth: CGFloat = 6 * 42 + 5 * 6 // 282pt

                // Header row: "Today" label + set plan name pill
                HStack(spacing: 8) {
                    Text("Today")
                        .font(.inter(size: 11))
                        .foregroundStyle(.white.opacity(0.5))

                    Spacer()

                    // Set plan name pill
                    HStack(spacing: 4) {
                        Text("\(currentPlan.name) Session")
                            .font(.inter(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(highlightPlanName ? Color.appAccent : .white.opacity(0.5))
                    .animation(.easeOut(duration: 0.3), value: highlightPlanName)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.16)))

                    // Stack icon (matching real UI)
                    Image(systemName: "square.stack")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .frame(width: tileRowWidth, height: 22)
                .animation(.easeInOut(duration: 0.3), value: currentPlanIndex)

                // Tile row — fixed height, aligned with header
                HStack(spacing: 6) {
                    ForEach(0..<6, id: \.self) { index in
                        if index < currentPlan.tiles.count {
                            let tile = currentPlan.tiles[index]
                            let color = Self.effortColor(for: tile.effort)

                            ZStack {
                                // Empty state: border only
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.clear)
                                    .frame(width: 42, height: 42)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(color, lineWidth: 1.5)
                                    )

                                // Filled state
                                VStack(spacing: 2) {
                                    Text(tile.weight)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(tile.reps)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                .frame(width: 42, height: 42)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(color.opacity(0.3))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(color, lineWidth: 1.5)
                                )
                                .opacity(index < filledTiles ? 1 : 0)
                                .animation(.easeOut(duration: 0.4), value: filledTiles)
                            }
                        } else {
                            // Empty placeholder for plans with fewer than 6 tiles
                            Color.clear
                                .frame(width: 42, height: 42)
                        }
                    }
                }
                .frame(height: 46)

                // PR indicator row — fixed height
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image("LiftTheBullIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(Color.appAccent)
                            .shadow(color: Color.appAccent.opacity(0.5), radius: 6, x: 0, y: 0)

                        Text("New Estimated 1RM")
                            .font(.inter(size: 9))
                            .foregroundStyle(Color.appAccent)
                    }
                    .opacity(showPRIndicator ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: showPRIndicator)
                    Spacer()
                }
                .frame(height: 36)

                // Legend — always visible
                HStack(spacing: 24) {
                    LegendDot(color: .setEasy, label: "Easy")
                    LegendDot(color: .setModerate, label: "Moderate")
                    LegendDot(color: .setHard, label: "Hard")
                    LegendDot(color: .appAccent, label: "PR")
                }
                .frame(height: 16)
            }
            .padding(20)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            .onAppear {
                animateCurrentPlan()
            }

            // "Next Example" button — centered between card and continue
            Spacer()

            Button {
                hapticFeedback.impactOccurred()
                // Bounce animation
                withAnimation(.spring(duration: 0.3, bounce: 0.4)) {
                    nextButtonScale = 0.85
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(duration: 0.3, bounce: 0.4)) {
                        nextButtonScale = 1.0
                    }
                }
                advanceToNextPlan()
            } label: {
                Text("Next\nExample")
                    .font(.interSemiBold(size: 14))
                    .foregroundStyle(Color.appAccent)
                    .multilineTextAlignment(.center)
                    .frame(width: 90, height: 90)
                    .background(
                        Circle()
                            .fill(Color.appAccent.opacity(0.12))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.appAccent.opacity(0.4), lineWidth: 1.5)
                    )
                    .scaleEffect(nextButtonScale)
            }
            .buttonStyle(.plain)
            .opacity(showNextButton ? 1 : 0)
            .animation(.easeOut(duration: 0.4), value: showNextButton)

            Spacer()
        }
    }

    private func animateCurrentPlan() {
        guard !isAnimating else { return }
        isAnimating = true

        Task {
            // Reset for current plan
            filledTiles = 0
            showPRIndicator = false

            // Brief pause before starting fills
            try? await Task.sleep(for: .milliseconds(200))

            // Fill tiles one by one
            let tileCount = currentPlan.tiles.count
            for i in 1...tileCount {
                try? await Task.sleep(for: .milliseconds(200))
                filledTiles = i
            }

            // Show PR indicator if plan has a PR tile
            if hasPR {
                try? await Task.sleep(for: .milliseconds(500))
                showPRIndicator = true
            }

            // Show next button slightly before continue button
            withAnimation(.easeOut(duration: 0.4)) {
                showNextButton = true
            }
            try? await Task.sleep(for: .milliseconds(300))
            onAnimationComplete?()

            isAnimating = false
        }
    }

    private func advanceToNextPlan() {
        guard !isAnimating else { return }

        // Clear current tiles
        withAnimation(.easeInOut(duration: 0.3)) {
            filledTiles = 0
            showPRIndicator = false
        }

        Task {
            try? await Task.sleep(for: .milliseconds(400))

            currentPlanIndex = (currentPlanIndex + 1) % plans.count

            // Flash plan name amber briefly
            highlightPlanName = true
            animateCurrentPlan()
            try? await Task.sleep(for: .seconds(1))
            highlightPlanName = false
        }
    }
}

// MARK: - Screen 3 (Original Effort Training — commented out for reference)
/*
private struct OnboardingEffortTraining_ScrollVersion: View {
    @State private var scrollOffset: CGFloat = 0
    private var todaySets: [(reps: String, weight: String, color: Color)] {
        [("10", "135", .setEasy), ("8", "155", .setEasy), ("8", "175", .setModerate), ("6", "195", .setModerate),
         ("6", "205", .setHard), ("5", "215", .setHard), ("4", "225", .setNearMax), ("3", "235", .setNearMax),
         ("2", "245", .appAccent), ("6", "205", .setHard), ("8", "185", .setModerate), ("10", "165", .setEasy),
         ("8", "175", .setModerate), ("6", "195", .setHard), ("5", "210", .setNearMax), ("3", "230", .appAccent)]
    }
    private var previousSets: [(reps: String, weight: String, color: Color)] {
        [("12", "115", .setEasy), ("10", "135", .setEasy), ("8", "155", .setModerate), ("8", "165", .setModerate),
         ("6", "185", .setHard), ("6", "195", .setHard), ("5", "205", .setNearMax), ("4", "215", .setNearMax),
         ("3", "225", .appAccent), ("6", "195", .setHard), ("8", "175", .setModerate), ("10", "155", .setEasy),
         ("8", "165", .setModerate), ("6", "185", .setHard), ("4", "210", .setNearMax), ("2", "225", .appAccent)]
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("Effort-Based Training").font(.bebasNeue(size: 34)).foregroundStyle(.white).multilineTextAlignment(.center)
                Text("Each session follows a plan").font(.inter(size: 17)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            Spacer().frame(height: 24)
            VStack(alignment: .leading, spacing: 12) {
                OnboardingBullet(text: "Sessions escalate in effort: warmup → moderate → hard → progress attempt")
                OnboardingBullet(text: "The colored tiles on the Log Set screen represent your plan for the session")
                OnboardingBullet(text: "Tap any tile for a weight and rep suggestion")
            }.padding(.horizontal, 32)
            Spacer().frame(height: 24)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today").font(.interSemiBold(size: 12)).foregroundStyle(.white.opacity(0.7))
                    GeometryReader { _ in HStack(spacing: 6) { ForEach(0..<todaySets.count, id: \.self) { index in let set = todaySets[index]; SetSquareOnboarding(reps: set.reps, weight: set.weight, color: set.color) } }.offset(x: -scrollOffset) }.frame(height: 42).clipped()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Previous Day").font(.interSemiBold(size: 12)).foregroundStyle(.white.opacity(0.7))
                    GeometryReader { _ in HStack(spacing: 6) { ForEach(0..<previousSets.count, id: \.self) { index in let set = previousSets[index]; SetSquareOnboarding(reps: set.reps, weight: set.weight, color: set.color) } }.offset(x: -scrollOffset) }.frame(height: 42).clipped()
                }
                HStack(spacing: 10) { LegendDot(color: .setEasy, label: "Easy"); LegendDot(color: .setModerate, label: "Moderate"); LegendDot(color: .setHard, label: "Hard"); LegendDot(color: .setNearMax, label: "Near Max"); LegendDot(color: .appAccent, label: "PR") }.padding(.top, 12)
            }.padding(20).background(Color(white: 0.12)).clipShape(RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 24)
                .onAppear { withAnimation(.linear(duration: 40).repeatForever(autoreverses: true)) { scrollOffset = 450 } }
        }
    }
}
*/

// MARK: - Screen 3: Progress Options

private struct OnboardingProgressOptions: View {
    @State private var scrollOffset: CGFloat = 0

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
            // Title
            VStack(spacing: 12) {
                Text("Achievable Progress")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Follow weight and rep options that can move your e1RM forward.")
                    .font(.inter(size: 17))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 32)

            // Suggestions visualization
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
                GeometryReader { _ in
                    VStack(spacing: 8) {
                        ForEach(0..<sampleSuggestions.count, id: \.self) { index in
                            OnboardingSuggestionRow(suggestion: sampleSuggestions[index], isHighlighted: index == sampleSuggestions.count - 1)
                        }
                    }
                    .offset(y: -scrollOffset)
                }
                .frame(height: 140)
                .clipped()
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            .onAppear {
                withAnimation(.linear(duration: 90).repeatForever(autoreverses: true)) {
                    scrollOffset = 1100
                }
            }
        }
    }
}


// MARK: - Screen 4: Milestones That Matter

private struct OnboardingMilestonesConcept: View {
    var onAnimationComplete: (() -> Void)?

    private let exercises = TrendsCalculator.fundamentalExercises
    private let tiers: [StrengthTier] = [.novice, .beginner, .intermediate, .advanced, .elite, .legend]

    private let startE1RMs = [135, 115, 95, 85, 65]
    private let e1rmIncrements = [40, 35, 25, 20, 15]

    private let roundOrders: [[Int]] = [
        [2, 0, 4, 1, 3],
        [1, 3, 0, 4, 2],
        [4, 2, 3, 0, 1],
        [0, 1, 2, 3, 4],
        [3, 4, 1, 2, 0],
    ]

    @State private var exerciseTiers: [Int] = [0, 0, 0, 0, 0]
    @State private var exerciseProgress: [CGFloat] = [0, 0, 0, 0, 0]
    @State private var exerciseE1RMs: [Int] = [135, 115, 95, 85, 65]
    @State private var overallTierIndex: Int = 0
    @State private var animationComplete = false
    @State private var animationTask: Task<Void, Never>?
    @State private var showHeader: Bool = false
    @State private var showSubtitle: Bool = false
    @State private var showCard: Bool = false

    private let badgeSize: CGFloat = 48

    private var tierLegend: some View {
        let topRow = Array(tiers.prefix(3))
        let bottomRow = Array(tiers.suffix(3))
        return VStack(spacing: 8) {
            HStack(spacing: 16) {
                ForEach(topRow, id: \.rawValue) { tierLegendItem($0) }
            }
            HStack(spacing: 16) {
                ForEach(bottomRow, id: \.rawValue) { tierLegendItem($0) }
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

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 12) {
                Text("NOVICE TO LEGEND")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(showHeader ? 1 : 0)
                    .offset(y: showHeader ? 0 : 16)

                (Text("Your ").foregroundColor(.white.opacity(0.7))
                    + Text("Strength Tier").foregroundColor(.appAccent)
                    + Text(" climbs\nwhen all five lifts do.").foregroundColor(.white.opacity(0.7)))
                    .font(.inter(size: 17))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(showSubtitle ? 1 : 0)
                    .offset(y: showSubtitle ? 0 : 16)
            }

            Spacer()
                .frame(height: 32)

            // Card
            VStack(spacing: 0) {
                // Overall tier
                VStack(spacing: 8) {
                    Text("STRENGTH TIER")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(1.5)

                    HStack(spacing: 8) {
                        Image(tiers[overallTierIndex].icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(tiers[overallTierIndex].color)

                        Text(tiers[overallTierIndex].title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(tiers[overallTierIndex].color)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<5, id: \.self) { i in
                        milestoneColumn(index: i)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 28)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                // Strength tier legend (inside the card)
                tierLegend
                    .padding(.vertical, 16)
            }
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            .overlay(alignment: .bottomTrailing) {
                if animationComplete {
                    Button {
                        replayAnimation()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 28)
                    .padding(.bottom, 4)
                    .transition(.opacity)
                }
            }
            .opacity(showCard ? 1 : 0)
            .onAppear { startAnimation() }
        }
    }

    @ViewBuilder
    private func milestoneColumn(index i: Int) -> some View {
        let tierIndex = exerciseTiers[i]
        let achievedTier = tiers[tierIndex]
        let isInProgress = exerciseProgress[i] > 0
        let displayColor = isInProgress ? tiers[min(tierIndex + 1, 5)].color : achievedTier.color

        VStack(spacing: 8) {
            // Milestone circle
            ZStack {
                if isInProgress {
                    // In-progress: background ring + progress arc
                    let nextColor = tiers[min(tierIndex + 1, 5)].color

                    Circle()
                        .stroke(nextColor.opacity(0.25), lineWidth: 2.5)
                        .frame(width: badgeSize, height: badgeSize)

                    Circle()
                        .trim(from: 0, to: exerciseProgress[i])
                        .stroke(nextColor.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: badgeSize, height: badgeSize)
                        .rotationEffect(.degrees(-90))
                } else {
                    // Achieved: filled circle + stroke + icon
                    Circle()
                        .fill(achievedTier.color.opacity(0.2))
                        .frame(width: badgeSize, height: badgeSize)

                    Circle()
                        .stroke(achievedTier.color.opacity(0.7), lineWidth: 2.5)
                        .frame(width: badgeSize, height: badgeSize)

                    if tierIndex == 5 {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(achievedTier.color)
                    } else {
                        Image(exercises[i].icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .foregroundStyle(achievedTier.color)
                    }
                }
            }
            .frame(width: badgeSize, height: badgeSize)

            // Exercise name
            Text(shortExerciseName(exercises[i].name))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(displayColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func shortExerciseName(_ name: String) -> String {
        switch name {
        case "Overhead Press": return "OHP"
        case "Bench Press": return "Bench"
        case "Barbell Rows": return "Row"
        default: return name
        }
    }

    private func startAnimation() {
        animationTask?.cancel()
        animationTask = Task {
            withAnimation(.easeOut(duration: 0.55)) { showHeader = true }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.55)) { showSubtitle = true }
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeOut(duration: 0.45)) { showCard = true }
            try? await Task.sleep(for: .milliseconds(450))

            // Initial pause
            try? await Task.sleep(for: .milliseconds(300))

            for round in 0..<5 {
                guard !Task.isCancelled else { return }
                let order = roundOrders[round]

                for (exerciseCount, exerciseIndex) in order.enumerated() {
                    guard !Task.isCancelled else { return }

                    let targetE1RM = startE1RMs[exerciseIndex] + e1rmIncrements[exerciseIndex] * (round + 1)
                    let currentE1RMLocalCache = exerciseE1RMs[exerciseIndex]
                    let steps = 8
                    let stepDuration: UInt64 = 75

                    // Animate progress ring and e1RM simultaneously
                    for step in 1...steps {
                        guard !Task.isCancelled else { return }
                        try? await Task.sleep(for: .milliseconds(stepDuration))
                        let fraction = CGFloat(step) / CGFloat(steps)
                        let interpolatedE1RM = currentE1RMLocalCache + Int(Double(targetE1RM - currentE1RMLocalCache) * Double(fraction))
                        withAnimation(.easeOut(duration: 0.15)) {
                            exerciseProgress[exerciseIndex] = fraction
                            exerciseE1RMs[exerciseIndex] = interpolatedE1RM
                        }
                    }

                    // Complete: advance tier, reset progress
                    try? await Task.sleep(for: .milliseconds(50))
                    withAnimation(.easeOut(duration: 0.2)) {
                        exerciseTiers[exerciseIndex] += 1
                        exerciseProgress[exerciseIndex] = 0
                    }

                    // Fire callback early — after 1st exercise in round 0
                    if round == 0 && exerciseCount == 0 {
                        onAnimationComplete?()
                    }

                    // Pause between exercises
                    try? await Task.sleep(for: .milliseconds(150))
                }

                // Advance overall tier after all exercises in this round complete
                withAnimation(.easeOut(duration: 0.2)) {
                    overallTierIndex = exerciseTiers.min() ?? 0
                }

                // Pause between rounds
                try? await Task.sleep(for: .milliseconds(200))
            }

            withAnimation(.easeOut(duration: 0.3)) {
                animationComplete = true
            }
        }
    }

    private func replayAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            overallTierIndex = 0
            exerciseTiers = [0, 0, 0, 0, 0]
            exerciseProgress = [0, 0, 0, 0, 0]
            exerciseE1RMs = startE1RMs
            animationComplete = false
            showHeader = false
            showSubtitle = false
            showCard = false
        }
        startAnimation()
    }
}


// MARK: - Screen 5: Beyond the Basics (DISABLED — kept commented in case we re-enable)

/*
private struct OnboardingBeyondBasicsConcept: View {
    var onAnimationComplete: (() -> Void)?

    private let groups: [(fundamental: (icon: String, name: String), accessories: [(icon: String, name: String)])] = [
        (("DeadliftIcon", "Deadlifts"), [("FrontSquatsIcon", "Front Squats"), ("BackExtensionsIcon", "Back Ext."), ("HangingLegRaisesIcon", "Leg Raises")]),
        (("SquatIcon", "Squats"), [("BulgarianSplitSquatsIcon", "Split Squats"), ("DeadliftIcon", "RDLs"), ("StandingCalfRaisesIcon", "Calf Raises")]),
        (("BenchPressIcon", "Bench"), [("DipsIcon", "Dips"), ("DumbbellFlysIcon", "DB Flys"), ("LateralRaisesIcon", "Lat. Raises")]),
        (("BarbellRowIcon", "Row"), [("PullUpIcon", "Pull Ups"), ("CurlsIcon", "Curls"), ("DumbbellPulloversIcon", "Pullovers")]),
        (("OverheadPressIcon", "OHP"), [("CloseGripBenchPressIcon", "CG Bench"), ("RearDeltFlysIcon", "Rear Delts"), ("CableYRaisesIcon", "Y Raises")]),
    ]

    @State private var expandedCount: Int = 0
    @State private var showFooter: Bool = false
    @State private var animationComplete: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 12) {
                Text("Beyond the Basics")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("\(Text("Round out your training with ").foregroundColor(.white.opacity(0.7)))\(Text("accessories").fontWeight(.semibold).foregroundColor(.appAccent))\(Text(" that support the five fundamentals.").foregroundColor(.white.opacity(0.7)))")
                    .font(.inter(size: 17))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 32)

            // Card
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    HStack(spacing: 12) {
                        // Fundamental icon + name
                        Image(group.fundamental.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .foregroundStyle(Color.appAccent)

                        Text(group.fundamental.name)
                            .font(.inter(size: 13))
                            .foregroundStyle(.white)
                            .frame(width: 64, alignment: .leading)

                        // Accessory icons
                        HStack(spacing: 8) {
                            ForEach(Array(group.accessories.enumerated()), id: \.offset) { accIndex, accessory in
                                VStack(spacing: 4) {
                                    Image(accessory.icon)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 24, height: 24)
                                        .foregroundStyle(.white.opacity(0.5))

                                    Text(accessory.name)
                                        .font(.inter(size: 9))
                                        .foregroundStyle(.white.opacity(0.4))
                                        .lineLimit(1)
                                        .frame(height: 12)
                                }
                                .frame(width: 52)
                                .opacity(expandedCount > index ? 1 : 0)
                                .scaleEffect(expandedCount > index ? 1 : 0.6)
                                .animation(.easeOut(duration: 0.3), value: expandedCount)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                }

                // Footer
                Text("100+ exercises included")
                    .font(.inter(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.vertical, 12)
                    .opacity(showFooter ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: showFooter)
            }
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            .overlay(alignment: .bottomTrailing) {
                if animationComplete {
                    Button {
                        replayAnimation()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 28)
                    .padding(.bottom, 4)
                    .transition(.opacity)
                }
            }
        }
        .onAppear {
            runAnimation()
        }
    }

    private func runAnimation() {
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            for i in 0..<5 {
                withAnimation(.easeOut(duration: 0.3)) {
                    expandedCount = i + 1
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
            withAnimation(.easeOut(duration: 0.4)) {
                showFooter = true
            }
            withAnimation(.easeOut(duration: 0.3)) {
                animationComplete = true
            }
            onAnimationComplete?()
        }
    }

    private func replayAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            expandedCount = 0
            showFooter = false
            animationComplete = false
        }
        runAnimation()
    }
}
*/

// MARK: - Screen 7: Body Profile

private struct OnboardingBodyProfileStep: View {
    @Binding var currentPage: Int
    let totalPages: Int

    /// One-shot latch against a double-tap. The button stays hittable for the 0.3s
    /// advance animation, so a second tap can run the action again before SwiftUI
    /// swaps this step out — advancing twice, skipping a screen, and re-firing the
    /// sync push. Resets for free: @State is discarded when this step leaves the
    /// switch, so returning here (e.g. via the dev nav bar) re-arms it.
    @State private var didAdvance = false

    @Environment(\.modelContext) private var modelContext
    @Query private var userPropertiesItems: [UserProperties]

    @State private var selectedSex: String = "male"
    @State private var bodyweightValue: Double = 200.0
    @State private var selectedUnit: WeightUnit = .lbs
    @State private var hasInteracted: Bool = false
    /// Canonical lbs value to avoid round-trip conversion drift (e.g. 200→91kg→201)
    @State private var canonicalLbs: Double = 200.0
    @State private var isUnitSwitching: Bool = false

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 12) {
                Text("Set Your Profile")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("\(Text("Your profile helps calculate\nyour ").foregroundColor(.white.opacity(0.7)))\(Text("Strength Tier").foregroundColor(.appAccent))\(Text(".").foregroundColor(.white.opacity(0.7)))")
                    .font(.inter(size: 17))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 32)

            // Content card
            VStack(spacing: 24) {
                // Biological sex toggle
                VStack(spacing: 8) {
                    Text("BIOLOGICAL SEX")
                        .font(.interSemiBold(size: 10))
                        .foregroundStyle(Color(white: 0.5))

                    HStack(spacing: 12) {
                        ForEach(["male", "female"], id: \.self) { sex in
                            Button {
                                hasInteracted = true
                                selectedSex = sex
                            } label: {
                                Text(sex.capitalized)
                                    .font(.interSemiBold(size: 14))
                                    .foregroundStyle(selectedSex == sex ? .black : .white.opacity(0.7))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(selectedSex == sex ? Color.appAccent : Color(white: 0.16))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 240)
                }

                // Bodyweight picker
                VStack(spacing: 8) {
                    Text("BODYWEIGHT")
                        .font(.interSemiBold(size: 10))
                        .foregroundStyle(Color(white: 0.5))

                    Picker("Bodyweight", selection: $bodyweightValue) {
                        let range = selectedUnit.bodyweightPickerRange
                        ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: 1.0)), id: \.self) { value in
                            Text("\(Int(value)) \(selectedUnit.rawValue)")
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                    .onChange(of: bodyweightValue) {
                        guard !isUnitSwitching else { return }
                        hasInteracted = true
                        // Update canonical lbs when user changes picker in either unit
                        if selectedUnit == .lbs {
                            canonicalLbs = bodyweightValue
                        } else {
                            canonicalLbs = (bodyweightValue / 0.45359237).rounded()
                        }
                    }
                }

                // Weight unit toggle
                VStack(spacing: 8) {
                    Text("WEIGHT UNIT")
                        .font(.interSemiBold(size: 10))
                        .foregroundStyle(Color(white: 0.5))

                    Picker("Weight Unit", selection: $selectedUnit) {
                        Text("lbs").tag(WeightUnit.lbs)
                        Text("kg").tag(WeightUnit.kg)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .onChange(of: selectedUnit) { oldUnit, newUnit in
                        hasInteracted = true
                        isUnitSwitching = true
                        if oldUnit == .kg && newUnit == .lbs {
                            // Switching back to lbs — restore canonical value
                            // (updated whenever user changes the picker in kg)
                            bodyweightValue = canonicalLbs
                        } else if oldUnit == .lbs && newUnit == .kg {
                            // Save current lbs as canonical, then convert for display
                            canonicalLbs = bodyweightValue
                            bodyweightValue = (bodyweightValue * 0.45359237).rounded()
                            // Clamp to valid range
                            let range = newUnit.bodyweightPickerRange
                            bodyweightValue = min(max(bodyweightValue, range.lowerBound), range.upperBound)
                        }
                        isUnitSwitching = false
                    }
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 24)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            Spacer()

            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.appAccent : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()
                .frame(height: 20)

            // Bottom button
            Button {
                guard !didAdvance else { return }
                didAdvance = true
                // Save locally
                userProperties.biologicalSex = selectedSex
                userProperties.bodyweight = selectedUnit.toLbs(bodyweightValue)
                userProperties.preferredWeightUnit = selectedUnit
                try? modelContext.save()

                // Sync to backend via SyncService (retries on failure)
                Task {
                    await SyncService.shared.updateBodyProfile(
                        bodyweight: selectedUnit.toLbs(bodyweightValue),
                        biologicalSex: selectedSex,
                        weightUnit: selectedUnit.rawValue
                    )
                }

                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPage += 1
                }
            } label: {
                Text(hasInteracted ? "Continue" : "Use Defaults")
                    .font(.interSemiBold(size: 16))
                    .foregroundStyle(hasInteracted ? .black : .white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(hasInteracted ? Color.appAccent : Color(white: 0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
    }
}

// MARK: - Screen 8: Find Your Starting Strength Tier

private struct OnboardingStartingTierStep: View {
    @Binding var currentPage: Int
    let totalPages: Int
    /// "Got It!" rather than "Let's Begin" because screens follow this one — the flow
    /// isn't over yet.
    var ctaTitle: String = "Got It!"
    let onComplete: () -> Void

    private let lifts: [(icon: String, shortName: String)] = [
        ("DeadliftIcon", "Deadlifts"),
        ("SquatIcon", "Squats"),
        ("BenchPressIcon", "Bench"),
        ("BarbellRowIcon", "Row"),
        ("OverheadPressIcon", "OHP"),
    ]

    @State private var showHeader: Bool = false
    @State private var showSubtitle: Bool = false
    @State private var showCard: Bool = false
    @State private var pulse: Bool = false
    @State private var filledCount: Int = 0
    @State private var showLock: Bool = false
    @State private var showControls: Bool = false
    @State private var animationComplete: Bool = false
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 12) {
                Text("Find Your Starting Strength Tier")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .opacity(showHeader ? 1 : 0)
                    .offset(y: showHeader ? 0 : 16)

                Text("\(Text("Perform one set of each lift\nto unlock your ").foregroundColor(.white.opacity(0.7)))\(Text("Strength Tier").foregroundColor(.appAccent))\(Text(".").foregroundColor(.white.opacity(0.7)))")
                    .font(.inter(size: 17))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(showSubtitle ? 1 : 0)
                    .offset(y: showSubtitle ? 0 : 16)
            }

            Spacer().frame(height: 40)

            // Card — five fundamental lifts that fill in left-to-right; once all
            // five are locked, an open-lock icon appears beneath the caption.
            VStack(spacing: 24) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(lifts.enumerated()), id: \.offset) { index, lift in
                        let isFilled = index < filledCount
                        VStack(spacing: 10) {
                            ZStack {
                                if isFilled {
                                    Circle()
                                        .fill(Color.appAccent.opacity(0.18))
                                        .frame(width: 52, height: 52)
                                    Circle()
                                        .stroke(Color.appAccent, lineWidth: 2.5)
                                        .frame(width: 52, height: 52)
                                } else {
                                    Circle()
                                        .stroke(Color.appAccent.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
                                        .frame(width: 52, height: 52)
                                }

                                Image(lift.icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(isFilled ? Color.appAccent : Color.appAccent.opacity(pulse ? 0.85 : 0.5))
                            }
                            .frame(width: 52, height: 52)
                            .scaleEffect(isFilled ? 1.10 : (pulse ? 1.06 : 1.0))

                            Text(lift.shortName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isFilled ? .white.opacity(0.85) : .white.opacity(0.5))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            if isFilled {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color.appAccent)
                                    .frame(width: 8, height: 8)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Circle()
                                    .stroke(.white.opacity(0.25), lineWidth: 1)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                VStack(spacing: 18) {
                    Text("ONE SET EACH TO UNLOCK")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.4))

                    if showLock {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.appAccent)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            .overlay(alignment: .bottomTrailing) {
                if animationComplete {
                    Button {
                        replayAnimation()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 28)
                    .padding(.bottom, 4)
                    .transition(.opacity)
                }
            }
            .opacity(showCard ? 1 : 0)

            Spacer()

            // Page dots + CTA — gated on the fill-in animation completing so the
            // user can't skip ahead while the visualization is still playing.
            VStack(spacing: 20) {
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.appAccent : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Button {
                    onComplete()
                } label: {
                    Text(ctaTitle)
                        .font(.interSemiBold(size: 16))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.appAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            }
            .padding(.bottom, 50)
            .opacity(showControls ? 1 : 0)
            .animation(.easeOut(duration: 0.4), value: showControls)
            .allowsHitTesting(showControls)
        }
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        animationTask?.cancel()
        animationTask = Task {
            withAnimation(.easeOut(duration: 0.45)) { showHeader = true }
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeOut(duration: 0.45)) { showSubtitle = true }
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.easeOut(duration: 0.4)) { showCard = true }
            try? await Task.sleep(for: .milliseconds(80))

            // Gentle pulse on the awaiting lifts. Filled lifts ignore `pulse`
            // (they read the `isFilled` branch instead) so they hold their
            // brighter, larger state once they lock in.
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }

            // Fill in one by one, left to right.
            for _ in 0..<5 {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                    filledCount += 1
                }
                try? await Task.sleep(for: .milliseconds(200))
            }

            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                showLock = true
            }
            // Page dots + Let's Begin become available alongside the unlock
            // icon — slightly ahead of the replay button.
            withAnimation(.easeOut(duration: 0.35)) {
                showControls = true
            }

            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                animationComplete = true
            }
        }
    }

    private func replayAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            filledCount = 0
            showLock = false
            showControls = false
            animationComplete = false
        }
        runAnimation()
    }
}

// MARK: - Helper Views

private struct OnboardingBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.appAccent)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(.inter(size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
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
