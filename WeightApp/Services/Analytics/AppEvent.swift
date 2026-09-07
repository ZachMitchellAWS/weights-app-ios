//
//  AppEvent.swift
//  WeightApp
//
//  Typed Amplitude event catalog. One case per tracked user action; `name` and
//  `properties` produce the wire payload sent by `AmplitudeService.track(_:)`.
//
//  Naming convention (Amplitude best practice):
//    • Event names are Title-Case "Object Action"  → "Set Logged"
//    • Property keys are snake_case                 → "is_baseline_set"
//  Add a new event by adding a case here + one `AmplitudeService.shared.track(...)`
//  call at the site of the action. Keep names/keys stable once shipped — renaming
//  an event splits its history in Amplitude.
//
//  NOT in this catalog:
//    • Common properties (environment, app_version, build_number) — stamped on
//      every event by GlobalPropertiesPlugin (see AmplitudeService).
//    • Session start/end + app install/open/update — autocaptured by the SDK.
//

import Foundation

enum AppEvent {
    // Auth
    case signedUp(method: String)
    case signedIn(method: String)

    // Onboarding funnel
    case onboardingStepViewed(index: Int, name: String)
    case onboardingCompleted

    // Core actions
    case setLogged(SetLogProperties)
    /// Fired IN ADDITION to `setLogged` when the set is a baseline (first weighted
    /// set for that exercise). `fundamentalName` is set for the five strength-tier
    /// lifts so each gets its own event name ("Baseline Set Logged - Deadlifts");
    /// nil for any other exercise → generic "Baseline Set Logged".
    case baselineSetLogged(fundamentalName: String?, properties: SetLogProperties)
    /// The popup that reveals a lift's first estimated 1RM. Replaces the tier journey's
    /// silent "Nice Work" counter, which fired no analytics at all.
    case baselineRevealShown(exercise: String, tier: String, liftsLogged: Int)
    case baselineRevealNextUpTapped(exercise: String, liftsLogged: Int)
    /// The undo. Pairs with `baselineSetLogged`, which has already fired and cannot be
    /// retracted — the ratio between the two is the measurement of how often people are
    /// entering a number to see what happens rather than logging real work.
    case baselineRevealUndone(exercise: String, estimated1RM: Double)
    /// The one-time starting-tier unlock (generic — tier is a property, not in the name).
    case startingStrengthTierUnlocked(tier: String)
    /// A subsequent overall-tier rise after the starting tier (tier-specific event name).
    case strengthTierAchieved(tier: String, previousTier: String, drivingExercise: String)
    /// A per-exercise tier crossing after the starting tier (exercise+tier in the name).
    case strengthMilestoneAchieved(exercise: String, tier: String, estimated1RM: Double?)
    case exerciseCreated(loadType: String, movementType: String?, isCustom: Bool)

    /// Pre-unlock sample card appeared on the Strength tab. `liftsLogged` (0-5) is the
    /// user's REAL progress, not the sample's, so the funnel can show where people stall.
    case strengthSampleShown(widget: String, liftsLogged: Int)
    /// The sample's unlock footer was tapped, sending the user to the Lift tab. Paired
    /// with the event above this gives the sample's conversion rate — the reason the
    /// card exists. `tabSwitched` alone can't attribute this, since a footer tap and an
    /// ordinary Lift-tab tap are identical there.
    case strengthSampleUnlockTapped(widget: String, liftsLogged: Int)

    // Navigation / engagement
    case tabSwitched(tab: String)
    case screenViewed(name: String)
    case buttonTapped(name: String, context: String?)

