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

    @State private var currentPage = 0
    @State private var showControls = false
    private let totalPages = 6

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                // Page content
                Group {
                    switch currentPage {
                    case 0: OnboardingWelcome()
                    case 1: OnboardingFiveLiftsConcept(onAnimationComplete: {
                        withAnimation(.easeOut(duration: 0.4)) {
                            showControls = true
                        }
                    })
                    case 2: OnboardingProgressConcept(onAnimationComplete: {
                        withAnimation(.easeOut(duration: 0.4)) {
                            showControls = true
                        }
                    })
                    case 3: OnboardingMilestonesConcept(onAnimationComplete: {
                        withAnimation(.easeOut(duration: 0.4)) {
                            showControls = true
                        }
                    })
                    case 4: OnboardingChangePlatesStep(currentPage: $currentPage, totalPages: totalPages)
                    case 5: OnboardingBodyProfileStep(currentPage: $currentPage, totalPages: totalPages, onComplete: onComplete)
                    default: EmptyView()
                    }
                }

                Spacer()

                // Page indicators + Continue button (not shown on plates/body profile pages — they have their own)
                if currentPage < totalPages - 2 {
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
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showControls = false // Reset for E1RM animation fade-in
                                currentPage += 1
                            }
                        } label: {
                            Text(currentPage == 0 ? "Get Started" : "Continue")
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
                    // Welcome + Five Lifts: always visible. E1RM & Effort screens: fade in after animation. Others: always visible.
                    .opacity(currentPage == 0 || (currentPage != 1 && currentPage != 2 && currentPage != 3 && currentPage != 4 && currentPage != 5) || showControls ? 1 : 0)
                }
            }
        }
    }
}

// MARK: - Screen 1: Welcome

private struct OnboardingWelcome: View {
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
            Text("Welcome to Lift the Bull")
                .font(.bebasNeue(size: 38))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Spacer()
                .frame(height: 12)

            // Setup message
            Text("Here's a quick look at the basics.")
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
    private let targetProgress: [CGFloat] = [0.90, 0.65, 0.75, 0.70, 0.80]
    private let exerciseTiers: [StrengthTier] = [.legend, .advanced, .elite, .intermediate, .advanced]
    private let overallTier: StrengthTier = .advanced

