//
//  ProgramMockView.swift
//  WeightApp
//
//  Session tab proof-of-concept. The state enum below IS the spec:
//
//    idle       → nothing running today
//    generating → drafting; the card itself is the loading surface
//    active     → the live session. Generation ACTIVATED it; there is no commit step
//    failed     → generation failed and nothing exists; Retry or back out
//    receipt    → session filed for the day, read-only, restorable while it is still today
//
//  THE INVARIANT: the plan on screen is always the live session. Sets always credit
//  against it, only user taps cost a generation, and only logged sets make a session
//  leave a record.
//
//  There is deliberately no draft, no staleness and no auto-refresh. Those existed to
//  protect a commit boundary; with generation and activation collapsed into one moment,
//  there is nothing left to protect.
//
//  Nothing here writes application data. The only real read is today's logged sets,
//  because the generator drafts against actuals — that single rule is what makes
//  pre-logged work, reruns and second sessions all behave without special cases.
//

import SwiftUI
import SwiftData

struct ProgramMockView: View {
    @Binding var selectedTab: AppTab

    /// Five states. There is no draft: generation activates, so the plan on screen is
    /// always the live session.
    enum Phase {
        case idle, generating, active, failed, receipt
        /// Generation succeeded and deliberately chose nothing — everything worth
        /// recommending is already logged today. Distinct from `failed`: there is nothing
        /// to retry, because the answer was correct.
        case nothingToday
    }

    @Query(filter: #Predicate<LiftSet> { !$0.deleted }) private var allLiftSets: [LiftSet]
    @Query private var entitlementRecords: [EntitlementGrant]
    /// Every plan the generator may choose from — built-ins plus anything the user wrote.
    /// The catalog lives in client code, so the backend has no copy and we send ours.
    @Query(filter: #Predicate<SetPlan> { !$0.deleted }) private var setPlans: [SetPlan]
    @Query(filter: #Predicate<Estimated1RM> { !$0.deleted }) private var allEstimated1RM: [Estimated1RM]
    /// Only for `activeSetPlanId`, so a lift added by hand starts on the plan the user
    /// already chose rather than an arbitrary one.
    @Query private var userPropertiesItems: [UserProperties]

    /// Which of the five fundamentals have a baseline, in `fundamentalExercises` order.
    ///
    /// Presence of an `Estimated1RM` record, which is exactly what the Strength tab's
    /// `exerciseTiers.map { $0.e1rm != nil }` reduces to — matched deliberately, so this
    /// tab can never disagree with the tier card about whether the user is unlocked.
    private var tierLoggedFlags: [Bool] {
        let logged = Set(allEstimated1RM.compactMap { $0.exercise?.id })
        return TrendsCalculator.fundamentalExercises.map { logged.contains($0.id) }
    }

    /// The generator picks among the five and reasons about how hard to push each, so a
    /// baseline for every one of them is a hard prerequisite — without it there is
    /// nothing to choose between, and the request is not worth making.
    private var hasStartingTier: Bool { tierLoggedFlags.allSatisfy { $0 } }

    /// Whether `hasStartingTier` can be TRUSTED.
    ///
    /// Unlike the Strength tab widgets this has no `.task` — it reads the SwiftData query
    /// directly — but it races the same way: before sync lands, `allEstimated1RM` is empty,
    /// every flag is false, and a returning Advanced lifter gets told they have logged 0 of
    /// 5 lifts while `StrengthUnlockFooter` fires `strengthSampleShown` at them.
    ///
    /// Same rule as the widgets: sync complete is authoritative; failing that, any local
    /// e1RM means there is real data to judge from.
    private var canTrustTierState: Bool {
        syncService.initialSyncComplete || !allEstimated1RM.isEmpty
    }

    /// Sessions is a premium feature. Free users get the placeholder instead of the
    /// whole state machine — which also means none of the draft machinery runs for them.
    private var isPremium: Bool {
        if FreeOverride.isEnabled { return false }
        return PremiumOverride.isEnabled || EntitlementGrant.isPremium(entitlementRecords)
    }

    @State private var phase: Phase = .idle
    @State private var plan: MockDayPlan?
    @State private var builtAt: Date?

    @State private var context = DraftContext()
    @State private var showContext = false
    @State private var showRevise = false
    @State private var expandedRationale = false
    /// Editing is opt-in. Off, the planning card renders exactly as it did before editing
    /// existed — no delete glyphs, no chevrons, no add row. The controls are a mode you
    /// enter, not chrome the card carries.
    @State private var editingPlan = false
    /// Which lift's plan the catalog is open for. Identity rather than a bool, so the sheet
    /// is always scoped to the row that opened it — a separate bool plus a stored id could
    /// disagree with each other.
    ///
    /// Wrapped because `sheet(item:)` needs `Identifiable` and `UUID` is not. A local
    /// wrapper rather than `extension UUID: Identifiable`, which would conform a stdlib
    /// type app-wide to satisfy one sheet.
    private struct PlanEditTarget: Identifiable {
        let id: UUID
    }
    @State private var planEditTarget: PlanEditTarget?
    @State private var noteExpanded = false
    @State private var collapsedCardHeight: CGFloat?

    /// The generator's explanation for choosing nothing, shown by `nothingTodayCard`.
    @State private var nothingTodayMessage: String?

    @State private var generateTask: Task<Void, Never>?
    @State private var showUpsell = false

    @ObservedObject private var syncService = SyncService.shared

    private var sessionStore: ProgramSessionStore { ProgramSessionStore.shared }

    /// Always live now. The on-card debug toggles were removed — this is a production
    /// surface and it should look like one.
    ///
    /// `MockSessionsOverride` is left in place and still honoured, but nothing sets it any
    /// more. If the canned plans are ever wanted again, expose it from the staging block in
    /// `MoreView` alongside `PremiumOverride` and `FreeOverride`, which is where the app's
    /// other staging switches already live.
    private var draftService: SessionDraftService {
        // Checked first: the showcase is the most specific override, and someone who left
        // the older mock switch on should still get the screenshot session they just asked
        // for rather than a rotating canned one.
        if ShowcaseSessionOverride.isEnabled { return ShowcaseSessionDraftService.shared }
        return MockSessionsOverride.isEnabled ? MockSessionDraftService.shared : LiveSessionDraftService.shared
    }

    /// What we send as `set_plan_catalog`. Sent as stored — "redline" and "pr" included,
    /// which the backend normalizes — so there is no translation table to keep in step.
    private var catalog: [SetPlanCatalogEntry] {
        setPlans.map { plan in
            SetPlanCatalogEntry(
                id: plan.id.uuidString,
                name: plan.name,
                sequence: plan.effortSequence,
                description: plan.planDescription ?? ""
            )
        }
    }

    private let surface = Color(white: 0.14)

    /// Primary-CTA gradient stops, bracketing `Color.appAccent`.
    private static let ctaTop = Color(red: 0xF5/255, green: 0xCE/255, blue: 0x70/255)      // #F5CE70
    private static let ctaBottom = Color(red: 0xE8/255, green: 0xB8/255, blue: 0x4A/255)   // #E8B84A

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !isPremium {
                    SessionPremiumPlaceholder {
                        AmplitudeService.shared.track(.lockedWidgetTapped(feature: "session_tab"))
                        showUpsell = true
                    }
                } else if !canTrustTierState {
                    // Unknown, not locked. Showing the prerequisite here would state a
                    // falsehood to an unlocked user AND emit a sample-shown event for them.
                    sessionLoadingCard
                } else if !hasStartingTier {
                    // Checked after the premium gate on purpose: a free user without a
                    // baseline has two things standing between them and this feature, and
                    // the subscription is the one they cannot resolve by just training.
                    SessionTierPrerequisite(loggedFlags: tierLoggedFlags)
                } else {
                    // The footer is attached here rather than inside the cards so that the
                    // rule for WHICH phases carry it lives in one place, next to the switch
                    // that decides them. 15pt rather than the stack's 12 — it is a caption ON
                    // the widget, and at the stack's spacing it starts to read as a sibling.
                    switch phase {
                    case .idle: idleCard
                    case .generating: generatingCard
                    case .active:
                        VStack(spacing: 15) {
                            activeCard
                            sessionFooter
                        }
                    case .failed: failedCard
                    case .nothingToday: nothingTodayCard
                    case .receipt:
                        VStack(spacing: 15) {
                            receiptCard
                            sessionFooter
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .background(Color.black)
        .onAppear { reconcileOnAppear() }
        // Recovery edge. `reconcileOnAppear` guards on `hasStartingTier`, so during the
        // untrusted window it early-returns and does nothing — without this, a session that
        // was live in the store would render as `.idle` for the rest of the appearance.
        // Same "check on appear, re-check on the false→true transition" shape as
        // `CheckInView.onChange(of: syncService.initialSyncComplete)`.
        .onChange(of: canTrustTierState) { _, trusted in
            if trusted { reconcileOnAppear() }
        }
        .fullScreenCover(isPresented: $showUpsell) {
            UpsellView(initialPage: SubscriptionConfig.upsellPage(for: SubscriptionConfig.smartSessionsTitle),
                       source: SubscriptionConfig.UpsellSource.sessionTab) { _ in showUpsell = false }
        }
        .sheet(isPresented: $showRevise) { reviseSheet }
        .sheet(item: $planEditTarget) { target in
            // Writes straight to the session item via the store, which is also what makes
            // Cancel work: the edit buffer captured the items on `beginEditing()`, so
            // discarding restores whatever the plan was before the catalog was opened.
            SetPlanCatalogSheet(
                sessionExerciseId: target.id,
                scopeName: sessionStore.item(for: target.id)?.exerciseName
            )
        }
        .onChange(of: planEditTarget?.id) { _, id in
            // Rebuild the view's copy once the sheet closes — the store changed underneath
            // it, and `liveItems` maps over `plan`, not over the store.
            if id == nil { refreshPlanFromStore() }
        }
        .onChange(of: sessionStore.isActive) { _, active in
            guard !active else { return }
            if sessionStore.lastOutcome == .completed {
                withAnimation(.easeInOut(duration: 0.3)) { phase = .receipt }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) { resetToIdle() }
            }
        }
    }

    /// Shown while it is not yet knowable whether the user has unlocked their tier.
    /// Deliberately says nothing about lifts logged or sessions — any such claim would be
    /// a guess, and guessing is the bug.
    private var sessionLoadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white.opacity(0.5))
            Text("Getting your training…")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: collapsedCardHeight ?? 160)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sessionCardBorder()
    }

    // MARK: - Appearance reconciliation

    /// Regeneration is upstream of eyeballs: by the time a draft is read it has already
    /// been checked against current inputs.
    private func reconcileOnAppear() {
        guard isPremium, hasStartingTier else { return }

        // Order matters, and nothing here ever calls generation.
        sessionStore.finalizeIfIdle4h()
        sessionStore.dissolveIfSetlessAndRolledOver()

        // Rehydrate after a cold launch. `plan` is `@State` and dies with the process,
        // while the session itself is persisted — so a force quit mid-session left
        // `phase == .active` with nothing to draw, and both active cards are wrapped in
        // `if let plan`. The result was a blank tab. The store kept everything needed, so
        // this rebuilds from it rather than regenerating.
        if plan == nil, let restored = sessionStore.restoredPlan {
            plan = restored
        }

        if sessionStore.pendingAutoStart {
            sessionStore.pendingAutoStart = false
            if !sessionStore.isActive && !sessionStore.hasReceiptForToday {
                generate(trigger: "auto_start")
                return
            }
        }

        if sessionStore.isActive {
            phase = .active
            return
        }

        if sessionStore.hasReceiptForToday {
            phase = .receipt
            return
        }

        // `resetToIdle()`, not a bare `phase = .idle`. Assigning the phase alone left the
        // previous session's context — chips and typed note — sitting in the editor of what
        // is meant to be a clean start, which is what made an unexpectedly-idle Session tab
        // look pre-populated rather than merely wrong.
        if phase != .generating && phase != .failed && phase != .nothingToday {
            resetToIdle()
        }
    }

    private var todaysSetCount: Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return allLiftSets.filter { $0.createdAt >= dayStart && $0.createdAt < dayEnd }.count
    }