    // "Ready to Lift?" next-focus nudge
    /// `trigger` distinguishes the once-per-launch automatic appearance ("auto")
    /// from the user tapping the next-focus chip ("manual") — different intent, so
    /// they must not be pooled when judging whether the nudge works.
    case readyToLiftShown(focusExercise: String, trigger: String)
    /// The CTA that sends the user to that exercise on the Lift tab. Pair with
    /// `readyToLiftShown` for the conversion rate of the nudge.
    case readyToLiftCTATapped(focusExercise: String)
    /// Closed without acting, via the X or the scrim.
    case readyToLiftDismissed(focusExercise: String)
    /// The "Plan my whole session" CTA. Previously fired `readyToLiftDismissed`, which both
    /// inflated the dismissal rate and hid the fact that anyone was taking this route at all.
    /// `isPremium` matters because the two states go to different places — the Session tab
    /// versus the paywall.
    case readyToLiftSessionTapped(focusExercise: String, isPremium: Bool)

    // Sets widget engagement
    /// The "How this works" disclosure under the set rows. `isExpanded` false is a
    /// collapse, so open/close can be told apart in one event.
    case setsHowItWorksToggled(isExpanded: Bool)
    /// The "Open the full Sets Guide" pill inside that disclosure.
    case setsGuideOpened
    /// A set row tapped to load its values into the log inputs. `source` is
    /// "suggestion" for an upcoming planned row or "logged_set" for a completed one.
    case setPresetLoaded(effort: String, source: String)

    // Session reminder (onboarding next-session question → local notification)
    /// Answer to the iOS permission dialog. `source` is where it was asked from:
    /// "onboarding" / "progress_tab" / "settings".
    case notificationPermissionAnswered(granted: Bool, source: String)
    /// "No thanks" in onboarding — declined WITHOUT the system dialog being shown, so
    /// authorization stays `.notDetermined` and the user is still reachable later.
    /// Deliberately not folded into `notificationPermissionAnswered(granted: false)`:
    /// that means a hard, permanent `.denied`, and conflating the two would make the
    /// recoverable population impossible to size.
    case notificationPermissionSkipped(source: String, intent: String)
    /// A one-shot local reminder was scheduled. `hoursAhead` is the lead time, so
    /// the four intents can be compared without re-deriving dates.
    case sessionReminderScheduled(intent: String, hoursAhead: Int)
    /// The delivered reminder was tapped. Pair with Scheduled for the open rate.
    /// The reminder was delivered while the app was FOREGROUNDED — the only delivery
    /// signal iOS gives for a local notification. Background delivery is unobservable,
    /// so this is a partial view: absence does not mean undelivered.
    case sessionReminderDelivered(intent: String)
    case sessionReminderOpened(intent: String)
    /// Withdrawn before firing: "tier_unlocked" / "logout".
    case sessionReminderCancelled(reason: String)

    // Strength tab engagement
    case strengthInsightPlayTapped(action: String, tier: String)

    // Generated sessions (Session tab). Distinct from the `sessionReminder*` events
    // above, which are about the onboarding notification, not a generated session.
    //
    // `durationSeconds` is the point of these: generation is synchronous behind API
    // Gateway's fixed 29s ceiling, and this is the only place real client-side latency —
    // network included — is visible. CloudWatch sees the Lambda's time, never the user's.
    case sessionGenerationRequested(trigger: String)
    case sessionGenerationSucceeded(trigger: String, durationSeconds: Double, liftCount: Int)
    case sessionGenerationFailed(trigger: String, durationSeconds: Double, reason: String)

    // Session completion moments (Lift tab popups). `kind` is "lift" or "session".
    //
    // The ratio of CTA-tapped to dismissed is the number that matters: this is a popup in
    // the middle of a workout, and a rising dismissal rate is the signal that it has become
    // something to swat away rather than read.
    case sessionCelebrationShown(kind: String)
    case sessionCelebrationCTATapped(kind: String)
    case sessionCelebrationDismissed(kind: String)

    // Premium lock states
    case lockedWidgetTapped(feature: String)

    // "How it works" tutorial funnel
    case tutorialShown(resourceId: String)
    case tutorialWatchTapped(resourceId: String)
    case tutorialSkipped(resourceId: String)
    case tutorialClosed(resourceId: String, durationSeconds: Double, watchedToEnd: Bool)

