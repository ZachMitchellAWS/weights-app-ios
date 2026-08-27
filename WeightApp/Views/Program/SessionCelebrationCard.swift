//
//  SessionCelebrationCard.swift
//  WeightApp
//
//  The moment a lift's set plan is finished mid-session, and the moment the whole session
//  is. Before this, both were nearly silent — an icon turned amber in the rail and a button
//  relabelled, which is very little for the point at which a session has real momentum.
//
//  Visual language is deliberately `readyToLiftCard`'s (CheckInView): same scrim, card
//  width, corner radius, gradient, accent border and type ramp. These are two different
//  moments, but they are the same KIND of moment — the app asking "here is where you are,
//  do you want to go here next" — and they should look related.
//
//  The chain is the new element, and it reuses the rail's vocabulary rather than inventing
//  a second way to draw session progress.
//

import SwiftUI

struct SessionCelebrationCard: View {
    enum Kind {
        /// One lift finished, more left.
        case lift(completed: ProgramSessionStore.Item, next: ProgramSessionStore.Item)
        /// Every lift finished.
        case session

        /// Stable analytics discriminator. Kept on the type so the two call sites that
        /// report it cannot disagree about the spelling.
        var analyticsKind: String {
            switch self {
            case .lift: return "lift"
            case .session: return "session"
            }
        }
    }

    let kind: Kind


    let items: [ProgramSessionStore.Item]
    let onPrimary: () -> Void
    let onDismiss: () -> Void

    /// Drives the just-finished icon's one-off emphasis. A single settle rather than a
    /// repeating pulse — this card is read once and dismissed, so a loop would only ever
    /// be motion for its own sake.
    @State private var settled = false
    /// The title's checkmark, animated in separately from `settled` so the two beats do not
    /// arrive together — the chain icon settles, then the check lands.
    @State private var checked = false

    /// Which closing line this showing gets. Resolved once, in `onAppear`.
    ///
    /// It CANNOT be computed in the body: a random pick there would be re-rolled on every
    /// render, and the title would change while the card animates in.
    @State private var sessionTitle = Self.sessionTitles[0]

    /// Rotated rather than randomised, so the same line does not land twice running — the
    /// repeat is exactly what would make a stock phrase feel stock.
    private static let sessionTitles = [
        "THAT'S THE WORK.",
        "SHOWED UP. LIFTED.",
        "ALL LIFTS LANDED.",
        "THE WORK IS DONE.",
        "TODAY'S WORK IS IN.",
        "EVERY SET COUNTED.",
    ]

    /// Install-scoped and deliberately not reset with a session — the point is variety
    /// ACROSS sessions, so the counter has to outlive each one.
    private static let rotationKey = "sessionCelebrationTitleIndex"

    var body: some View {
        VStack(spacing: 16) {
            Text(eyebrow)
                .font(.interSemiBold(size: 11))
                .tracking(3)
                .foregroundStyle(Color.appAccent)

            HStack(spacing: 10) {
                Text(title)
                    .font(.bebasNeue(size: 40))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                // Carries the completion in place of the word "done". It lands a beat after
                // the card, so the check reads as something that just happened rather than
                // as part of the title.
                if case .lift = kind {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                        .scaleEffect(checked ? 1 : 0.2)
                        .opacity(checked ? 1 : 0)
                }
            }

            chain

            Button(action: onPrimary) {
                HStack(spacing: 8) {
                    Image(systemName: primaryIcon)
                        .font(.system(size: 15, weight: .semibold))
                    Text(primaryLabel)
                        .font(.interSemiBold(size: 16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.appAccent, in: Capsule())
            }
            .buttonStyle(.plain)

            // Only the per-lift card offers a quiet exit. Someone may want extra sets on
            // the lift they just finished, and trapping them behind a single CTA would make
            // this an obstacle. The session card needs no such escape — the scrim dismisses
            // it, and there is nothing left to stay for.
            if case .lift = kind {
                Button(action: onDismiss) {
                    Text("Not right now")
                        .font(.inter(size: 13))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(maxWidth: 330)
        .background(
            LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.09)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.appAccent.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .padding(.horizontal, 24)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.15)) {
                settled = true
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.3)) {
                checked = true
            }

            if case .session = kind {
                let index = UserDefaults.standard.integer(forKey: Self.rotationKey)
                sessionTitle = Self.sessionTitles[index % Self.sessionTitles.count]
                UserDefaults.standard.set(index + 1, forKey: Self.rotationKey)
            }
        }
    }

    // MARK: - The chain

    /// Every lift in the session, in order: what is done, what you just finished, and what
    /// is next. Answers "how far through am I" and "where am I going" in one object, which
    /// a from → to pair cannot.
    private var chain: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(connectorColor(before: item))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }

