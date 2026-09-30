//
//  SessionIntentFlow.swift
//  WeightApp
//
//  The last two onboarding steps: a next-session question, and a reminder permission
//  ask that schedules a one-time local notification from the answer.
//
//  SCOPE
//  The reminder is a LOCAL notification. The backend has no APNs send path — it stores
//  `apnsDeviceToken` and nothing reads it — so scheduling happens on-device. Granting
//  permission still registers for remote notifications, which keeps the token flowing
//  as groundwork for a future server-side sender.
//
//  The chosen intent lives on-device only (UserDefaults via `PushNotificationService`,
//  plus an Amplitude user property). Nothing server-side consumes it today.
//
//  `MockSystemPermissionAlert` survives for one reason: the standalone dev preview at
//  the bottom of this file passes `usesMockPermissionPrompt: true`. iOS shows its
//  permission dialog once per install, so iterating on this screen against the real
//  prompt would consume it and require a reinstall to test again.
//

import SwiftUI

// MARK: - Intent model

/// The user's answer to "when's your next session?", plus the reminder timestamp
/// each answer implies.
enum NextSessionIntent: String, CaseIterable, Identifiable {
    case today = "Today"
    case tomorrow = "Tomorrow"
    case thisWeekend = "This weekend"
    case notSure = "Not sure yet"

    var id: String { rawValue }

    // MARK: Declared intent

    /// The answer the user gave during onboarding, remembered past the flow.
    ///
    /// Stored here rather than reusing `PushNotificationService`'s reminder key, which is
    /// written only inside the notification-scheduling success callback and cleared whenever
    /// the reminder is cancelled or consumed. Both are wrong for this: a user who DECLINED
    /// notifications still answered the question, and their answer should outlive the
    /// reminder it was collected for.
    private static let declaredKey = "onboardingSessionIntent"

    /// What they said, or nil if they never reached the step (every account created before
    /// it shipped).
    static var declared: NextSessionIntent? {
        guard let raw = UserDefaults.standard.string(forKey: declaredKey) else { return nil }
        return NextSessionIntent(rawValue: raw)
    }

    static func recordDeclared(_ intent: NextSessionIntent) {
        UserDefaults.standard.set(intent.rawValue, forKey: declaredKey)
    }

    static func clearDeclared() {
        UserDefaults.standard.removeObject(forKey: declaredKey)
    }

    /// The single anchor hour for every scheduled reminder. "Today" is the only rule
    /// expressed as an offset, and even it falls back to this hour when clamped.
    static let anchorHour = 11

    /// Lead time for "Today" before any clamping.
    static let todayLeadHours = 2

    /// Days out for "Not sure yet".
    static let notSureLeadDays = 3

    /// Hours outside which a reminder must not land. A "Today" answer late at night
    /// would otherwise fire in the small hours — a poor first impression for the only
    /// notification this app ever sends.
    static let earliestHour = 8
    static let latestHour = 22

    /// Subline on the reminder screen. Deliberately vague for "Not sure yet" even
    /// though it now schedules like the others — someone who said they don't know
    /// their plans shouldn't be handed a specific time back.
    var reminderSublineTail: String {
        switch self {
        case .notSure:
            return " when it's been a few days, so you don't lose momentum."
        default:
            return " before your session so you can unlock your Starting Strength Tier."
        }
    }

    /// Body copy for the sample notification.
    /// Read by both the real notification and the onboarding preview banner, so the
    /// two cannot drift.
    var bannerBody: String {
        switch self {
        case .notSure:
            return "Ready when you are. Log one set of each lift to unlock your Starting Strength Tier."
        default:
            return "Session time. Log one set of each lift to unlock your Starting Strength Tier."
        }
    }

    /// Declarative confirmation, used as the reminder screen's headline so it reads
    /// as acknowledging the answer rather than asking again.
    var confirmationHeadline: String {
        switch self {
        case .today: return "TODAY IT IS."
        case .tomorrow: return "TOMORROW IT IS."
        case .thisWeekend: return "THIS WEEKEND IT IS."
        case .notSure: return "NO PROBLEM."
        }
    }

