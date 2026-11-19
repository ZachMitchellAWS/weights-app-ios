//
//  TierUnlockUpsellPresenter.swift
//  WeightApp
//
//  Raises the premium paywall once, ten seconds after a user unlocks their starting strength
//  tier, wherever they happen to be in the app.
//
//  WHY THIS MOMENT. Unlocking the tier is the first time the app has told the user something
//  about themselves they did not already know, and it is the strongest predictor the funnel has:
//  tier unlock fires at ~16.8% of users and predicts a trial start at 4.6x the base rate (18% vs
//  3.9%, p=1.19e-05) — the same finding that made it a Google Ads conversion proxy. Showing the
//  offer immediately after is showing it at the one point where the product has just proven
//  itself.
//
//  WHY TEN SECONDS AND NOT ZERO. The unlock already draws its own celebration, and a paywall
//  landing on top of it would read as the app interrupting its own good news to ask for money.
//  Ten seconds is long enough for that to land and be dismissed, short enough that the
//  connection between the two is still obvious.
//
//  WHY A PRESENTER RATHER THAN A SHEET ON `CheckInView`. "Regardless of where they are in the
//  app" is the requirement, and the unlock is detected deep inside the Lift tab. This is the
//  same shape as `TutorialPresenter` — a tiny observable the app root watches so a child view
//  can raise something that covers the whole window. Kept separate from `TutorialPresenter`
//  because it owns a timer and a persisted once-ever guard, neither of which belongs in a
//  coordinator named for tutorials.
//

import Foundation
import Combine

@MainActor
final class TierUnlockUpsellPresenter: ObservableObject {
    static let shared = TierUnlockUpsellPresenter()

    /// Ten seconds after the unlock. See the file header for why not zero.
    static let delay: TimeInterval = 10

    /// Watched by `WeightAppApp`, which owns the cover.
    @Published var isPresented = false

    /// ONCE EVER, PERSISTED. `markStartingTierUnlocked` is itself once-ever — its guard on
    /// `hasMetStrengthTierConditions` has no un-set path anywhere in the app — so this is
    /// belt-and-braces rather than the primary mechanism. It exists because the two are
    /// separated by ten seconds and a process boundary: if the schedule were ever moved, or the
    /// unlock re-detected after a reinstall-and-resync, this is what stops a second showing.
    private static let shownKey = "tierUnlockUpsellShown"

    private var pending: Task<Void, Never>?

    private init() {}

    var hasShown: Bool { UserDefaults.standard.bool(forKey: Self.shownKey) }

    /// Called from the unlock itself. Starts the clock.
    ///
    /// - Parameter isPremium: skip entirely for subscribers. Evaluated at SCHEDULE time rather
    ///   than at fire time, which is a deliberate simplification: reaching premium inside the
    ///   ten-second window requires seeing a paywall, buying, and returning, which is not a
    ///   sequence that fits. A premium user who somehow got here would see a paywall for
    ///   something they own, so if this assumption ever stops holding, re-check on fire.
    func scheduleAfterUnlock(isPremium: Bool) {
        guard !isPremium, !hasShown, pending == nil else { return }

        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.delay))
            guard !Task.isCancelled else { return }
            guard let self, !self.hasShown else { return }
            UserDefaults.standard.set(true, forKey: Self.shownKey)
            self.isPresented = true
        }
    }

    /// `Task.sleep` suspends rather than dies when the app backgrounds, so a user who leaves
    /// mid-window gets the paywall when they return — which is correct, since the unlock is
    /// still the last thing that happened to them. A user who KILLS the app inside the window
    /// never sees it at all: the flag is only written at fire time, but nothing re-schedules on
    /// launch, because "ten seconds after the unlock" stops being true once a relaunch has
    /// happened in between.
    func dismiss() {
        isPresented = false
    }

    /// Developer menu only.
    func resetForTesting() {
        pending?.cancel()
        pending = nil
        isPresented = false
        UserDefaults.standard.removeObject(forKey: Self.shownKey)
    }
}
