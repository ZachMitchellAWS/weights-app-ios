//
//  StrengthTabView.swift
//  WeightApp
//
//  Top-level Strength tab. Was the default sub-tab of the old Progress tab, which is
//  why it inherits the notification permission ask that used to live on `TrendsView`.
//

import SwiftUI

struct StrengthTabView: View {
    @ObservedObject var selectedSetData: SelectedSetData
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Preserves the 10pt the old shared header row contributed even when
                // its history button was hidden, so content sits where it always has.
                Color.clear.frame(height: 10)

                // `AudioPlayerManager` is `@Observable`, so passing the singleton
                // directly still establishes tracking wherever it is read in a body.
                BalanceView(
                    selectedTab: $selectedTab,
                    audioPlayer: AudioPlayerManager.shared,
                    selectedSetData: selectedSetData
                )
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            // The backstop ask. Onboarding is where permission is normally requested, but
            // that step is skippable — anyone who tapped "No thanks" there would otherwise
            // never be asked again outside Settings, which nobody opens, and so would never
            // produce an APNs token.
            //
            // Safe to fire on every appearance despite being conceptually one-shot:
            // `requestPermissionIfNeeded` reads the REAL authorization status and returns
            // immediately unless it is `.notDetermined`. That is deliberately not a stored
            // flag — the old `hasRequestedNotificationPermission` key was written before the
            // system dialog resolved, so it recorded "we asked" rather than "they answered",
            // and it silently consumed Settings' Enable row. iOS also shows its own dialog
            // once per install regardless, so the user cannot be nagged by this.
            //
            // The token reaches the backend without anything further here: a grant calls
            // `registerForRemoteNotifications()`, the AppDelegate hands the token to
            // `handleNewToken`, and that POSTs it (deduped against `lastSentAPNSDeviceToken`).
            .onAppear {
                PushNotificationService.shared.requestPermissionIfNeeded(source: "strength_tab")
            }
        }
    }
}