    // Premium upsell / purchase funnel
    //
    // `source` is on every upsell event because the paywall is presented from nine places and
    // four of them open on the same page — post-onboarding (which every new user sees) was
    // otherwise indistinguishable from a deliberate tap on a locked feature, and those two
    // convert nothing alike.
    case premiumUpsellShown(source: String, initialPage: Int, initialFeature: String)
    case upsellPageViewed(source: String, feature: String, index: Int)
    case upsellPlanSelected(source: String, plan: String)
    case upsellDismissed(source: String, feature: String, secondsOnScreen: Double)
    case purchaseStarted(productId: String, plan: String, isFreeTrial: Bool)
    /// Started but not completed. `reason` is "cancelled" (user backed out of the StoreKit
    /// sheet), "failed" (StoreKit or the entitlements call threw) or "product_unavailable".
    case purchaseAbandoned(productId: String, plan: String, reason: String)
    case purchaseCompleted(productId: String, transactionId: String, isRenewal: Bool, isFreeTrial: Bool, price: Double?, currency: String)

    /// Amplitude event type (Title-Case "Object Action").
    var name: String {
        switch self {
        case .signedUp: return "Signed Up"
        case .signedIn: return "Signed In"
        case .onboardingStepViewed: return "Onboarding Step Viewed"
        case .onboardingCompleted: return "Onboarding Completed"
        case .setLogged: return "Set Logged"
        case let .baselineSetLogged(fundamentalName, _):
            if let fundamentalName { return "Baseline Set Logged - \(fundamentalName)" }
            return "Baseline Set Logged"
        case .baselineRevealShown: return "Baseline Reveal Shown"
        case .baselineRevealNextUpTapped: return "Baseline Reveal Next Up Tapped"
        case .baselineRevealUndone: return "Baseline Reveal Undone"
        case .startingStrengthTierUnlocked: return "Strength Tier Unlocked - Starting"
        case let .strengthTierAchieved(tier, _, _): return "Strength Tier Unlocked - \(tier)"
        case let .strengthMilestoneAchieved(exercise, tier, _): return "Strength Milestone Achieved - \(exercise) \(tier)"
        case .exerciseCreated: return "Exercise Created"
        case .strengthSampleShown: return "Strength Sample Shown"
        case .strengthSampleUnlockTapped: return "Strength Sample Unlock Tapped"
        case let .tabSwitched(tab): return "Tab Switched - \(tab)"
        case .screenViewed: return "Screen Viewed"
        case .buttonTapped: return "Button Tapped"
        case .readyToLiftShown: return "Ready To Lift Shown"
        case .readyToLiftCTATapped: return "Ready To Lift CTA Tapped"
        case .readyToLiftDismissed: return "Ready To Lift Dismissed"
        case .readyToLiftSessionTapped: return "Ready To Lift Session Tapped"
        case .setsHowItWorksToggled: return "Sets How It Works Toggled"
        case .setsGuideOpened: return "Sets Guide Opened"
        case .setPresetLoaded: return "Set Preset Loaded"
        case .notificationPermissionAnswered: return "Notification Permission Answered"
        case .notificationPermissionSkipped: return "Notification Permission Skipped"
        case .sessionReminderScheduled: return "Session Reminder Scheduled"
        case .sessionReminderDelivered: return "Session Reminder Delivered"
        case .sessionReminderOpened: return "Session Reminder Opened"
        case .sessionReminderCancelled: return "Session Reminder Cancelled"
        case .strengthInsightPlayTapped: return "Strength Insight Play Tapped"
        case .lockedWidgetTapped: return "Locked Widget Tapped"
        case .tutorialShown: return "Tutorial Shown"
        case .tutorialWatchTapped: return "Tutorial Watch Tapped"
        case .tutorialSkipped: return "Tutorial Skipped"
        case .sessionCelebrationShown: return "Session Celebration Shown"
        case .sessionCelebrationCTATapped: return "Session Celebration CTA Tapped"
        case .sessionCelebrationDismissed: return "Session Celebration Dismissed"
        case .sessionGenerationRequested: return "Session Generation Requested"
        case .sessionGenerationSucceeded: return "Session Generation Succeeded"
        case .sessionGenerationFailed: return "Session Generation Failed"
        case .tutorialClosed: return "Tutorial Closed"
        case .premiumUpsellShown: return "Premium Upsell Shown"
        case .upsellPageViewed: return "Upsell Page Viewed"
        case .upsellPlanSelected: return "Upsell Plan Selected"
        case .upsellDismissed: return "Upsell Dismissed"
        case .purchaseStarted: return "Purchase Started"
        case .purchaseAbandoned: return "Purchase Abandoned"
        case .purchaseCompleted: return "Purchase Completed"
        }
    }