    /// When the reminder should fire. Every answer now yields a concrete time.
    func targetDate(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .today:
            let raw = now.addingTimeInterval(TimeInterval(Self.todayLeadHours) * 3600)
            return Self.clampedToWakingHours(raw, calendar: calendar)

        case .tomorrow:
            return Self.nextAnchorHour(after: now, addingDays: 1, calendar: calendar)

        case .notSure:
            return Self.nextAnchorHour(after: now, addingDays: Self.notSureLeadDays, calendar: calendar)

        case .thisWeekend:
            // Next Saturday morning, strictly after now — so answering on a Saturday
            // afternoon points at the following weekend rather than the past.
            var components = DateComponents()
            components.weekday = 7            // Saturday
            components.hour = Self.anchorHour
            components.minute = 0
            return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
                ?? now.addingTimeInterval(TimeInterval(Self.todayLeadHours) * 3600)
        }
    }

    /// `anchorHour` on the day `days` from `now`.
    private static func nextAnchorHour(after now: Date, addingDays days: Int, calendar: Calendar) -> Date {
        let shifted = calendar.date(byAdding: .day, value: days, to: now) ?? now
        return calendar.date(bySettingHour: anchorHour, minute: 0, second: 0, of: shifted) ?? shifted
    }

    /// Pushes a time that lands overnight to the next `anchorHour`.
    ///
    /// Handles both tails with one rule, because "the next 11:00 after this instant"
    /// resolves to later the same morning for a pre-dawn target and to the following
    /// morning for a late-evening one. A same-day clamp can't work for the 11:30pm
    /// case — every remaining hour that day is already in the past.
    private static func clampedToWakingHours(_ date: Date, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: date)
        guard hour >= latestHour || hour < earliestHour else { return date }

        var components = DateComponents()
        components.hour = anchorHour
        components.minute = 0
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime) ?? date
    }

    /// Timestamp shown in the banner's top-right, as iOS would display it.
    func bannerTimeLabel(from now: Date = Date(), calendar: Calendar = .current) -> String {
        let target = targetDate(from: now, calendar: calendar)
        let formatter = DateFormatter()
        switch self {
        case .today:
            // A clamped "Today" lands tomorrow, so name the day rather than an hour
            // that would read as today.
            if !calendar.isDate(target, inSameDayAs: now) { return "tomorrow" }
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: target)
        case .tomorrow:
            return "tomorrow"
        case .thisWeekend:
            formatter.dateFormat = "EEE"
            return formatter.string(from: target)
        case .notSure:
            // Stays vague on purpose, even though a time is now scheduled.
            return "later"
        }
    }

    /// Whole hours from `now` until the reminder — the analytics lead-time property.
    func hoursAhead(from now: Date = Date(), calendar: Calendar = .current) -> Int {
        let seconds = targetDate(from: now, calendar: calendar).timeIntervalSince(now)
        return max(0, Int((seconds / 3600).rounded()))
    }
}

/// What the permission ask resolved to.
enum PermissionOutcome: String {
    case granted = "granted"
    case denied = "denied"
    case skipped = "skipped (No thanks)"
    case notAsked = "not asked"
}

// MARK: - Step 1: the session question