                VStack(spacing: badgeSize * 0.13) {
                    ZStack {
                        Circle()
                            .fill(fill(for: item))
                            .frame(width: badgeSize, height: badgeSize)

                        Circle()
                            .strokeBorder(border(for: item),
                                          lineWidth: isNext(item) ? ringWidth * 2 : ringWidth)
                            .frame(width: badgeSize, height: badgeSize)

                        Image(item.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: badgeSize * 0.52, height: badgeSize * 0.52)
                            .foregroundStyle(tint(for: item))
                    }
                    // The lift just finished lands slightly larger, then settles.
                    .scaleEffect(isJustCompleted(item) && !settled ? 1.22 : 1)

                    Text(item.shortName)
                        .font(.system(size: labelSize, weight: .semibold))
                        .foregroundStyle(tint(for: item).opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: badgeSize * 1.35)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - Chain sizing

    // The chain fills the card rather than sitting at one fixed size.
    //
    // 40pt was chosen so five lifts fit, which made it right for five and wrong for
    // everything else — a one-lift session rendered as a lone tiny badge floating in a
    // card built for a row. The badge now grows as the row shortens, so a single lift
    // reads as a medallion and five still fit comfortably.
    //
    // Hand-picked per count rather than derived from available width: there are only five
    // possible values, and each was chosen to look right rather than to satisfy a formula.
    private var badgeSize: CGFloat {
        switch items.count {
        case 0, 1: return 88
        case 2: return 70
        case 3: return 58
        case 4: return 47
        default: return 40
        }
    }

    /// Hairlines look thinner as the circle grows, so the ring thickens a little with it.
    private var ringWidth: CGFloat { items.count <= 2 ? 1.5 : 1 }

    private var labelSize: CGFloat {
        switch items.count {
        case 0, 1: return 13
        case 2: return 12
        case 3: return 11
        default: return 9
        }
    }

    // MARK: - Chain styling

    private func isJustCompleted(_ item: ProgramSessionStore.Item) -> Bool {
        if case let .lift(completed, _) = kind { return item.id == completed.id }
        return false
    }

    private func isNext(_ item: ProgramSessionStore.Item) -> Bool {
        if case let .lift(_, next) = kind { return item.id == next.id }
        return false
    }

    private func fill(for item: ProgramSessionStore.Item) -> Color {
        item.isComplete ? Color.appAccent.opacity(0.18) : Color.white.opacity(0.04)
    }

    private func border(for item: ProgramSessionStore.Item) -> Color {
        if item.isComplete { return Color.appAccent.opacity(0.65) }
        if isNext(item) { return Color.appAccent.opacity(0.8) }
        return .white.opacity(0.12)
    }

    private func tint(for item: ProgramSessionStore.Item) -> Color {
        if item.isComplete { return Color.appAccent }
        if isNext(item) { return .white }
        return .white.opacity(0.3)
    }

    /// Lit up to the point you have reached, dim beyond it — so the row reads left to right
    /// as progress rather than as a set of unrelated badges.
    private func connectorColor(before item: ProgramSessionStore.Item) -> Color {
        item.isComplete ? Color.appAccent.opacity(0.4) : .white.opacity(0.1)
    }

    // MARK: - Copy

    private var eyebrow: String {
        switch kind {
        // "SESSION PROGRESS", not "LIFT COMPLETE". The card's job here is to place you
        // inside the session — the chain below is the point — and leading with COMPLETE
        // framed it as an ending when the session is still running. The completion itself
        // is carried by the title and the checked icon.
        case .lift: return "SESSION PROGRESS"
        case .session: return "SESSION COMPLETE"
        }
    }

    private var title: String {
        switch kind {
        case let .lift(completed, _): return completed.exerciseName
        case .session: return sessionTitle
        }
    }

    private var primaryLabel: String {
        switch kind {
        case let .lift(_, next): return "Continue to \(next.shortName)"
        case .session: return "See your session"
        }
    }

    private var primaryIcon: String {
        switch kind {
        case .lift: return "arrow.right"
        case .session: return "checkmark.circle.fill"
        }
    }
}