    /// Event-specific properties (snake_case keys). Common props are added globally.
    var properties: [String: Any] {
        switch self {
        case let .signedUp(method), let .signedIn(method):
            return ["method": method]

        case let .onboardingStepViewed(index, name):
            return ["step_index": index, "step_name": name]

        case .onboardingCompleted:
            return [:]

        case let .setLogged(properties):
            return properties.dictionary

        case let .baselineSetLogged(_, properties):
            return properties.dictionary

        case let .startingStrengthTierUnlocked(tier):
            return ["tier": tier]

        case let .strengthTierAchieved(tier, previousTier, drivingExercise):
            return ["tier": tier, "previous_tier": previousTier, "driving_exercise": drivingExercise]

        case let .strengthMilestoneAchieved(exercise, tier, estimated1RM):
            var props: [String: Any] = ["exercise": exercise, "tier": tier]
            if let estimated1RM { props["estimated_1rm"] = estimated1RM }
            return props

        case let .exerciseCreated(loadType, movementType, isCustom):
            var props: [String: Any] = ["load_type": loadType, "is_custom": isCustom]
            if let movementType { props["movement_type"] = movementType }
            return props

        case let .tabSwitched(tab):
            return ["tab": tab]

        case let .screenViewed(name):
            return ["screen_name": name]

        case let .buttonTapped(name, context):
            var props: [String: Any] = ["button": name]
            if let context { props["context"] = context }
            return props

        case let .readyToLiftShown(focusExercise, trigger):
            return ["focus_exercise": focusExercise, "trigger": trigger]

        case let .readyToLiftSessionTapped(focusExercise, isPremium):
            return ["focus_exercise": focusExercise, "is_premium": isPremium]

        case let .readyToLiftCTATapped(focusExercise),
             let .readyToLiftDismissed(focusExercise):
            return ["focus_exercise": focusExercise]

        case let .setsHowItWorksToggled(isExpanded):
            return ["is_expanded": isExpanded]

        case .setsGuideOpened:
            return [:]

        case let .setPresetLoaded(effort, source):
            return ["effort": effort, "source": source]

        case let .notificationPermissionAnswered(granted, source):
            return ["granted": granted, "source": source]

        case let .notificationPermissionSkipped(source, intent):
            return ["source": source, "intent": intent]

        case let .baselineRevealShown(exercise, tier, liftsLogged):
            return ["exercise": exercise, "tier": tier, "lifts_logged": liftsLogged]

        case let .baselineRevealNextUpTapped(exercise, liftsLogged):
            return ["exercise": exercise, "lifts_logged": liftsLogged]

        case let .baselineRevealUndone(exercise, estimated1RM):
            return ["exercise": exercise, "estimated_1rm": estimated1RM]

        case let .strengthSampleShown(widget, liftsLogged):
            return ["widget": widget, "lifts_logged": liftsLogged]

        case let .strengthSampleUnlockTapped(widget, liftsLogged):
            return ["widget": widget, "lifts_logged": liftsLogged]

        case let .sessionReminderScheduled(intent, hoursAhead):
            return ["intent": intent, "hours_ahead": hoursAhead]

        case let .sessionReminderDelivered(intent):
            return ["intent": intent]

        case let .sessionReminderOpened(intent):
            return ["intent": intent]

        case let .sessionReminderCancelled(reason):
            return ["reason": reason]

        case let .strengthInsightPlayTapped(action, tier):
            return ["action": action, "tier": tier]

        case let .lockedWidgetTapped(feature):
            return ["feature": feature]

        case let .tutorialShown(resourceId),
             let .tutorialWatchTapped(resourceId),
             let .tutorialSkipped(resourceId):
            return ["resource_id": resourceId]

        case let .sessionCelebrationShown(kind),
             let .sessionCelebrationCTATapped(kind),
             let .sessionCelebrationDismissed(kind):
            return ["kind": kind]

        case let .sessionGenerationRequested(trigger):
            return ["trigger": trigger]

        case let .sessionGenerationSucceeded(trigger, durationSeconds, liftCount):
            return [
                "trigger": trigger,
                "duration_seconds": durationSeconds,
                "lift_count": liftCount,
            ]

        case let .sessionGenerationFailed(trigger, durationSeconds, reason):
            return [
                "trigger": trigger,
                "duration_seconds": durationSeconds,
                "reason": reason,
            ]

        case let .tutorialClosed(resourceId, durationSeconds, watchedToEnd):
            return [
                "resource_id": resourceId,
                "duration_seconds": durationSeconds,
                "watched_to_end": watchedToEnd,
            ]

        case let .premiumUpsellShown(source, initialPage, initialFeature):
            // `initial_page` is kept for continuity with existing charts, but it is an INDEX and
            // the carousel has been reordered — page 1 was Weekly Progress Narratives before it
            // was Strength Balance. Segment on `initial_feature` for anything spanning that
            // change; the index is only safe within a single release.
            return ["source": source, "initial_page": initialPage, "initial_feature": initialFeature]

        case let .upsellPageViewed(source, feature, index):
            return ["source": source, "feature": feature, "page_index": index]

        case let .upsellPlanSelected(source, plan):
            return ["source": source, "plan": plan]

        case let .upsellDismissed(source, feature, secondsOnScreen):
            return ["source": source, "feature": feature, "seconds_on_screen": secondsOnScreen]

        case let .purchaseStarted(productId, plan, isFreeTrial):
            return ["product_id": productId, "plan": plan, "is_free_trial": isFreeTrial]

        case let .purchaseAbandoned(productId, plan, reason):
            return ["product_id": productId, "plan": plan, "reason": reason]

        case let .purchaseCompleted(productId, transactionId, isRenewal, isFreeTrial, price, currency):
            var props: [String: Any] = [
                "product_id": productId,
                "transaction_id": transactionId,
                "is_renewal": isRenewal,
                "is_free_trial": isFreeTrial,
                "currency": currency,
            ]
            if let price { props["price"] = price }
            return props
        }
    }
}

/// Shared property payload for `Set Logged` and `Baseline Set Logged` events.
struct SetLogProperties {
    let exerciseName: String
    let exerciseId: String
    let loadType: String
    let reps: Int
    let weight: Double
    let isBaselineSet: Bool
    let estimated1RM: Double?
    let e1rmIncreased: Bool
    let isMilestone: Bool
    let isFirstTierLog: Bool
    /// Effort chosen in the post-baseline "How did that feel?" prompt
    /// (easy/moderate/hard/near_max/max_effort). Only set on baseline sets —
    /// regular sets don't show that prompt, so it stays nil (and is omitted).
    var effort: String? = nil

    var dictionary: [String: Any] {
        var props: [String: Any] = [
            "exercise_name": exerciseName,
            "exercise_id": exerciseId,
            "load_type": loadType,
            "reps": reps,
            "weight": weight,
            "is_baseline_set": isBaselineSet,
            "e1rm_increased": e1rmIncreased,
            "is_milestone": isMilestone,
            "is_first_tier_log": isFirstTierLog,
        ]
        if let estimated1RM { props["estimated_1rm"] = estimated1RM }
        if let effort { props["effort"] = effort }
        return props
    }
}