/// Matches the layout contract of the later onboarding steps (`OnboardingBodyProfileStep`
/// et al): own progress dots, own full-width CTA, navigation delegated to the caller.
struct OnboardingSessionIntentStep: View {
    let pageIndex: Int
    let totalPages: Int
    @Binding var intent: NextSessionIntent
    /// Caller decides where Continue goes, since that depends on the answer.
    let onContinue: (NextSessionIntent) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("WHEN'S YOUR NEXT SESSION?")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                (
                    Text("The app will help you show up ready to unlock your ")
                        .foregroundStyle(.white.opacity(0.7))
                    + Text("Starting Strength Tier").foregroundStyle(Color.appAccent)
                    + Text(".").foregroundStyle(.white.opacity(0.7))
                )
                .font(.inter(size: 17))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            }

            Spacer().frame(height: 32)

            VStack(spacing: 10) {
                ForEach(NextSessionIntent.allCases) { option in
                    SessionOptionCard(title: option.rawValue, isSelected: option == intent) {
                        // Selection only. Advancing stays with Continue, matching every
                        // other onboarding step and preserving the tap-through rhythm:
                        // a user mashing Continue proceeds on the preselected answer.
                        withAnimation(.easeOut(duration: 0.15)) { intent = option }
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 20) {
                OnboardingStepDots(pageIndex: pageIndex, totalPages: totalPages)

                Button {
                    onContinue(intent)
                } label: {
                    Text("Continue")
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
        }
    }
}

// MARK: - Step 2: the reminder ask

struct OnboardingReminderStep: View {
    let pageIndex: Int
    let totalPages: Int
    let intent: NextSessionIntent
    /// When true, draws a replica of the iOS dialog instead of asking for real. Only
    /// the standalone dev preview sets this — the system prompt appears once per
    /// install, so iterating on this screen would otherwise consume it for good.
    var usesMockPermissionPrompt: Bool = false
    let onResolved: (PermissionOutcome) -> Void

    @State private var showSystemAlert = false
    /// One-way latch: every path that sets it also resolves the step, so it cannot
    /// strand the user. The mock alert has no dismiss-without-answering path.
    @State private var isResolving = false
    /// Frozen on appear so the banner's timestamp doesn't drift mid-screen.
    @State private var now = Date()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    // Confirms the answer rather than re-asking it.
                    Text(intent.confirmationHeadline)
                        .font(.bebasNeue(size: 34))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    (
                        Text("Get ").foregroundStyle(.white.opacity(0.7))
                        + Text("one reminder").foregroundStyle(Color.appAccent)
                        + Text(intent.reminderSublineTail).foregroundStyle(.white.opacity(0.7))
                    )
                    .font(.inter(size: 17))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                }

                Spacer().frame(height: 36)

                // Shows the actual thing being offered. Seeing a single banner is the
                // argument that this isn't spam.
                NotificationPreviewBanner(
                    timeLabel: intent.bannerTimeLabel(from: now),
                    message: intent.bannerBody
                )
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 16) {
                    OnboardingStepDots(pageIndex: pageIndex, totalPages: totalPages)

                    VStack(spacing: 14) {
                        Button {
                            // Same latch as the other self-advancing steps. Without it,
                            // repeated taps spawn concurrent requests that each call
                            // `onResolved`, completing onboarding more than once and
                            // double-firing the scheduled event.
                            guard !isResolving else { return }
                            isResolving = true
                            if usesMockPermissionPrompt {
                                showSystemAlert = true
                            } else {
                                Task { await requestAndSchedule() }
                            }
                        } label: {
                            Text("Remind me")
                                .font(.interSemiBold(size: 16))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.appAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        // Quiet, but deliberately still legible. Burying this reads as a
                        // dark pattern to exactly the skeptical users worth keeping.
                        //
                        // Skipping leaves authorization `.notDetermined`, so the Progress
                        // tab's ask stays reachable for exactly these users.
                        Button {
                            guard !isResolving else { return }
                            isResolving = true
                            // Only tracked for the real flow — the dev preview would
                            // otherwise pollute the funnel with internal runs.
                            if !usesMockPermissionPrompt {
                                AmplitudeService.shared.track(
                                    .notificationPermissionSkipped(
                                        source: "onboarding",
                                        intent: intent.rawValue
                                    )
                                )
                            }
                            onResolved(.skipped)
                        } label: {
                            Text("No thanks")
                                .font(.inter(size: 15))
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 46)
            }

            if showSystemAlert {
                MockSystemPermissionAlert(
                    onAllow: { showSystemAlert = false; onResolved(.granted) },
                    onDeny: { showSystemAlert = false; onResolved(.denied) }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showSystemAlert)
        .onAppear { now = Date() }
    }

    /// Ask for real, and schedule only on a grant.
    ///
    /// The fire date is computed here rather than reusing the one the banner previewed,
    /// so a user who sits on this screen for a while still gets an accurate offset for
    /// the "Today" case.
    @MainActor
    private func requestAndSchedule() async {
        let granted = await PushNotificationService.shared.requestAuthorization(source: "onboarding")
        guard granted else {
            onResolved(.denied)
            return
        }
        let firesAt = Date()
        PushNotificationService.shared.scheduleSessionReminder(
            intent: intent,
            at: intent.targetDate(from: firesAt),
            now: firesAt
        )
        onResolved(.granted)
    }
}

// MARK: - Shared chrome

/// The progress dots the later onboarding steps each render for themselves.
struct OnboardingStepDots: View {
    let pageIndex: Int
    let totalPages: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == pageIndex ? Color.appAccent : Color.white.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Option card

/// Selected state uses an amber border plus a faint amber wash rather than a solid
/// amber fill, so it can't compete with the amber Continue button for primacy — on a
/// screen whose point is that tapping through lands on a good default, the CTA has to
/// stay the loudest element.
private struct SessionOptionCard: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.inter(size: 17))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.appAccent : .white.opacity(0.2))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.appAccent.opacity(0.12) : Color(white: 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.appAccent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Faux iOS notification banner

/// A drawn replica of a delivered iOS notification, showing the exact copy the user
/// would receive. Uses iOS banner styling, not app styling — it represents something
/// the system renders, not something we draw.
private struct NotificationPreviewBanner: View {
    let timeLabel: String
    /// Named `message`, not `body` — the latter collides with SwiftUI's `var body`.
    let message: String

    /// The real app icon, pulled from the built bundle. Xcode synthesizes
    /// `CFBundleIcons` into the compiled Info.plist from the asset catalog, so the
    /// last entry in `CFBundleIconFiles` is loadable by name even though the source
    /// Info.plist has no such key. Falls back to the bull mark if that ever changes.
    private static let appIcon: UIImage? = {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last
        else { return nil }
        return UIImage(named: name)
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let icon = Self.appIcon {
                    Image(uiImage: icon).resizable()
                } else {
                    // Fallback only — the previous stand-in inverted the real icon's
                    // colours, which is exactly what we're fixing.
                    Image("LiftTheBullIcon").resizable().renderingMode(.original)
                }
            }
            .scaledToFill()
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("LIFT THE BULL")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .tracking(0.4)
                    Spacer()
                    Text(timeLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(12)
        .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}

// MARK: - Mock iOS permission alert

/// Drawn replica of the iOS notification-permission dialog, so the flow can be walked
/// end to end without consuming the real one-shot system prompt. Intentionally uses
/// system blue and SF sizing rather than app styling — it should NOT look like our UI.
private struct MockSystemPermissionAlert: View {
    let onAllow: () -> Void
    let onDeny: () -> Void

    private let systemBlue = Color(red: 0.04, green: 0.52, blue: 1.0)

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("“Lift the Bull” Would Like to Send You Notifications")
                        .font(.system(size: 17, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)

                    Text("Notifications may include alerts, sounds and icon badges. These can be configured in Settings.")
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 16)
                .padding(.top, 19)
                .padding(.bottom, 16)

                Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5)

                HStack(spacing: 0) {
                    Button(action: onDeny) {
                        Text("Don't Allow")
                            .font(.system(size: 17))
                            .foregroundStyle(systemBlue)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    Rectangle().fill(.white.opacity(0.18)).frame(width: 0.5, height: 44)
                    Button(action: onAllow) {
                        Text("Allow")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(systemBlue)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(width: 270)
            .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        }
    }
}

// MARK: - Standalone dev preview

/// Just these two screens, for fast iteration without clicking through all seven
/// onboarding pages. Composes the SAME step views the real flow uses, then shows a
/// debrief of what would have been stored.
struct SessionIntentMockFlow: View {
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0
    @State private var intent: NextSessionIntent = .tomorrow
    @State private var outcome: PermissionOutcome = .notAsked
    @State private var now = Date()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 60)

                Group {
                    switch page {
                    case 0:
                        OnboardingSessionIntentStep(pageIndex: 0, totalPages: 3, intent: $intent) { _ in
                            // Every answer now reaches the reminder screen; "Not sure yet"
                            // gets its own open-ended state there rather than skipping.
                            outcome = .notAsked
                            withAnimation { page = 1 }
                        }
                    case 1:
                        // Mock prompt here so iterating on this screen doesn't consume
                        // the install's one real system dialog.
                        OnboardingReminderStep(
                            pageIndex: 1,
                            totalPages: 3,
                            intent: intent,
                            usesMockPermissionPrompt: true
                        ) { resolved in
                            outcome = resolved
                            withAnimation { page = 2 }
                        }
                    default:
                        debriefScreen
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: page)
        .onAppear { now = Date() }
    }

    private var debriefScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("WHAT WOULD BE STORED")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                Text("Mock only — nothing was saved.")
                    .font(.inter(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer().frame(height: 32)

            VStack(alignment: .leading, spacing: 16) {
                MockDebriefRow(label: "nextSessionIntent", value: "\"\(intent.rawValue)\"")
                MockDebriefRow(
                    label: "targetTimestamp",
                    value: Self.debugFormatter.string(from: intent.targetDate(from: now))
                )
                MockDebriefRow(label: "permission", value: outcome.rawValue)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            Spacer()

            Button { dismiss() } label: {
                Text("Done")
                    .font(.interSemiBold(size: 16))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
    }

    private static let debugFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d, h:mm a"
        return f
    }()
}

private struct MockDebriefRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.interSemiBold(size: 10))
                .foregroundStyle(Color(white: 0.5))
            Text(value)
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