    @State private var animatedExercise: Int = 0
    @State private var barProgress: [CGFloat] = [0, 0, 0, 0, 0]
    @State private var showOverallTier: Bool = false
    @State private var animationComplete: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 12) {
                Text("Your Strength Tier")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                (Text("Your strength is measured across\n")
                    + Text("Five").fontWeight(.semibold).foregroundColor(.appAccent)
                    + Text(" fundamental lifts."))
                    .font(.inter(size: 17))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 32)

            // Exercise list card (contains bars + overall tier)
            VStack(spacing: 0) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    HStack(spacing: 14) {
                        Image(exercise.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .foregroundStyle(barProgress[index] > 0 ? Color.appAccent : .white.opacity(0.3))

                        Text(exercise.name)
                            .font(.inter(size: 15))
                            .foregroundStyle(.white)
                            .frame(width: 120, alignment: .leading)

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 6)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(exerciseTiers[index].color)
                                    .frame(width: barProgress[index] * geo.size.width, height: 6)
                            }
                            .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 6)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }

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
            try? await Task.sleep(for: .milliseconds(300))
            for i in 0..<5 {
                withAnimation(.easeOut(duration: 0.3)) {
                    barProgress[i] = targetProgress[i]
                }
                try? await Task.sleep(for: .milliseconds(i < 4 ? 300 : 200))
            }
            try? await Task.sleep(for: .milliseconds(250))
            showOverallTier = true
            withAnimation(.easeOut(duration: 0.3)) {
                animationComplete = true
            }
            onAnimationComplete?()
        }
    }

    private func replayAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            barProgress = [0, 0, 0, 0, 0]
            showOverallTier = false
            animationComplete = false
        }
        runAnimation()
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
        (1.00, .setPR),
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
        (.setPR, "PR", 6),
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
                                        .foregroundStyle(Color.setPR)
                                        .shadow(color: Color.setPR.opacity(0.5), radius: 8, x: 0, y: 0)

                                    VStack(spacing: 1) {
                                        Text("New")
                                            .font(.inter(size: 9))
                                            .foregroundStyle(Color.setPR)
                                        Text("Estimated 1RM")
                                            .font(.inter(size: 9))
                                            .foregroundStyle(Color.setPR)
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
                try await Task.sleep(for: .milliseconds(200))
                visibleBars = i
            }

            // PR indicator after 0.5s pause
            try await Task.sleep(for: .milliseconds(500))
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

    private let bars: [(height: CGFloat, color: Color)] = [
        (0.30, .setEasy),
        (0.35, .setEasy),
        (0.50, .setModerate),
        (0.55, .setModerate),
        (0.70, .setHard),
        (1.00, .setPR),
    ]

    private let maxBarHeight: CGFloat = 160
    private let barWidth: CGFloat = 32
    private let barSpacing: CGFloat = 12
    private let indicatorHeight: CGFloat = 56

    private let legendEntries: [(color: Color, label: String, threshold: Int)] = [
        (.setEasy, "Easy", 1),
        (.setModerate, "Moderate", 3),
        (.setHard, "Hard", 5),
        (.setPR, "Progress", 6),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 12) {
                Text("Achievable Progress")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                (Text("Follow set options that increase your\n")
                    + Text("estimated one-rep maxes").foregroundColor(.appAccent))
                    .font(.inter(size: 17))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
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
                                            .foregroundStyle(Color.setPR)
                                            .shadow(color: Color.setPR.opacity(0.5), radius: 8, x: 0, y: 0)

                                        VStack(spacing: 1) {
                                            Text("New")
                                                .font(.inter(size: 9))
                                                .foregroundStyle(Color.setPR)
                                            Text("Estimated 1RM")
                                                .font(.inter(size: 9))
                                                .foregroundStyle(Color.setPR)
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
            .onAppear {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        Task {
            // Initial beat, then show e1RM number + first bar simultaneously
            try await Task.sleep(for: .milliseconds(300))
            showE1RM = true
            visibleBars = 1

            for i in 2...bars.count {
                try await Task.sleep(for: .milliseconds(100))
                visibleBars = i
            }

            try await Task.sleep(for: .milliseconds(300))
            showPRIndicator = true

            // Animate e1RM number rolling up from 185 → 195
            try await Task.sleep(for: .milliseconds(250))
            for value in 186...195 {
                try await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeOut(duration: 0.2)) {
                    displayedE1RM = value
                }
            }

            // Show green delta indicator
            try await Task.sleep(for: .milliseconds(200))
            showDelta = true

            withAnimation(.easeOut(duration: 0.3)) {
                animationComplete = true
            }
            onAnimationComplete?()
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
            (167, .setHard), (169, .setNearMax), (170, .setPR),
            (160, .setEasy), (164, .setModerate), (168, .setHard),
            (171, .setHard), (173, .setNearMax), (175, .setPR),
            (165, .setEasy), (169, .setEasy), (173, .setModerate),
            (176, .setHard), (179, .setNearMax), (182, .setPR),
            (172, .setEasy), (176, .setModerate), (180, .setModerate),
            (183, .setHard), (186, .setNearMax), (188, .setPR),
            (178, .setEasy), (182, .setModerate), (186, .setHard),
            (189, .setHard), (192, .setNearMax), (195, .setPR),
            (184, .setEasy), (188, .setEasy), (192, .setModerate),
            (196, .setHard), (199, .setNearMax), (202, .setPR),
            (190, .setEasy), (194, .setModerate), (198, .setModerate),
            (202, .setHard), (205, .setNearMax), (208, .setPR),
            (196, .setEasy), (200, .setEasy), (204, .setModerate),
            (208, .setHard), (212, .setNearMax), (215, .setPR),
            (202, .setEasy), (206, .setModerate), (210, .setModerate),
            (214, .setHard), (218, .setNearMax), (222, .setPR),
            (208, .setEasy), (212, .setEasy), (216, .setModerate),
            (220, .setHard), (225, .setNearMax), (228, .setPR),
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
                HStack(spacing: 10) { LegendDot(color: .setEasy, label: "Easy"); LegendDot(color: .setModerate, label: "Moderate"); LegendDot(color: .setHard, label: "Hard"); LegendDot(color: .setNearMax, label: "Redline"); LegendDot(color: .setPR, label: "PR") }.padding(.top, 16)
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
        case "pr": return .setPR
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
                            .foregroundStyle(Color.setPR)
                            .shadow(color: Color.setPR.opacity(0.5), radius: 6, x: 0, y: 0)

                        Text("New Estimated 1RM")
                            .font(.inter(size: 9))
                            .foregroundStyle(Color.setPR)
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
                    LegendDot(color: .setPR, label: "PR")
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
            try await Task.sleep(for: .milliseconds(200))

            // Fill tiles one by one
            let tileCount = currentPlan.tiles.count
            for i in 1...tileCount {
                try await Task.sleep(for: .milliseconds(200))
                filledTiles = i
            }

            // Show PR indicator if plan has a PR tile
            if hasPR {
                try await Task.sleep(for: .milliseconds(500))
                showPRIndicator = true
            }

            // Show next button slightly before continue button
            withAnimation(.easeOut(duration: 0.4)) {
                showNextButton = true
            }
            try await Task.sleep(for: .milliseconds(300))
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
            try await Task.sleep(for: .milliseconds(400))

            currentPlanIndex = (currentPlanIndex + 1) % plans.count

            // Flash plan name amber briefly
            highlightPlanName = true
            animateCurrentPlan()
            try await Task.sleep(for: .seconds(1))
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
         ("2", "245", .setPR), ("6", "205", .setHard), ("8", "185", .setModerate), ("10", "165", .setEasy),
         ("8", "175", .setModerate), ("6", "195", .setHard), ("5", "210", .setNearMax), ("3", "230", .setPR)]
    }
    private var previousSets: [(reps: String, weight: String, color: Color)] {
        [("12", "115", .setEasy), ("10", "135", .setEasy), ("8", "155", .setModerate), ("8", "165", .setModerate),
         ("6", "185", .setHard), ("6", "195", .setHard), ("5", "205", .setNearMax), ("4", "215", .setNearMax),
         ("3", "225", .setPR), ("6", "195", .setHard), ("8", "175", .setModerate), ("10", "155", .setEasy),
         ("8", "165", .setModerate), ("6", "185", .setHard), ("4", "210", .setNearMax), ("2", "225", .setPR)]
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
                HStack(spacing: 10) { LegendDot(color: .setEasy, label: "Easy"); LegendDot(color: .setModerate, label: "Moderate"); LegendDot(color: .setHard, label: "Hard"); LegendDot(color: .setNearMax, label: "Redline"); LegendDot(color: .setPR, label: "PR") }.padding(.top, 12)
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

    private let badgeSize: CGFloat = 48

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 12) {
                Text("Milestones That Matter")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                (Text("Earn ").foregroundColor(.white.opacity(0.7))
                    + Text("Milestones").foregroundColor(.appAccent)
                    + Text(" as you get stronger.").foregroundColor(.white.opacity(0.7)))
                    .font(.inter(size: 17))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 32)

            // Card
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<5, id: \.self) { i in
                        milestoneColumn(index: i)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 40)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

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
                .padding(.vertical, 12)
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
            // e1RM number
            Text("\(exerciseE1RMs[i])")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

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

                    Text("\(Int(exerciseProgress[i] * 100))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
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

            // Tier label
            Text(shortTierName(tiers[tierIndex]))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(displayColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func shortTierName(_ tier: StrengthTier) -> String {
        switch tier {
        case .intermediate: return "Inter."
        default: return tier.title
        }
    }

    private func startAnimation() {
        animationTask?.cancel()
        animationTask = Task {
            // Initial pause
            try? await Task.sleep(for: .milliseconds(300))

            for round in 0..<5 {
                guard !Task.isCancelled else { return }
                let order = roundOrders[round]

                for (exerciseCount, exerciseIndex) in order.enumerated() {
                    guard !Task.isCancelled else { return }

                    let targetE1RM = startE1RMs[exerciseIndex] + e1rmIncrements[exerciseIndex] * (round + 1)
                    let currentE1RM = exerciseE1RMs[exerciseIndex]
                    let steps = 8
                    let stepDuration: UInt64 = 100

                    // Animate progress ring and e1RM simultaneously
                    for step in 1...steps {
                        guard !Task.isCancelled else { return }
                        try? await Task.sleep(for: .milliseconds(stepDuration))
                        let fraction = CGFloat(step) / CGFloat(steps)
                        let interpolatedE1RM = currentE1RM + Int(Double(targetE1RM - currentE1RM) * Double(fraction))
                        withAnimation(.easeOut(duration: 0.3)) {
                            exerciseProgress[exerciseIndex] = fraction
                            exerciseE1RMs[exerciseIndex] = interpolatedE1RM
                        }
                    }

                    // Complete: advance tier, reset progress
                    try? await Task.sleep(for: .milliseconds(100))
                    withAnimation(.easeOut(duration: 0.4)) {
                        exerciseTiers[exerciseIndex] += 1
                        exerciseProgress[exerciseIndex] = 0
                    }

                    // Fire callback early — after 1st exercise in round 0
                    if round == 0 && exerciseCount == 0 {
                        onAnimationComplete?()
                    }

                    // Pause between exercises
                    try? await Task.sleep(for: .milliseconds(300))
                }

                // Advance overall tier after all exercises in this round complete
                withAnimation(.easeOut(duration: 0.4)) {
                    overallTierIndex = exerciseTiers.min() ?? 0
                }

                // Pause between rounds
                try? await Task.sleep(for: .milliseconds(400))
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
        }
        startAnimation()
    }
}


// MARK: - Screen 5: Change Plates

private struct OnboardingChangePlatesStep: View {
    @Binding var currentPage: Int
    let totalPages: Int

    @Environment(\.modelContext) private var modelContext
    @Query private var userPropertiesItems: [UserProperties]
    @State private var initialPlates: [Double] = []

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

    private var hasChanges: Bool {
        userProperties.availableChangePlates.sorted() != initialPlates
    }

    private func isPlateActive(_ plate: Double) -> Bool {
        return plateWeights.contains { abs($0 - plate) < 0.01 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 12) {
                Text("Select Plate Increments")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Select the change plates you have\navailable for more precise suggestions.")
                    .font(.inter(size: 17))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 32)

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
                if hasChanges {
                    Task {
                        await SyncService.shared.updateChangePlates(userProperties.availableChangePlates)
                    }
                }
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPage += 1
                }
            } label: {
                Text(hasSelection ? "Continue" : "Maybe Later")
                    .font(.interSemiBold(size: 16))
                    .foregroundStyle(hasSelection ? .black : .white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(hasSelection ? Color.appAccent : Color(white: 0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
        .onAppear {
            initialPlates = userProperties.availableChangePlates.sorted()
        }
    }

    private func togglePlate(_ plate: Double) {
        if isPlateActive(plate) {
            userProperties.availableChangePlates.removeAll { abs($0 - plate) < 0.01 }
        } else {
            userProperties.availableChangePlates.append(plate)
        }
        try? modelContext.save()
    }
}

// MARK: - Screen 6: Body Profile

private struct OnboardingBodyProfileStep: View {
    @Binding var currentPage: Int
    let totalPages: Int
    let onComplete: () -> Void

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
                Text("Set Your Baseline")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Your inputs help to determine\nyour strength tier.")
                    .font(.inter(size: 17))
                    .foregroundStyle(.white.opacity(0.7))
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

                onComplete()
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
