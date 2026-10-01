//
//  PushNotificationService.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/18/26.
//
//  Owns notification authorization, APNs token registration, and the one-shot
//  session reminder scheduled from the onboarding next-session question.
//
//  Note on scope: the backend has no APNs send path today — `apnsDeviceToken` is
//  persisted on the user-properties row and read by nothing. The session reminder is
//  therefore a LOCAL notification scheduled on-device. Token capture is groundwork.
//

import UIKit
import UserNotifications

class PushNotificationService {
    static let shared = PushNotificationService()

    /// Legacy one-shot marker. No longer read: it was set BEFORE the system prompt
    /// resolved, so it meant "we asked", not "we got an answer" — which made it unsafe
    /// as a proxy for authorization and left Settings' "Enable" row a no-op once the
    /// Progress tab had consumed it. Authorization status is queried directly instead.
    private let hasRequestedKey = "hasRequestedNotificationPermission"
    private let lastSentTokenKey = "lastSentAPNSDeviceToken"

    /// Single identifier — the reminder is one-shot, so re-scheduling replaces rather
    /// than accumulates. Nothing else in the app schedules notifications.
    static let sessionReminderIdentifier = "session-reminder"

    /// Remembers which answer produced the pending reminder, so the open/cancel events
    /// can name it. Cleared with the schedule.
    private let reminderIntentKey = "sessionReminderIntent"

    private init() {}

    // MARK: - Authorization

    /// Current authorization status, straight from the system.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Request permission and report the outcome, so callers can act on a grant.
    ///
    /// `source` identifies the ask site for analytics: "onboarding" / "progress_tab" /
    /// "settings". Returns the existing answer without re-prompting when the status is
    /// already determined — iOS shows its dialog once per install regardless.
    @discardableResult
    func requestAuthorization(source: String) async -> Bool {
        let status = await authorizationStatus()
        guard status == .notDetermined else {
            return status == .authorized || status == .provisional || status == .ephemeral
        }

        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false

        AmplitudeService.shared.track(.notificationPermissionAnswered(granted: granted, source: source))

        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        return granted
    }

    /// Fire-and-forget ask used by the Progress tab and Settings.
    ///
    /// Gated on the real authorization status rather than a stored flag, so it is a
    /// no-op for anyone who already answered — which makes it reach exactly the users
    /// who finished onboarding without answering (i.e. tapped "No thanks").
    func requestPermissionIfNeeded(source: String = "progress_tab") {
        Task { await requestAuthorization(source: source) }
    }

    // MARK: - Session reminder

    /// Staging fires every reminder 5 minutes out regardless of the chosen intent, so
    /// the whole path (delivery, foreground banner, tap routing, tier-unlock cancel)
    /// can be exercised in one sitting instead of waiting until 11am tomorrow.
    /// Production always honours the real target.
    private static let stagingTestLeadSeconds: TimeInterval = 5 * 60

    private func effectiveFireDate(_ requested: Date, now: Date) -> Date {
        guard APIConfig.environment == "staging" else { return requested }
        return now.addingTimeInterval(Self.stagingTestLeadSeconds)
    }

    /// Schedule the one-time reminder. Replaces any existing one.
    func scheduleSessionReminder(intent: NextSessionIntent, at fireDate: Date, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.sessionReminderIdentifier])

        let scheduledFor = effectiveFireDate(fireDate, now: now)

        let content = UNMutableNotificationContent()
        content.title = "Lift the Bull"
        content.body = intent.bannerBody
        content.sound = .default

        // Calendar rather than time-interval so the reminder holds its wall-clock time
        // if the device sleeps or the user travels.
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: scheduledFor
        )
        let request = UNNotificationRequest(
            identifier: Self.sessionReminderIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )

        center.add(request) { error in
            if let error {
                print("Failed to schedule session reminder: \(error)")
                return
            }
            UserDefaults.standard.set(intent.rawValue, forKey: self.reminderIntentKey)
            AmplitudeService.shared.track(.sessionReminderScheduled(
                intent: intent.rawValue,
                hoursAhead: intent.hoursAhead(from: now)
            ))
        }
    }

    /// Withdraw a pending reminder. Safe to call when none exists — the event only
    /// fires if something was actually cancelled.
    func cancelSessionReminder(reason: String) {
        guard let intent = UserDefaults.standard.string(forKey: reminderIntentKey) else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.sessionReminderIdentifier])
        UserDefaults.standard.removeObject(forKey: reminderIntentKey)
        AmplitudeService.shared.track(.sessionReminderCancelled(reason: reason))
        print("Cancelled session reminder (\(intent)) — \(reason)")
    }

    /// The answer behind the pending reminder, for the open event.
    var pendingReminderIntent: String? {
        UserDefaults.standard.string(forKey: reminderIntentKey)
    }

    /// Clears local reminder bookkeeping without emitting a cancellation event. Used
    /// once the notification has actually been delivered.
    func clearReminderRecord() {
        UserDefaults.standard.removeObject(forKey: reminderIntentKey)
    }

    // MARK: - APNs token

    /// Called from `AppDelegate` when APNs delivers a new device token.
    /// Syncs to backend only if the token has changed since last sync.
    func handleNewToken(_ token: String) {
        let lastSent = UserDefaults.standard.string(forKey: lastSentTokenKey)
        guard token != lastSent else { return }

        Task {
            do {
                let _ = try await APIService.shared.registerDeviceToken(token)
                UserDefaults.standard.set(token, forKey: lastSentTokenKey)
                print("APNS token synced to backend: \(token.prefix(8))...")
            } catch {
                print("Failed to sync APNS token: \(error)")
            }
        }
    }

    /// Silently re-register for remote notifications on app launch
    /// if the user previously granted permission. No prompt shown.
    func refreshTokenIfAuthorized() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - Cleanup

    /// Full teardown on logout / account deletion.
    func clearOnLogout() {
        cancelSessionReminder(reason: "logout")
        UserDefaults.standard.removeObject(forKey: lastSentTokenKey)
        UserDefaults.standard.removeObject(forKey: hasRequestedKey)
        // The declared session intent belongs to the account that answered, not the device.
        NextSessionIntent.clearDeclared()
    }
}
