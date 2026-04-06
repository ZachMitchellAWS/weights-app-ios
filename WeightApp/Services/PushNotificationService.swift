//
//  PushNotificationService.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/18/26.
//

import UIKit
import UserNotifications

class PushNotificationService {
    static let shared = PushNotificationService()

    private let hasRequestedKey = "hasRequestedNotificationPermission"
    private let lastSentTokenKey = "lastSentAPNSDeviceToken"

    private init() {}

    /// Request notification permission if we haven't already prompted.
    /// Call from InsightsView on first appearance — guarded by UserDefaults flag.
    func requestPermissionIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: hasRequestedKey) else { return }
        UserDefaults.standard.set(true, forKey: hasRequestedKey)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    /// Called from AppDelegate when APNS delivers a new device token.
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
}