    // MARK: - 1. Idle

    private var idleCard: some View {
        VStack(spacing: 16) {
            // Above the header rather than beside the title: it labels the whole card,
            // and hanging it off the title would read as describing that line alone.
            //
            // Given room rather than tucked against the header. It was crowding "TODAY"
            // and the two centred, tracked labels fought each other; separated, the badge
            // reads as chrome on the card and the header keeps its own top line.
            PremiumBadge()
                .padding(.bottom, 6)

            cardHeader(title: "Ready to train?")

            Text("Built for today, the moment you start.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if showContext { contextEditor }

            VStack(spacing: 8) {
                primaryButton("Start Session", icon: "sparkles", glint: true) {
                    generate(trigger: "start")
                }

                if !showContext {
                    // A chevron and a rule, so it reads as a thing that OPENS rather than
                    // a second, quieter action competing with Start Session. Full-width
                    // and separated, which is what makes it look like the lid of a
                    // section instead of another button in the stack.
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showContext = true }
                    } label: {
                        VStack(spacing: 12) {
                            Divider().overlay(Color.white.opacity(0.10))

                            HStack(spacing: 5) {
                                Text("Add context first")
                                    .font(.subheadline.weight(.medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(Color.appAccent)
                        }
                        // The rule needs clear air above it, or it reads as an
                        // underline on the Start Session button rather than the top edge
                        // of a separate, collapsed section.
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sessionCardBorder()
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: CardHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(CardHeightKey.self) { height in
            if !showContext, height > 0 { collapsedCardHeight = height }
        }
    }

    // MARK: - 2. Generating

    private var generatingCard: some View {
        // ORDER IS THE WHOLE TRICK HERE. The card is held to `collapsedCardHeight` so it
        // does not shrink when generation replaces a taller card, and `.frame(minHeight:)`
        // CENTRES its child in that taller frame. So anything laid out alongside the
        // spinner — a VStack row, a ZStack's top-trailing child — gets centred with it and
        // floats down the card. Both earlier attempts failed that way.
        //
        // Applying the overlay AFTER the height frame is what fixes it: the button aligns
        // to the full-height card, while the spinner still centres itself inside it.
        GeneratingView(
            steps: ProgramMockData.generatingSteps,
            heat: liftHeat
            // TIMELINE PARKED: see `setHistoryMarquee` in GeneratingView. To restore, add
            //   recentDays: LiftMomentum.recentDays(
            //       sets: allLiftSets,
            //       estimated1RMs: allEstimated1RM,
            //       unit: userPropertiesItems.first?.preferredWeightUnit ?? .lbs
            //   )
        )
            .frame(maxWidth: .infinity)
            .frame(minHeight: collapsedCardHeight ?? 0)
            .overlay(alignment: .topTrailing) {
                // Cancel, because a wait you cannot leave is a trap even at two seconds.
                Button {
                    generateTask?.cancel()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        // Cancelling a re-roll leaves the existing session alone; only a
                        // first generation has nothing to fall back to.
                        if sessionStore.isActive { phase = .active } else { resetToIdle() }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        // Padding is the tap target, so it stays generous while the glyph
                        // itself sits close to the corner.
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(2)
            }
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .sessionCardBorder()
    }

    // MARK: - 3. Active

    /// The plan with the store's live progress folded in. Same `MockPlanItem` shape, so
    /// one row renderer serves both the just-generated card and the mid-session one, and
    /// the tiles show the effort that actually happened rather than the planned one.
    private var liveItems: [MockPlanItem] {
        guard let plan else { return [] }
        guard sessionStore.isActive else { return plan.items }

        return plan.items.map { item in
            guard let live = sessionStore.items.first(where: { $0.exerciseName == item.exerciseName })
            else { return item }

            var copy = item

            // Progress.
            copy.completedSets = live.loggedSets
            copy.loggedEfforts = live.loggedEfforts
            copy.outcome = live.isComplete ? .landed : (live.loggedSets > 0 ? .underway : .pending)

            // THE PLAN ITSELF. Only progress used to be merged here, so a plan swapped
            // from the LIFT TAB — which writes to the store and never touches this view's
            // `plan` copy — was invisible on the Session tab: the card kept showing the
            // plan the generator picked while the rail ran the new one.
            //
            // While a session is live the store is the source of truth for every one of
            // these. `plan` still supplies the ordering and the summary; anything the store
            // can answer, the store answers.
            copy.setPlanId = live.setPlanId
            copy.planName = live.planName
            copy.sequence = live.sequence
            copy.detail = live.detail
            copy.rationale = live.rationale

            return copy
        }
    }

    /// The live session. No banner, no dim, no disabled controls — there is nothing to
    /// protect the user from, because seeing the plan IS being in the session.
    @ViewBuilder
    private var activeCard: some View {
        if sessionStore.activePhase == .underway {
            underwayCard
        } else {
            planningCard
        }
    }

    /// Provenance and disclaimer, under the session widget.
    ///
    /// Two jobs, one block. Everything else on the card says WHAT was picked; the banner is the
    /// only line that says where it came from — without it a reader can take the session for a
    /// template that happens to mention their shoulder. The paragraph under it then says where
    /// that authority ends.
    ///
    /// Shown only in `.active` and `.receipt` — the phases where a generated plan is actually on
    /// screen. On `.idle` there is nothing yet to qualify, and a safety notice attached to an
    /// empty state is noise the user has to read past every day.
    ///
    /// This deliberately reuses the Lift tab's footer grammar (`CheckInView`: rules-with-icon,
    /// then small centred grey type) and the back half of its sentence verbatim, so the two tabs
    /// read as one app making one disclosure rather than two teams writing separate small print.
    ///
    /// The flanking rules do the separating, which is what lets the banner stay this quiet: at
    /// 35% white it would read as a stray caption on its own, but bracketed it reads as a footer.
    /// 9pt with 1.4 tracking is measured — at 11pt the text runs 241pt of the 311pt card and the
    /// rules collapse to stubs.
    private var sessionFooter: some View {
        VStack(spacing: 10) {
            // Amber rather than the rules' grey, and the one warm mark down here. At 0.4 it
            // signs the footer without competing with the card's CTA above it. The asset is a
            // template SVG, so it tints.
            Image("LiftTheBullIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(Color.appAccent.opacity(0.4))

            HStack(spacing: 6) {
                provenanceRule
                Text("BASED ON YOUR RECENT TRAINING")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize()
                provenanceRule
            }

            // Matches the Lift tab's disclaimer exactly in size, colour and alignment. The
            // banner above is a 9pt tracked divider and this is body copy, so they frame each
            // other rather than compete — the caps line reads as this paragraph's header.
            Text("Sessions are computer-generated from your logged sets and the context you "
                 + "provide. They are suggestions, not prescriptions — always train within your "
                 + "limits and consult a physician before beginning or modifying any exercise "
                 + "program.")
                .font(.inter(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 8)
    }

    private var provenanceRule: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
    }

    /// Negotiable. Everything that can change the plan lives here and nowhere else, so
    /// the mutation window is only as long as the user spends deciding.
    @ViewBuilder
    private var planningCard: some View {
        if let plan {
            VStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.appAccent)
                            Text("Today's Session")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                        }

                        // FEATURE FLAG: the dated line and "Built 9:41 AM" are removed.
                        //
                        // Nothing keyed off the timestamp once staleness was dropped, and
                        // with the session always being today's, neither line told the
                        // user anything the title above did not.
                        //
                        // TO RESTORE: uncomment. `builtAt` is still set on every
                        // generation, and `Self.timeFormatter` is still live (the underway
                        // card's "Started 10:02 AM" uses it), so this block works as-is.
                        //
                        // Text(ProgramMockData.todayLabel)
                        //     .font(.caption)
                        //     .foregroundStyle(.white.opacity(0.5))
                        //
                        // if let builtAt {
                        //     Text("Built \(Self.timeFormatter.string(from: builtAt))")
                        //         .font(.caption2)
                        //         .foregroundStyle(.white.opacity(0.35))
                        // }
                    }
                    .frame(maxWidth: .infinity)

                    // Refresh removed. Revise still regenerates, and it does so WITH the
                    // user's context — a bare re-roll asked the model the same question and
                    // hoped for a different answer, which is not a thing to offer next to a
                    // 20-second wait.
                    //
                    // Save takes the corner it vacated, so Cancel and Save sit at opposite
                    // ends of the header rather than crowding one side.
                    if editingPlan {
                        Button { finishEditing(save: true) } label: {
                            Text("Save")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.appAccent)
                                .padding(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .overlay(alignment: .topLeading) {
                    // Paired with Refresh on the opposite corner: both are ways to change
                    // the session, and both stay out of the body.
                    if sessionStore.activePhase == .planning {
                        Button {
                            if editingPlan {
                                finishEditing(save: false)
                            } else {
                                sessionStore.beginEditing()
                                withAnimation(.easeInOut(duration: 0.2)) { editingPlan = true }
                            }
                        } label: {
                            // A glyph at rest, a word while editing.
                            //
                            // The pencil is quiet enough to sit on a card the user is only
                            // reading — "Edit" as text asked for attention it had not
                            // earned. Once editing, the pair becomes Cancel / Save: those
                            // discard or keep work, and words are unambiguous where two
                            // icons would need to be told apart under pressure.
                            //
                            // "Cancel", not "Done": the edits are provisional until Save,
                            // and a label implying completion next to a discard action is
                            // how people lose work they thought they had kept.
                            Group {
                                if editingPlan {
                                    Text("Cancel")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.55))
                                } else {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                            // On the frame, not inside the Group: a Group distributes
                            // modifiers to each child, so the tap target would otherwise be
                            // built twice and sized to whichever branch rendered.
                            .padding(6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(plan.summary)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Showcase only. Says nothing the card does not already contain — it is the same
                // ten sets, restated as one shape — so it adds colour without adding a claim.
                // Sits in the zone the removed duration line used to hold.
                if ShowcaseSessionOverride.isEnabled {
                    EffortMixStrip(sequences: liveItems.map(\.sequence))
                        .padding(.horizontal, 24)
                        .padding(.top, 2)
                }

                // Stated, not explained. The cause could be moderation or an outage, and
                // naming either one would be wrong half the time — and would tell anyone
                // testing the filter which of the two they hit.
                if plan.noteOmitted {
                    Text("Your note couldn't be used.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }

                // The summary above describes what was GENERATED. Once a lift is added,
                // removed or re-planned that is no longer the whole truth, so say it —
                // rather than let the card present an edited session as the generator's
                // own work. Shown on the underway card too: the edit does not stop being
                // true when lifting starts.
                if sessionStore.wasEdited {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .bold))
                        Text("Edited by you")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                }

                contextRecap

                Divider().overlay(Color.white.opacity(0.08))

                VStack(spacing: 12) {
                    ForEach(liveItems) { planItemRow($0, editable: editingPlan) }
                }

                if editingPlan { addLiftRow }

                reasoningToggle

                // Navigation, not a commit — the session is already live and the rail is
                // already up. Kept primary because it is still where you go next.
                primaryButton("Start Lifting", icon: nil) { startLifting() }

                HStack(spacing: 10) {
                    secondaryButton("Revise") { showRevise = true }
                    secondaryButton("Discard") { discardSession() }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .sessionCardBorder()
        }
    }

    // MARK: - 3b. Underway

    /// Committed. The lift rows are the hero and every regeneration affordance is gone —
    /// Revise and Refresh do not exist here at all, so a session cannot be rewritten out
    /// from under work already done.
    @ViewBuilder
    private var underwayCard: some View {
        if let plan {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("SESSION UNDERWAY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .tracking(1.5)

                    Text("\(sessionStore.completedCount) of \(sessionStore.items.count)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.appAccent)

                    if let started = sessionStore.startedLiftingAt {
                        Text("Started \(Self.timeFormatter.string(from: started))")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .frame(maxWidth: .infinity)

                // The reason the session looks the way it does. It belongs here as much
                // as in Planning — knowing WHY you are squatting today does not stop
                // being useful once you have started.
                Text(plan.summary)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Stated, not explained. The cause could be moderation or an outage, and
                // naming either one would be wrong half the time — and would tell anyone
                // testing the filter which of the two they hit.
                if plan.noteOmitted {
                    Text("Your note couldn't be used.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }

                // The summary above describes what was GENERATED. Once a lift is added,
                // removed or re-planned that is no longer the whole truth, so say it —
                // rather than let the card present an edited session as the generator's
                // own work. Shown on the underway card too: the edit does not stop being
                // true when lifting starts.
                if sessionStore.wasEdited {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .bold))
                        Text("Edited by you")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: 14) {
                    ForEach(liveItems) { underwayRow($0) }
                }

                // Reasoning and context both fold away here — useful while deciding,
                // noise once the decision is made.
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { expandedRationale.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(expandedRationale ? "Hide details" : "Why these lifts?")
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(expandedRationale ? 0 : -90))
                    }
                    .foregroundStyle(Color.appAccent)
                }
                .buttonStyle(.plain)

                if expandedRationale {
                    VStack(spacing: 10) {
                        contextRecap

                        // Grid, not a stack of HStacks. Each name was intrinsically sized,
                        // so "Squats" and "Overhead Press" pushed their rationale to
                        // different x positions and the column read as ragged. A Grid
                        // sizes the first column to the widest name and every rationale
                        // then starts on the same line — no fixed width to guess at, and
                        // it still adapts if the five lifts are ever renamed.
                        Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 10) {
                            ForEach(liveItems) { item in
                                GridRow {
                                    Text(item.exerciseName)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.55))
                                        // The column is as wide as the longest name, so
                                        // wrapping here would only ever be wrong.
                                        .lineLimit(1)
                                        .fixedSize()

                                    Text(item.rationale)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.4))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }

                secondaryButton("Resume on Lift tab") { startLifting() }

                // Quiet exit. Files a receipt only if work happened — a session that
                // logged nothing leaves no trace, same as Discard.
                Button { endSession() } label: {
                    Text("End Session")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .sessionCardBorder()
        }
    }

    /// Enlarged row: bigger icon, bigger tiles, explicit completion mark.
    private func underwayRow(_ item: MockPlanItem) -> some View {
        HStack(spacing: 12) {
            Image(item.icon)
                .resizable().scaledToFit()
                .frame(width: 30, height: 30)
                .foregroundStyle(item.isFinished ? Color.appAccent : .white.opacity(0.65))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Was `.body`, which wrapped "Overhead Press" onto two lines once the
                    // 30pt icon and the tiles had taken their share of the row. A step
                    // down fits the longest of the five, and `minimumScaleFactor` absorbs
                    // the rest rather than truncating a lift name.
                    Text(item.exerciseName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if item.isFinished {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.appAccent)
                    }
                }

                Text("\(item.planName) · \(item.completedSets) of \(item.totalSets) sets")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 8)

            EffortSquares(
                sequence: item.sequence,
                loggedEfforts: item.loggedEfforts,
                completed: item.completedSets,
                side: 20
            )
        }
    }

    // MARK: - 4. Failed

    /// A dead end, not a fallback. Nothing was generated, so there is no earlier plan to
    /// show underneath — and without the dismiss the user would be stranded on an error
    /// with a single option.
    /// Generation succeeded and chose nothing, because everything is already logged today.
    ///
    /// Deliberately not the failure card: there is no Retry, because retrying would ask
    /// the same question and correctly get the same answer. The tone is congratulatory
    /// rather than apologetic — having trained everything is the good outcome.
    private var nothingTodayCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.appAccent)

            VStack(spacing: 6) {
                Text("You're covered for today")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                // The generator's own words when it has them — it knows which lifts were
                // already done and why that settled the day.
                Text(nothingTodayMessage ?? "You've already trained everything worth doing today.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Only a dismiss. There is deliberately no "Generate anyway": the request
            // carries no way to say "ignore what I already did", so it would ask the same
            // question, correctly get the same answer, and land back on this card. A
            // second session on the same day needs a flag on the request before a button
            // here can mean anything.
            secondaryButton("Done") {
                withAnimation(.easeInOut(duration: 0.25)) { resetToIdle() }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .frame(minHeight: collapsedCardHeight ?? 0)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sessionCardBorder()
    }

    private var failedCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.5))

            VStack(spacing: 6) {
                Text("Couldn't build a session")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text("Nothing was changed. Try again in a moment.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }

            primaryButton("Retry", icon: "arrow.clockwise") { generate(trigger: "retry") }

            secondaryButton("Not now") {
                withAnimation(.easeInOut(duration: 0.25)) { resetToIdle() }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .frame(minHeight: collapsedCardHeight ?? 0)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sessionCardBorder()
    }

    // MARK: - 7. Receipt

    /// Every lift in the filed session reached its planned set count.
    ///
    /// Read from `receipt`, not `items`: `finish()` clears the live items, so by the time
    /// this card renders the session itself is gone and the snapshot is all that is left.
    private var receiptFullyComplete: Bool {
        !sessionStore.receipt.isEmpty
            && sessionStore.receipt.allSatisfy { $0.loggedSets >= $0.plannedSetCount }
    }

    private var receiptCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.appAccent)

                Text("Session complete")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text(ProgramMockData.todayLabel)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)

            Divider().overlay(Color.white.opacity(0.08))

            VStack(spacing: 12) {
                ForEach(sessionStore.receipt) { item in
                    HStack(spacing: 10) {
                        Image(item.icon)
                            .resizable().scaledToFit()
                            .frame(width: 22, height: 22)
                            .foregroundStyle(Color.appAccent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.exerciseName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("\(item.planName) · \(item.loggedSets) of \(item.plannedSetCount) sets")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                        }

                        Spacer(minLength: 6)

                        EffortSquares(sequence: item.sequence, loggedEfforts: item.loggedEfforts, side: 14)
                    }
                }
            }

            VStack(spacing: 8) {
                // Restores from the store — never regenerates, so this costs no API call.
                // Also the recovery for a finalizer false positive: a long interruption
                // files the session early, and this puts it straight back.
                // Offered only when there is something left to continue. A session where
                // every lift hit its set count has nothing to resume, and inviting the user
                // back into it is a question with no good answer.
                if !receiptFullyComplete {
                    primaryButton("Continue session", icon: "arrow.uturn.backward") {
                        sessionStore.resume()
                        withAnimation(.easeInOut(duration: 0.25)) { phase = .active }
                    }
                }

                // "Delete receipt" used to sit below this and did the same job — both
                // returned you to idle, and the receipt records nothing that would be lost
                // (the logged sets are the record, on the Lift tab, untouched). Two buttons
                // for one outcome only made the user pick between them.
                //
                // This one now does the clearing that Delete did. That matters beyond
                // tidiness: hiding the receipt behind a view flag left it in the store, so
                // it reappeared after a relaunch. Clearing the outcome retires it properly.
                secondaryButton("Start Another Session") {
                    sessionStore.clearOutcome()
                    withAnimation(.easeInOut(duration: 0.25)) { resetToIdle() }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sessionCardBorder()
    }

    // MARK: - Shared pieces

    private func cardHeader(title: String) -> some View {
        VStack(spacing: 6) {
            // Nudged up from `.caption` (12pt). It holds the top of the card alone now
            // that the dated line is gone, but stays well under the title beneath it — a
            // kicker that matches its headline stops being a kicker, and the pair then
            // reads as two competing titles.
            Text("TODAY")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .tracking(1.8)

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            // The dated line ("Monday, Aug 18") used to sit here. Removed: "TODAY"
            // directly above already says which day this is, so the date restated it in
            // a third centred line and made the card read as stacked layers of text.
        }
        .frame(maxWidth: .infinity)
    }

    private var reasoningToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { expandedRationale.toggle() }
        } label: {
            HStack(spacing: 4) {
                Text(expandedRationale ? "Hide reasoning" : "Why these lifts?")
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    // Right when collapsed (there is more to open), up when expanded (this
                    // closes it). It sat at 0 while expanded — still pointing down, i.e.
                    // "more below" — directly beside the words "Hide reasoning".
                    .rotationEffect(.degrees(expandedRationale ? 180 : -90))
            }
            .foregroundStyle(Color.appAccent)
        }
        .buttonStyle(.plain)
    }

    /// Re-read the plan from the store after an edit.
    ///
    /// `plan` is the view's copy and `liveItems` maps over it, so mutating the store alone
    /// would leave a removed lift still on screen. `restoredPlan` already knows how to build
    /// a `MockDayPlan` from store items — it exists for cold launches — so editing reuses it
    /// rather than growing a second rebuild path that could drift from the first.
    /// Leave edit mode, keeping or discarding what was changed.
    ///
    /// Both paths rebuild `plan` from the store afterwards, because Cancel restores the
    /// store's items and the view's copy has to follow — otherwise the card would keep
    /// showing edits the session no longer has.
    private func finishEditing(save: Bool) {
        if save {
            sessionStore.commitEditing()
        } else {
            sessionStore.cancelEditing()
        }
        refreshPlanFromStore()
        withAnimation(.easeInOut(duration: 0.2)) { editingPlan = false }
    }

    private func refreshPlanFromStore() {
        guard let rebuilt = sessionStore.restoredPlan else { return }
        withAnimation(.easeInOut(duration: 0.2)) { plan = rebuilt }
    }

    /// Today's non-baseline sets for a lift — what a newly added lift should already show
    /// as done. Same rule as `creditingTodaysWork`, which credits the generated plan.
    private func creditedSetsToday(for exerciseId: UUID) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return allLiftSets.filter {
            $0.exercise?.id == exerciseId
                && !$0.isBaselineSet
                && $0.createdAt >= dayStart
                && $0.createdAt < dayEnd
        }.count
    }

    /// Offers the fundamentals the generator left out. Hidden once all five are in.
    @ViewBuilder
    private var addLiftRow: some View {
        let available = sessionStore.availableLifts
        if sessionStore.activePhase == .planning, !available.isEmpty {
            Menu {
                ForEach(available, id: \.id) { lift in
                    Button(lift.name) { addLift(lift) }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add a lift")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(Color.appAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
        }
    }

    private func addLift(_ lift: TrendsCalculator.FundamentalExercise) {
        // Default to whatever the user has active, falling back to Standard — the same
        // plan a fresh install starts on.
        let fallback = setPlans.first(where: { $0.id == SetPlan.standardId }) ?? setPlans.first
        let activeId = userPropertiesItems.first?.activeSetPlanId
        let chosen = setPlans.first(where: { $0.id == activeId }) ?? fallback
        guard let chosen else { return }

        sessionStore.addLift(
            exerciseId: lift.id,
            exerciseName: lift.name,
            icon: lift.icon,
            setPlanId: chosen.id,
            planName: chosen.name,
            sequence: chosen.effortSequence,
            creditedSets: creditedSetsToday(for: lift.id)
        )
        refreshPlanFromStore()
    }

    /// Tile size for every row on this card, from the longest plan in the session.
    ///
    /// Card-wide rather than per-row so the strips stay comparable to each other; see
    /// `PlanTileMetrics`. Reads `liveItems` so a plan swapped mid-session resizes the whole
    /// card rather than leaving one row at a size the others no longer use.
    /// Icon slot for a lift row.
    ///
    /// Bigger in the showcase, and gated there for a measured reason: `planItemRow` is shared
    /// with real sessions, where the worst case is an 8-set plan whose strip leaves the lift name
    /// 121pt. "Overhead Press" needs 113.1pt, so a 30pt slot there would cut the margin to 0.4pt
    /// and a 34pt one would truncate. The showcase tops out at a 4-set plan, which leaves 139pt.
    private var rowIconSlot: CGFloat { ShowcaseSessionOverride.isEnabled ? 34 : 22 }

    /// Drawn glyph size within that slot.
    ///
    /// In the showcase these carry the same proportions the upsell's Smart Sessions page uses
    /// (Bench 30/34, Deadlifts 34/34, Overhead 38/34) — optical corrections for line art whose
    /// stroke density and surrounding whitespace differ, so the three read as one weight. Scaled
    /// off the slot rather than hardcoded, so changing the slot keeps the ratios.
    private func rowIconSize(_ item: MockPlanItem) -> CGFloat {
        guard ShowcaseSessionOverride.isEnabled else { return rowIconSlot }
        switch item.exerciseName {
        case "Bench Press":    return rowIconSlot * 30 / 34
        case "Overhead Press": return rowIconSlot * 38 / 34
        default:               return rowIconSlot
        }
    }

    /// Whether this row shows its reasoning inline without the toggle. Showcase only.
    private func showcaseMicroLine(_ item: MockPlanItem) -> Bool {
        ShowcaseSessionOverride.isEnabled && item.exerciseName == "Bench Press"
    }

    /// Hangs the reasoning line under the lift name rather than under the icon. Derived, so it
    /// follows the icon slot instead of drifting when that changes.
    private var rationaleIndent: CGFloat { rowIconSlot + 8 + 2 }

    private var planTileSide: CGFloat {
        PlanTileMetrics.side(forLongestPlan: liveItems.map(\.sequence.count).max() ?? 0)
    }

    private func planItemRow(_ item: MockPlanItem, editable: Bool = false) -> some View {
        // Editing is a Planning-phase affordance. Once Underway the session stops being
        // negotiable — the same boundary Revise and Refresh sit behind.
        let canEdit = editable && sessionStore.activePhase == .planning

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(item.icon)
                    .resizable().scaledToFit()
                    .frame(width: rowIconSize(item), height: rowIconSize(item))
                    // Constant slot around a varying glyph, so the lift names stay aligned with
                    // each other however the per-lift sizes are tuned.
                    .frame(width: rowIconSlot, height: rowIconSlot)
                    .foregroundStyle(item.completedSets > 0 ? Color.appAccent : .white.opacity(0.6))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        // No `minimumScaleFactor` here: it shrank only the long names,
                        // so "Overhead Press" rendered visibly smaller than "Squats" in
                        // the same list. Fixed size plus layout priority instead — the
                        // name is the thing that must not give, so the status pill and
                        // the tiles yield to it.
                        Text(item.exerciseName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)

                        if let label = item.outcome.label {
                            StatusPill(text: label, isAccent: item.outcome.isAccent)
                                .layoutPriority(1)
                        }
                    }

                    if canEdit, let exerciseId = item.exerciseId {
                        // The plan name becomes the control. A separate "change plan"
                        // button would add a third tap target to a row that already has
                        // two; making the thing you want to change the thing you tap is
                        // both smaller and more obvious.
                        //
                        // Opens the catalog rather than a menu of names. A set plan IS a
                        // sequence of efforts, and "Wave Loading" or "Ladders" does not say
                        // what you are picking — the catalog draws those sequences, which
                        // is the only way to choose between them on sight.
                        Button {
                            planEditTarget = PlanEditTarget(id: exerciseId)
                        } label: {
                            HStack(spacing: 3) {
                                Text(item.planName)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundStyle(Color.appAccent.opacity(0.85))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Plan name only. `item.detail` used to trail it — "· 1 of 6 sets" —
                        // which did not fit beside a long lift name, and doubled the plan
                        // name once crediting rewrote `detail` to include it. The tiles to
                        // the right already show how far through the plan the lift is.
                        Text(item.planName)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                PlanTile(item: item,
                         side: planTileSide,
                         glow: ShowcaseSessionOverride.isEnabled,
                         saturated: ShowcaseSessionOverride.isEnabled)

                // Hidden on the last remaining lift: an empty session is not a state this
                // tab can render, and "none of this" is what Discard is for.
                if canEdit, sessionStore.items.count > 1, let exerciseId = item.exerciseId {
                    Button {
                        sessionStore.removeLift(exerciseId: exerciseId)
                        refreshPlanFromStore()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Normally the reasoning lives behind "Why these lifts?". The showcase surfaces
            // exactly one of them inline — Bench, the lift that also owns the single amber
            // progress square, so the strongest evidence and the brightest element land on the
            // same row. All three inline would turn the card back into a list.
            if expandedRationale || showcaseMicroLine(item) {
                Text(item.rationale)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.leading, rationaleIndent)
            }
        }
    }

    /// One labelled row of chips. Both groups feed the same `context.chips` set — the
    /// split is presentational, and the backend receives one flat list either way.
    /// The five fundamentals, tappable, all on by default.
    ///
    /// Built to the Lift tab's tier-strip card spec — 84pt-tall rounded rects at radius 10,
    /// icon over short name, `Color(white: 0.12)` fill with a hairline border — so the two
    /// read as the same control in two places. Squarer cells looked like a different widget
    /// that happened to contain the same icons.
    ///
    /// Deliberately NOT a horizontal ScrollView like that one: five cells fit the card
    /// width, and a scroll view here would hide lifts behind a gesture in a panel whose
    /// whole job is to show what is on the table.
    ///
    /// "CONSIDER", NOT "INCLUDE". Include reads as a promise that every ticked lift will be
    /// in the session, which is false — the generator still picks one to three from these
    /// under its own rules. What the control actually sets is eligibility.
    ///
    /// NOT WIRED TO THE BACKEND YET. `DraftContext.excludedLifts` is real state and this
    /// really toggles it, but nothing sends it: the request carries `chips` and `note` only.
    /// Making it work needs a field on `SessionGenerateRequest`, validation in the sessions
    /// handler, a line in the payload's `user_context`, and a rule in the prompt — none of
    /// which is worth building until the layout is settled.
    ///
    /// The chip group below lost "Upper only" and "Lower only" to pay for this row. They
    /// were presets of the same constraint, and two controls setting one thing is worse
    /// than either alone.
    /// How warm each fundamental is, 0...1. Feeds the generating screen's recap only — the
    /// selector deliberately shows eligibility and nothing else. See `LiftMomentum`.
    private var liftHeat: [UUID: Double] {
        LiftMomentum.heatByExercise(sets: allLiftSets, estimated1RMs: allEstimated1RM)
    }

    private var liftSelector: some View {
        let excluded = context.excludedLifts
        let includedCount = TrendsCalculator.fundamentalExercises.count - excluded.count

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("LIFTS TO CONSIDER")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.55))

                // Silent at five of five. Announcing the default would make an untouched
                // control look like a decision the user had already made.
                if !excluded.isEmpty {
                    Text("\(includedCount) of \(TrendsCalculator.fundamentalExercises.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.appAccent.opacity(0.8))
                }
            }

            HStack(spacing: 7) {
                ForEach(TrendsCalculator.fundamentalExercises, id: \.id) { lift in
                    let isOn = !excluded.contains(lift.name)
                    Button {
                        // Never let the last one go. An empty selection asks for a session
                        // with nothing in it, and the honest response would be an error —
                        // so the control simply does not offer that state.
                        if isOn {
                            guard includedCount > 1 else { return }
                            context.excludedLifts.insert(lift.name)
                        } else {
                            context.excludedLifts.remove(lift.name)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            // One signal per cell: eligible or not. Recency lives on the
                            // generating screen instead — here it competed with selection
                            // for the same amber, and a cell has one thing to say.
                            Image(lift.icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                                .foregroundStyle(isOn ? Color.appAccent : .white.opacity(0.22))

                            Text(ProgramSessionStore.shortName(for: lift.name))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isOn ? Color.appAccent.opacity(0.9) : .white.opacity(0.3))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        // Taller than wide, matching the Lift tab strip's proportion. The
                        // border is 0.45 rather than that strip's 0.6: there one card is
                        // selected among many, here four or five usually are, and at 0.6
                        // the whole row reads as a solid amber block.
                        .frame(minHeight: 76)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isOn ? Color.appAccent.opacity(0.10) : Color(white: 0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10).strokeBorder(
                                isOn ? Color.appAccent.opacity(0.45) : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chipGroup(title: String, chips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            // Bumped from 10pt/35% — legible at arm's length, and now unambiguously one
            // step below the section title rather than competing with it. Three levels
            // read cleanly: question, group label, chip.
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.55))

                // Appears only at the cap. Before that it is a rule nobody needed to know.
                if context.chipsAtLimit {
                    Text("\(SessionContextLimits.maxChips) of \(SessionContextLimits.maxChips)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.appAccent.opacity(0.8))
                }
            }

            FlowLayout(spacing: 9) {
                ForEach(chips, id: \.self) { chip in
                    let isSelected = context.chips.contains(chip)
                    // At the cap, unpicked chips go quiet. Selected ones stay live so the
                    // user is never stuck at 8 with no way to swap one out.
                    let isBlocked = !isSelected && context.chipsAtLimit
                    ContextChip(text: chip, isSelected: isSelected) {
                        if isSelected {
                            context.chips.remove(chip)
                        } else if !context.chipsAtLimit {
                            // Clear anything this chip contradicts. Each group is one axis
                            // — lift count, body region, intensity, time, sleep, readiness —
                            // and holding two members of one would send the generator a
                            // constraint it has to arbitrate, which is the decision the user
                            // was trying to take away from it.
                            //
                            // Subtracting before inserting also means swapping a selection
                            // can never trip the cap.
                            for group in ProgramMockData.exclusiveChipGroups
                            where group.contains(chip) {
                                context.chips.subtract(group)
                            }
                            context.chips.insert(chip)
                        }
                    }
                    .opacity(isBlocked ? 0.35 : 1)
                    .allowsHitTesting(!isBlocked)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var contextRecap: some View {
        // Both groups, in a stable order — the recap must not silently drop a constraint
        // the user set just because it came from the other row.
        let chips = (ProgramMockData.contextChips + ProgramMockData.sessionShapeChips)
            .filter { context.chips.contains($0) }
        // Suppressed when the note was withheld. Quoting it back under "here is the context
        // that shaped this session" states the opposite of what happened, and does it while
        // reprinting the exact text that was rejected.
        let noteWasDropped = plan?.noteOmitted ?? false
        let note = noteWasDropped
            ? ""
            : context.note.trimmingCharacters(in: .whitespacesAndNewlines)

        if !chips.isEmpty || !note.isEmpty {
            // A bounded panel rather than more centred text.
            //
            // The summary directly above is centred, dim and the same size, so the recap
            // used to read as a second paragraph of it — two different things (what the
            // generator decided, what you told it) set identically. Left alignment inside
            // a tinted container is what separates them; it costs no vertical space, where
            // a heading or a pair of rules would each cost a row.
            VStack(alignment: .leading, spacing: 8) {
                if !chips.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(chips, id: \.self) { StatusPill(text: $0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !note.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { noteExpanded.toggle() }
                    } label: {
                        // `.firstTextBaseline`, so the chevron sits against the opening
                        // line in both states rather than drifting to the middle of an
                        // expanded note.
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            // One line collapsed, not two. This is the first thing you see
                            // after generating, and the note is the one element with no
                            // length ceiling — at 500 characters the old two-line clamp
                            // still let it wrap the card open before the CTA. One line is
                            // enough to recognise what you wrote, which is all the
                            // collapsed state owes you.
                            Text("“\(note)”")
                                .font(.caption).italic()
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.leading)
                                .lineLimit(noteExpanded ? nil : 1)
                                .minimumScaleFactor(0.85)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // Shown whenever there is a note, not only when it overflows.
                            // Detecting truncation means measuring the rendered text, and
                            // the failure mode of guessing at it from a character count is
                            // that a note which DOES wrap loses its only way to open. A
                            // chevron on a short note is merely redundant; a missing one
                            // hides what the user typed.
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                                .rotationEffect(.degrees(noteExpanded ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
        }
    }

    private var contextEditor: some View {
        // Was 16. Pulled in to 13 when the lift selector was added: the panel now has a
        // section title, a lift row, two chip groups and a text field, and the idle card
        // has a hard constraint that Start Session stays above the fold. 13 still reads as
        // separated groups; below about 11 they start merging into one block again.
        VStack(alignment: .leading, spacing: 13) {
            // The editor used to open flush against the card header, so "Ready to train?"
            // and "Anything to know today?" ran together as one block of centred-then-left
            // text. A rule plus real space makes the card read as two parts: what this is,
            // then what you can tell it.
            Divider()
                .overlay(Color.white.opacity(0.10))
                .padding(.top, 4)

            HStack {
                // The section's own title, so it is set like one. At caption/60% it was
                // the same weight as the group labels beneath it and the whole panel read
                // flat — nothing announced that a new part of the card had opened.
                Text("Anything to know today?")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showContext = false
                        context = DraftContext()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            liftSelector

            chipGroup(title: "How you're feeling", chips: ProgramMockData.contextChips)

            chipGroup(title: "Keep it to", chips: ProgramMockData.sessionShapeChips)

            TextField(
                "",
                text: $context.note,
                prompt: Text("Anything else…").foregroundStyle(.white.opacity(0.3)),
                axis: .vertical
            )
            .font(.subheadline)
            .foregroundStyle(.white)
            .lineLimit(1...8)
            .padding(10)
            .background(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        context.isNoteOver ? Color.orange.opacity(0.55) : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
            )

            // Silent until the last 50 characters. Going over is allowed — the field does
            // not stop accepting input — but only the first 500 are sent, so the user is
            // told rather than having their words quietly cut.
            if context.shouldShowNoteCount {
                Text(context.isNoteOver
                     ? "\(-context.noteRemaining) over — only the first \(SessionContextLimits.noteLimit) will be used"
                     : "\(context.noteRemaining) left")
                    .font(.caption2)
                    .foregroundStyle(context.isNoteOver ? Color.orange : .white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var reviseSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What changed?")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        Text("The session gets drafted again with this added to what it already knows.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)

                        contextEditor
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)

                // Pinned, so it never scrolls out of reach behind a long note.
                primaryButton("Revise Session", icon: "sparkles") {
                    showRevise = false
                    regenerate(trigger: "revise")
                }
                .padding()
                // Matches the sheet's own background rather than punching a black bar
                // across the bottom of it. The pinned button still needs a fill — it sits
                // over scrolling content — but it should be the same surface, not a
                // different one.
                .background(Color(white: 0.14))
            }
            .navigationTitle("Revise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRevise = false }
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Same treatment as the weight and reps pickers (`CheckInView:962`). Solid black
        // read as a void with no edge — the sheet had no visible boundary against the dark
        // screen behind it, so it looked less like a card and more like the app blanking.
        .presentationBackground(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func primaryButton(
        _ title: String,
        icon: String?,
        glint: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if glint {
                    GlintingSparkle(size: 14)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.interSemiBold(size: 16))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            // A flat fill is a swatch; a shallow vertical ramp reads as a surface with light
            // on it. Both stops bracket `appAccent` (#FFC850) rather than departing from it —
            // #F5CE70 is a touch lighter at the top, #E8B84A a touch deeper at the bottom — so
            // this is richness, not a new hue.
            .background(
                LinearGradient(
                    colors: [Self.ctaTop, Self.ctaBottom],
                    startPoint: .top, endPoint: .bottom
                )
                .opacity(enabled ? 1 : 0.35)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transitions

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// First generation of the day. Activates on success.
    private func generate(trigger: String = "start") {
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .generating
            expandedRationale = false
        }
        runGeneration(trigger: trigger)
    }

    /// Revise or Refresh on a live session. Same request, but the resulting plan replaces
    /// the current one in place rather than starting a new session.
    private func regenerate(trigger: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .generating
            expandedRationale = false
        }
        runGeneration(trigger: trigger)
    }

    private func runGeneration(trigger: String) {
        generateTask?.cancel()
        let wasActive = sessionStore.isActive

        // Assigned here rather than on appear, where `resetToIdle()` would immediately wipe
        // it again. Setting it at the moment of generation also guarantees the recap under
        // the plan and the plan itself always agree — they are written as a matched pair,
        // and a stale context beside a fresh plan is exactly the incoherence a screenshot
        // would preserve forever.
        if ShowcaseSessionOverride.isEnabled { context = SessionShowcase.context }

        AmplitudeService.shared.track(.sessionGenerationRequested(trigger: trigger))
        // Wall clock, spanning the network too. The Lambda's own duration is already in
        // CloudWatch; what is not measured anywhere else is what the user actually waits.
        let startedAt = Date()

        generateTask = Task {
            do {
                let fresh = try await draftService.generateDraft(context: context, catalog: catalog)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    AmplitudeService.shared.track(.sessionGenerationSucceeded(
                        trigger: trigger,
                        durationSeconds: Date().timeIntervalSince(startedAt),
                        liftCount: fresh.items.count
                    ))
                    // The showcase is authored to look a specific way, and crediting
                    // would rewrite its `detail` lines from whatever the demo account
                    // happens to have logged today — the one thing it is meant to be
                    // independent of.
                    let credited = ShowcaseSessionOverride.isEnabled
                        ? fresh
                        : creditingTodaysWork(fresh)
                    // Generation IS activation. Nothing is proposed, so there is no
                    // commit step and nothing can go stale between here and the user
                    // reading it.
                    if wasActive {
                        sessionStore.replacePlan(from: credited)
                    } else {
                        sessionStore.start(from: credited)
                    }

                    withAnimation(.easeInOut(duration: 0.3)) {
                        plan = credited
                        builtAt = Date()
                        phase = .active
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let draftError = error as? DraftError

                    // Not a failure — the generator ran, and "nothing" was the right
                    // answer. Recorded as a success with zero lifts so it does not
                    // pollute the failure rate, and so `lift_count: 0` stays queryable.
                    if case let .nothingToRecommend(summary) = draftError {
                        AmplitudeService.shared.track(.sessionGenerationSucceeded(
                            trigger: trigger,
                            durationSeconds: Date().timeIntervalSince(startedAt),
                            liftCount: 0
                        ))
                        nothingTodayMessage = summary.isEmpty ? nil : summary
                        withAnimation(.easeInOut(duration: 0.25)) { phase = .nothingToday }
                        return
                    }

                    AmplitudeService.shared.track(.sessionGenerationFailed(
                        trigger: trigger,
                        durationSeconds: Date().timeIntervalSince(startedAt),
                        reason: draftError?.analyticsReason ?? "unknown"
                    ))

                    // A 402 means the local entitlement disagrees with the backend — this
                    // view only renders the generator for premium accounts, so we would
                    // not be here otherwise. Retry can never fix that, so the failure card
                    // would be a dead end. Show the paywall and re-sync in the background,
                    // which resolves it either way: they subscribe, or the refresh
                    // corrects a stale local record.
                    if case .notPremium = draftError {
                        withAnimation(.easeInOut(duration: 0.25)) { resetToIdle() }
                        showUpsell = true
                        Task { await EntitlementsService.shared.syncEntitlementStatus() }
                        return
                    }

                    withAnimation(.easeInOut(duration: 0.25)) { phase = .failed }
                }
            }
        }
    }

    /// Pure navigation. The session is already live and the rail is already up; this only
    /// puts the user where the work is.
    private func startLifting() {
        // Underway withdraws negotiation, so the mode cannot outlive Planning. Starting
        // mid-edit COMMITS: the user is acting on the session in front of them, and
        // silently reverting it as they walk to the rack would be the wrong surprise.
        if editingPlan { finishEditing(save: true) }
        sessionStore.markUnderway()
        sessionStore.pendingSelection = sessionStore.nextIncomplete?.exerciseId
        selectedTab = .lift
    }

    /// Underway's exit. ALWAYS files a receipt.
    ///
    /// It used to file one only when sets had been logged, on the reasoning that a session
    /// you never worked should leave no trace. That reads as a broken step: you tap End
    /// Session, and the app returns you to the start with no acknowledgement that anything
    /// happened — indistinguishable from a bug.
    ///
    /// An explicit action gets a visible result. A receipt with nothing on it is honest,
    /// and it carries a Delete button for exactly that case.
    ///
    /// `discardSession()` is still the leave-no-trace path, which is the distinction that
    /// actually matters: End Session records what happened, Discard says it did not count.
    private func endSession() {
        withAnimation(.easeInOut(duration: 0.3)) {
            sessionStore.finish()
            // Set the phase in the SAME block as `finish()`, rather than leaving it to the
            // `isActive` observer below.
            //
            // `finish()` calls `clear()`, and the observer runs on a later update cycle —
            // so for one render `phase` was still `.active` while the store had already
            // torn the session down, and `activeCard` duly drew the planning card. That
            // was the split-second flash of "Today's Session" before the receipt appeared.
            phase = .receipt
        }
    }

    /// Ends the live session and leaves no record, regardless of what was logged. The
    /// sets themselves are untouched — they remain ordinary logged sets on the Lift tab.
    private func discardSession() {
        sessionStore.end()
        sessionStore.clearOutcome()
        withAnimation(.easeInOut(duration: 0.25)) { resetToIdle() }
    }

    private func resetToIdle() {
        generateTask?.cancel()
        phase = .idle
        plan = nil
        builtAt = nil
        context = DraftContext()
        showContext = false
        expandedRationale = false
        noteExpanded = false
        // Drop the buffer as well as the flag. Clearing only the flag left the store
        // holding a snapshot, which `beginEditing()` then refused to replace — so the next
        // Cancel would have reverted to a stale session.
        sessionStore.commitEditing()
        editingPlan = false
        nothingTodayMessage = nil
    }

    /// Fold today's already-logged sets into a freshly drafted plan.
    ///
    /// The generator is always right about "what's left today" because it always looks at
    /// today's actuals. Satisfied lifts are kept and shown pre-checked rather than
    /// dropped, so the draft explains itself instead of silently omitting the squats you
    /// were expecting.
    private func creditingTodaysWork(_ base: MockDayPlan) -> MockDayPlan {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let credited = base.items.map { item -> MockPlanItem in
            guard let fundamental = TrendsCalculator.fundamentalExercises
                .first(where: { $0.name == item.exerciseName }) else { return item }

            // Baselines excluded, matching the two crediting paths in `CheckInView` and the
            // backend's `today_coverage`. Counting them here would pre-fill tiles at
            // generation time for work that was calibration, not training.
            let logged = allLiftSets.filter {
                $0.exercise?.id == fundamental.id
                    && !$0.isBaselineSet
                    && $0.createdAt >= dayStart
                    && $0.createdAt < dayEnd
            }.count
            guard logged > 0 else { return item }

            var copy = item
            copy.completedSets = min(logged, item.totalSets)
            if logged >= item.totalSets {
                copy.outcome = .landed
                copy.detail = "Already done today · \(logged) sets"
            } else {
                copy.outcome = .underway
                copy.detail = "\(item.planName) · \(logged) of \(item.totalSets) sets"
            }
            // `rationale` is deliberately NOT touched. It used to be overwritten with
            // "1 of 6 sets already logged today", which threw away the one thing the
            // generator produced that nothing else can — and did it silently, for any
            // user with sets logged today. Progress belongs in `detail` and the status
            // pill; the reasoning stays the reasoning.
            return copy
        }

        // Copy the plan and swap the items, rather than constructing a fresh MockDayPlan.
        // The old form listed only `summary` and `items`, so every other field reverted to
        // its default — which is exactly how `noteOmitted` was lost between the service
        // setting it and the card reading it. A copy carries whatever gets added next.
        var credited_plan = base
        credited_plan.items = credited
        return credited_plan
    }
}
