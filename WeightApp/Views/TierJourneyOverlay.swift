import SwiftUI

enum TierJourneyMode {
    case intro
    case progress(justLoggedId: UUID)
    case completion(tier: StrengthTier)
}

struct TierJourneyOverlay: View {
    let mode: TierJourneyMode
    let exerciseTiers: [(exercise: TrendsCalculator.FundamentalExercise, e1rm: Double?, tier: StrengthTier)]
    let onDismiss: () -> Void
    let onNavigateToExercise: (UUID) -> Void
    let onNavigateToStrength: () -> Void

    @State private var glowPhase: CGFloat = 1.0
    @State private var justLoggedAppeared = false

    private var loggedCount: Int {
        exerciseTiers.filter { $0.e1rm != nil }.count
    }

    private var borderColor: Color {
        if case .completion(let tier) = mode {
            return tier.color.opacity(0.5)
        }
        return Color.appAccent.opacity(0.5)
    }

    private var nextUnloggedExercise: TrendsCalculator.FundamentalExercise? {
        exerciseTiers.first(where: { $0.e1rm == nil })?.exercise
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            VStack(spacing: 12) {
                switch mode {
                case .intro:
                    introContent
                case .progress:
                    progressContent
                case .completion(let tier):
                    completionContent(tier: tier)
                }

                exerciseRow

                ctaButton
            }
            .padding(16)
            .frame(width: 280)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(borderColor, lineWidth: 1.5)
            )
        }
    }

    // MARK: - State A: Introduction

    private var introContent: some View {
        VStack(spacing: 8) {
            Text("Your Strength Tier Journey")
                .font(.bebasNeue(size: 22))
                .foregroundStyle(Color.appAccent)

            Text("Log your first set of each exercise to unlock your Strength Tier")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - State B: Progress

    private var progressContent: some View {
        VStack(spacing: 8) {
            Text("Nice Work")
                .font(.bebasNeue(size: 22))
                .foregroundStyle(Color.appAccent)

            Text("\(loggedCount) of 5 Exercises Logged")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - State C: Completion

    private func completionContent(tier: StrengthTier) -> some View {
        VStack(spacing: 8) {
            Text("Strength Tier Unlocked")
                .font(.bebasNeue(size: 24))
                .foregroundStyle(tier.color)

            ZStack {
                // Pulsing glow ring
                Circle()
                    .fill(tier.color.opacity(0.3))
                    .frame(width: 72, height: 72)
                    .scaleEffect(glowPhase)
                    .opacity(1.0 - (glowPhase - 1.0) / 0.6)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                            glowPhase = 1.6
                        }
                    }

                Circle()
                    .fill(tier.color.opacity(0.2))
                    .frame(width: 72, height: 72)

                Circle()
                    .stroke(tier.color.opacity(0.7), lineWidth: 3)
                    .frame(width: 72, height: 72)

                Image(tier.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(tier.color)
            }

            Text(tier.title)
                .font(.bebasNeue(size: 28))
                .foregroundStyle(tier.color)
        }
    }

    // MARK: - Exercise Row

    private var exerciseRow: some View {
        HStack(spacing: 12) {
            ForEach(exerciseTiers, id: \.exercise.id) { item in
                let isLogged = item.e1rm != nil
                let isJustLogged: Bool = {
                    if case .progress(let justLoggedId) = mode {
                        return item.exercise.id == justLoggedId
                    }
                    return false
                }()
                let iconColor: Color = {
                    if case .completion(let tier) = mode {
                        return tier.color
                    }
                    return isLogged ? Color.appAccent : .white.opacity(0.2)
                }()

                VStack(spacing: 4) {
                    Image(item.exercise.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(iconColor)

                    Text(shortName(for: item.exercise.name))
                        .font(.system(size: 10))
                        .foregroundStyle(isLogged ? .white.opacity(0.7) : .white.opacity(0.3))

                    if isLogged {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(iconColor)
                    } else {
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                            .frame(width: 8, height: 8)
                    }
                }
                .scaleEffect(isJustLogged && !justLoggedAppeared ? 0.8 : 1.0)
                .opacity(isJustLogged && !justLoggedAppeared ? 0.0 : 1.0)
                .background {
                    if isJustLogged && justLoggedAppeared {
                        Circle()
                            .fill(Color.appAccent.opacity(0.15))
                            .frame(width: 44, height: 44)
                            .blur(radius: 8)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            if case .progress = mode {
                withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
                    justLoggedAppeared = true
                }
            }
        }
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        Group {
            switch mode {
            case .intro:
                ctaCapsule(label: "Let's Go", color: .appAccent) {
                    onDismiss()
                }

            case .progress:
                if let next = nextUnloggedExercise {
                    ctaCapsule(label: "Next Up: \(shortName(for: next.name))", color: .appAccent) {
                        onDismiss()
                        onNavigateToExercise(next.id)
                    }
                }

            case .completion(let tier):
                ctaCapsule(label: "See Your Strength Tier", color: tier.color) {
                    onDismiss()
                    onNavigateToStrength()
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private func ctaCapsule(label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(color, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func shortName(for name: String) -> String {
        switch name {
        case "Overhead Press": return "OH Press"
        case "Bench Press": return "Bench"
        case "Barbell Row": return "Rows"
        default: return name
        }
    }
}
