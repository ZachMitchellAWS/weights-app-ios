import SwiftUI
import SwiftData
import Sentry
import StoreKit

struct CheckInView: View {
    @Environment(\.modelContext) private var modelContext

    /// How many months of Estimated1RM history to query for hybrid e1RM lookups.
    private static let e1rmQueryMonths = -3

    private static var estimated1RMsDescriptor: FetchDescriptor<Estimated1RM> {
        let cutoff = Calendar.current.date(byAdding: .month, value: e1rmQueryMonths, to: Date())!
        return FetchDescriptor<Estimated1RM>(
            predicate: #Predicate { !$0.deleted && $0.createdAt >= cutoff },
            sortBy: [SortDescriptor(\.createdAt)]
        )
    }

    @Query(filter: #Predicate<Exercise> { !$0.deleted }, sort: \Exercise.createdAt) private var exercises: [Exercise]
    @Query(filter: #Predicate<LiftSet> { !$0.deleted }) private var allLiftSets: [LiftSet]
    @Query private var userPropertiesItems: [UserProperties]
    @Query(filter: #Predicate<SetPlan> { !$0.deleted }) private var allPlans: [SetPlan]
    @Query(filter: #Predicate<ExerciseGroup> { !$0.deleted }) private var allGroups: [ExerciseGroup]
    @Query private var entitlementRecords: [EntitlementGrant]
    @Query(estimated1RMsDescriptor) private var allEstimated1RM: [Estimated1RM]

    @ObservedObject var selectedSetData: SelectedSetData
    @ObservedObject private var syncService = SyncService.shared
    @Binding var selectedTab: Int

    // MARK: - State

    @State private var selectedLiftIndex: Int = 0
    @State private var viewingDate = Calendar.current.startOfDay(for: Date())
    @State private var setsForExercise: [LiftSet] = []
    @State private var estimated1RMsForExercise: [Estimated1RM] = []
    @State private var weight: Double = 92.5
    @State private var reps: Int = 6
    @State private var showAccessories = false
    @State private var selectedAccessoryId: UUID? = nil
    @State private var isAccessoryMode = false
    @State private var showHub = false
    @State private var hubSection: HubSection = .exercises
    @State private var hubDeepLinkExerciseId: UUID? = nil
    @State private var hubSelectedExerciseId: UUID? = nil
    @State private var activeGroupId: UUID = CheckInView.restoredActiveGroupId()

    // Weight/Reps picker state
    @State private var showWeightPicker = false
    @State private var showRepsPicker = false
    @State private var calculatorTokens: [String] = []
    @State private var currentCalcInput: String = ""
    @State private var repsInput: String = ""
    @State private var weightInputIsFirstKeypress = false
    @State private var repsInputIsFirstKeypress = false

    // Progress options state
    @State private var showExpandedProgressOptions = false
    @State private var sortColumn: SortColumn = .gain
    @State private var sortAscending = true
    @State private var columnHighlighted = false
    @State private var weightDelta: Double = 5.0
    @State private var initialWeightDelta: Double = 5.0
    @State private var repRangeDebounceTask: Task<Void, Never>?

    // Overlay state
    @State private var showSubmitOverlay = false
    @State private var overlayDidIncrease = false
    @State private var overlayDelta: Double = 0
    @State private var overlayNew1RM: Double = 0
    @State private var overlayIntensityColor: Color = .setEasy
    @State private var overlayIntensityLabel: String = "Easy"
    @State private var overlayIsMilestone = false
    @State private var overlayMilestoneTier: StrengthTier = .novice
    @State private var overlayMilestoneExerciseIcon: String = ""
    @State private var overlayMilestoneExerciseName: String = ""
    @State private var overlayMilestoneTargetLabel: String = ""

    // Sync overlay state
    @State private var showSyncOverlay = false
    @State private var syncOverlayDismissed = false
    @State private var showSyncDismissConfirmation = false
    @State private var syncPulsePhase = false
    @State private var showSyncFailedAlert = false

    // Tier journey overlay state
    @AppStorage("hasSeenTierIntro") private var hasSeenTierIntro = false
    @State private var showTierJourneyOverlay = false
    @State private var tierJourneyMode: TierJourneyMode = .intro
    // Hide the tier name on the completion overlay only for the first (starting-tier) unlock.
    @State private var tierJourneyHideTierName = false
    @State private var suppressTierDisplay = false

    // One-shot tutorial popup shown the first time the Lift tab appears
    // after the strength tier is unlocked. Cleared on logout so a re-login
    // on the same install can show it again.
    @AppStorage("hasSeenLiftTutorialAfterTierUnlock") private var hasSeenLiftTutorialAfterTierUnlock = false

    // App Store review prompt: requested once, ever, after the user's first e1RM progress on a
    // fundamental lift once their starting tier is already unlocked. Survives logout (device-lifetime).
    @AppStorage("hasRequestedAppStoreReview") private var hasRequestedAppStoreReview = false
    @Environment(\.requestReview) private var requestReview
    @State private var pendingReviewAfterProgress = false

    // Baseline calibration state
    @State private var pendingCalibrationSet: LiftSet? = nil
    @State private var pendingCalibrationEstimated: Estimated1RM? = nil
    @State private var showCalibrationAlert = false

    // Info sheet for the unlocked-state Sets widget
    @State private var showSetsInfoSheet = false

    // The NEXT badge rasterized so it can sit INSIDE a Text run in the "How this
    // works" explainer. An image inside Text flows as a single unbreakable glyph,
    // which is what lets the sentence wrap underneath it as a normal paragraph —
    // a real SwiftUI view in an HStack can't do that, and an AttributedString
    // background can't be corner-rounded. Rendered once, on first expansion.
    @State private var nextBadgeRendered: Image? = nil
    @Environment(\.displayScale) private var displayScale

    // Inline "How this works" expansion below the rows. Deliberately @State, not
    // @AppStorage: it always starts collapsed on launch so the widget opens compact,
    // and only stays open for as long as the user keeps it open this session.
    // (The old "setsWidgetRangesExpanded" UserDefaults key is now unused.)
    @State private var isSetsRangesExpanded: Bool = false
    // FEATURE FLAG: selectable SETS-widget style variant (see SetsWidgetStyle).
    // Isolated + reversible — pick "Original" (or change in More → Developer →
    // Experimental) to restore the shipping compact tile row exactly.
    @AppStorage("setsWidgetStyle") private var setsWidgetStyleRaw: String = SetsWidgetStyle.verticalRows.rawValue
    private var setsWidgetStyle: SetsWidgetStyle { SetsWidgetStyle(rawValue: setsWidgetStyleRaw) ?? .verticalRows }
    @State private var setsRangesChevronBob = false
    // Guards the bob animation from restarting if the view re-renders —
    // a one-shot per view-instance, not persisted (the user gets the
    // attention nudge once per session, not every cell update).
    @State private var hasBobbedChevron: Bool = false

    // Effort preset hint alert — fires when the user taps an empty effort tile
    // (easy/moderate/hard/redline) in the Sets widget but no preset can be
    // computed for the current exercise/state.
    @State private var presetHintTitle: String = ""
    @State private var presetHintMessage: String = ""
    @State private var showPresetHintAlert: Bool = false

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    // Retained like `hapticFeedback` above. The next-focus chip and the "LET'S GO"
    // CTA previously built a generator inline and let it deallocate immediately,
    // which leaves the Taptic Engine cold and frequently drops the first tap —
    // `prepare()` + a persistent instance is what makes these land reliably.
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    @State private var tappedTileIndex: Int? = nil
    @State private var scrollProxy: ScrollViewProxy?
    @State private var progressOptionsHighlighted = false
    @State private var logSetFlashActive = false
    @State private var hasAppeared = false
    @State private var weightIsSet: Bool = false
    @State private var repsIsSet: Bool = false
    @State private var weightHighlight: Bool = false
    @State private var repsHighlight: Bool = false
    @State private var focusedPanelVisible: Bool = true
    @State private var showE1RMPopup: Bool = false
    @State private var showE1RMUpsell: Bool = false
    @State private var showReadyToLift: Bool = false
    // Auto-trigger for the "Ready to lift?" popup. Observes the tutorial coordinator
    // so we can fire it once the intro flow (tutorial + resources hint) completes.
    @ObservedObject private var tutorialPresenter = TutorialPresenter.shared
    @AppStorage("hasSeenResourcesHint") private var hasSeenResourcesHint = false
    @State private var safeAreaTopInset: CGFloat = 59

    // MARK: - Computed

    private var userProperties: UserProperties {
        userPropertiesItems.first ?? UserProperties()
    }

    private var isPremium: Bool {
        if FreeOverride.isEnabled { return false }
        return PremiumOverride.isEnabled || EntitlementGrant.isPremium(entitlementRecords)
    }

    private var bodyweight: Double {
        userProperties.bodyweight ?? 200.0
    }

    private var biologicalSex: String {
        userProperties.biologicalSex ?? "male"
    }

    private var sex: BiologicalSex {
        BiologicalSex(rawValue: biologicalSex) ?? .male
    }

    private var fundamentals: [TrendsCalculator.FundamentalExercise] {
        TrendsCalculator.fundamentalExercises
    }

    private var activeGroup: ExerciseGroup? {
        allGroups.first(where: { $0.groupId == activeGroupId })
            ?? allGroups.first(where: { $0.groupId == ExerciseGroup.tierExercisesId })
    }

    private var activeGroupExercises: [Exercise] {
        guard let group = activeGroup else { return [] }
        return group.exerciseIds.compactMap { id in
            exercises.first(where: { $0.id == id })
        }
    }

    private var selectedGroupExercise: Exercise? {
        let groupExercises = activeGroupExercises
        guard selectedLiftIndex < groupExercises.count else { return groupExercises.first }
        return groupExercises[selectedLiftIndex]
    }

    @State private var strengthTierResult: TrendsCalculator.StrengthTierResult = TrendsCalculator.StrengthTierResult(
        overallTier: .none,
        exerciseTiers: TrendsCalculator.fundamentalExercises.map { (exercise: $0, e1rm: nil as Double?, tier: StrengthTier.none) },
        limitingExercise: TrendsCalculator.fundamentalExercises[0]
    )
    @State private var latestE1RMs: [UUID: Double] = [:]
    @State private var lastTrainedDates: [UUID: Date] = [:]
    @State private var recentSetCounts: [UUID: Int] = [:]

    private var nextFocus: TrendsCalculator.FundamentalExercise? {
        TrendsCalculator.nextFocusExercise(
            exerciseTiers: strengthTierResult.exerciseTiers,
            lastTrainedDates: lastTrainedDates,
            recentSetCounts: recentSetCounts,
            bodyweight: bodyweight,
            sex: sex
        )
    }

    private var actualToday: Date { Calendar.current.startOfDay(for: Date()) }
    private var isViewingToday: Bool { viewingDate == actualToday }

    private var current1RM: Double {
        if let exerciseId = selectedExercise?.id,
           let fromQuery = allEstimated1RM.filter({ $0.exercise?.id == exerciseId }).max(by: { $0.createdAt < $1.createdAt }) {
            return fromQuery.value
        }
        return selectedExercise?.currentE1RMLocalCache ?? 0
    }

    private var availablePlates: [Double] {
        userProperties.availableChangePlates.sorted { $0 > $1 }
    }

    private var availableWeightDeltas: [Double] {
        var deltas = Set<Double>()
        let multiplier = selectedExercise?.exerciseLoadType.plateMultiplier ?? 2.0
        for plateWeight in availablePlates {
            let increment = plateWeight * multiplier
            if increment <= 5.0 {
                deltas.insert(increment)
            }
        }
        if multiplier == 1.0 {
            deltas.insert(2.5)
        }
        deltas.insert(5.0)
        return Array(deltas).sorted()
    }

    private var minWeightDelta: Double {
        availableWeightDeltas.first ?? 5.0
    }

    private var maxWeightDelta: Double {
        5.0
    }

    private var hasWeightDeltaChanges: Bool {
        abs(weightDelta - initialWeightDelta) > 0.01
    }

    private var filteredSuggestions: [OneRMCalculator.Suggestion] {
        guard current1RM > 0 else { return [] }
        let suggestions = OneRMCalculator.minimizedSuggestions(current1RM: current1RM, increment: weightDelta)
        return suggestions.filter {
            $0.reps >= userProperties.progressMinReps && $0.reps <= userProperties.progressMaxReps
        }
    }

    private var selectedExercise: Exercise? {
        if isAccessoryMode, let accId = selectedAccessoryId {
            return exercises.first(where: { $0.id == accId })
        }
        return selectedGroupExercise
    }

    private var datesWithSets: [Date] {
        let calendar = Calendar.current
        var unique = Set<Date>()
        for set in setsForExercise {
            unique.insert(calendar.startOfDay(for: set.createdAt))
        }
        return unique.sorted()
    }

    private var previousSessionDate: Date? {
        datesWithSets.last(where: { $0 < viewingDate })
    }

    private var nextSessionDate: Date? {
        guard !isViewingToday else { return nil }
        return datesWithSets.first(where: { $0 > viewingDate }) ?? actualToday
    }

    private var todaysSets: [LiftSet] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: viewingDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return setsForExercise.filter { !$0.deleted && $0.createdAt >= dayStart && $0.createdAt < dayEnd }
    }


    private var nonGroupExercises: [Exercise] {
        let groupIds = Set(activeGroupExercises.map(\.id))
        return exercises.filter { !groupIds.contains($0.id) }
    }

    // Set plan
    private var activeSetPlan: SetPlan? {
        guard let planId = userProperties.activeSetPlanId else { return nil }
        return allPlans.first(where: { $0.id == planId })
    }

    // MARK: - Body

    var body: some View {
        checkInSheets
    }

    // Split into two computed properties to help the type checker:
    // - checkInZStack: the ZStack with all overlays
    // - checkInContent: the ZStack + all modifiers

    private var checkInZStack: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            safeAreaTopInset = geo.safeAreaInsets.top
                        }
                    }
                )

            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    strengthHeader
                        .id("checkInTop")
                    groupSelector
                    focusedLiftPanel
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onChange(of: geo.frame(in: .global).minY) { _, newMinY in
                                        let visible = newMinY > safeAreaTopInset
                                        if visible != focusedPanelVisible {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                focusedPanelVisible = visible
                                            }
                                        }
                                    }
                            }
                        )
                    setsWidget
                        .id("setsWidget")
                    progressOptionsWidget
                        .id("progressOptions")
                        // Zero-height anchor pinned to the TOP of the progress-options
                        // widget (== bottom of the sets widget). Scrolling to this
                        // lands the boundary at a predictable fraction of the screen,
                        // independent of the (tall) progress-options widget's height.
                        .overlay(alignment: .top) {
                            Color.clear
                                .frame(height: 1)
                                .id("progressTop")
                        }
                        // Opt out of the Sets widget's expansion animation so
                        // the ViewfinderPulse inside doesn't snapshot-ghost
                        // while SwiftUI animates this sibling's position
                        // shift.
                        .animation(nil, value: isSetsRangesExpanded)
                    // accessorySection // TODO: Re-enable when splits functionality is wired up

                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(height: 1)
                        Image("LiftTheBullIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(.white.opacity(0.15))
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                    Text("Strength estimates are approximations based on your logged sets and standard formulas. Always train within your limits and consult a physician before beginning or modifying any exercise program.")
                        .font(.inter(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .onAppear { scrollProxy = proxy }
            }

            // Sticky exercise banner
            if !focusedPanelVisible {
                VStack {
                    stickyExerciseBanner
                    Spacer()
                }
                .transition(.opacity)
                .zIndex(10)
            }

            // Floating log bar
            VStack {
                Spacer()
                floatingLogBar
            }

            // Overlays
            if showSubmitOverlay {
                if overlayIsMilestone {
                    milestoneOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .zIndex(20)
                } else {
                    submitOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .zIndex(20)
                }
            }

            if showTierJourneyOverlay {
                TierJourneyOverlay(
                    mode: tierJourneyMode,
                    exerciseTiers: strengthTierResult.exerciseTiers,
                    hideTierName: tierJourneyHideTierName,
                    onDismiss: {
                        let wasIntro = { if case .intro = tierJourneyMode { return true }; return false }()
                        if wasIntro {
                            hasSeenTierIntro = true
                        }
                        suppressTierDisplay = false
                        withAnimation(.easeOut(duration: 0.18)) {
                            showTierJourneyOverlay = false
                        }
                        // Highlight log set inputs after intro dismiss
                        if wasIntro {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                triggerLogSetFlash(markFieldsSet: false)
                            }
                        }
                    },
                    onNavigateToExercise: { exerciseId in
                        navigateToTierExercise(exerciseId)
                    },
                    onNavigateToStrength: {
                        selectedSetData.pendingTrendsTab = .strength
                        selectedSetData.pendingScrollToStrengthTop = true
                        selectedTab = 0
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(21)
            }

            // e1RM progression popup
            if showE1RMPopup, let exercise = selectedExercise {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showE1RMPopup = false
                        }
                    }
                    .zIndex(22)

                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("e1RM Progression")
                                .font(.interSemiBold(size: 13))
                                .foregroundStyle(.white.opacity(0.85))
                            Text("\(exercise.name) · Last 3 months")
                                .font(.inter(size: 11))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showE1RMPopup = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.1), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                        .padding(.horizontal, 16)

                    OneRMProgressionChart(
                        dataPoints: TrendsCalculator.oneRMProgression(
                            from: estimated1RMsForExercise,
                            exerciseName: exercise.name
                        )
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 14)

                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                        .padding(.horizontal, 16)

                    if isPremium {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showE1RMPopup = false
                            }
                            selectedSetData.pendingTrendsTab = .analytics
                            selectedTab = 0
                        } label: {
                            HStack(spacing: 6) {
                                Text("View Full Analytics")
                                    .font(.interSemiBold(size: 13))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Color.appAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showE1RMPopup = false
                            }
                            AmplitudeService.shared.track(.lockedWidgetTapped(feature: "e1rm_estimate"))
                            showE1RMUpsell = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Unlock Full Analytics")
                                    .font(.interSemiBold(size: 13))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.appAccent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                }
                .background(
                    LinearGradient(
                        colors: [Color(white: 0.13), Color(white: 0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(23)
            }
            // Sync in progress overlay
            if showSyncOverlay {
                syncInProgressOverlay
                    .transition(.opacity)
                    .zIndex(25)
            }
            // "Ready to lift?" next-focus popup
            if showReadyToLift, let focus = nextFocus {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .onTapGesture {
                        AmplitudeService.shared.track(.readyToLiftDismissed(focusExercise: focus.name))
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showReadyToLift = false
                        }
                    }
                    .zIndex(26)

                readyToLiftCard(focus: focus)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(27)
            }
        }
    }

    private var checkInContent: some View {
        checkInZStack
        .onChange(of: syncService.initialSyncComplete) { _, complete in
            if complete {
                if showSyncOverlay {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showSyncOverlay = false
                    }
                }
                // Reload exercise data after delay to let SwiftData process commits
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    loadDataForSelectedLift()
                }
                // Second reload as safety net
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if setsForExercise.isEmpty {
                        loadDataForSelectedLift()
                    }
                }
                // Now safe to evaluate tier journey (user properties are synced)
                evaluateTierJourney()
                evaluateLiftTutorialTrigger()
            }
        }
        .onChange(of: syncService.syncFailed) { _, failed in
            if failed { showSyncFailedAlert = true }
        }
        .onChange(of: showSubmitOverlay) { _, isShowing in
            // When the e1RM-increase dialog appears, snap to the top of the Lift tab.
            if isShowing, overlayDidIncrease {
                scrollProxy?.scrollTo("checkInTop", anchor: .top)
            }
            // After the "Increased 1RM" dialog dismisses (auto-dismiss or tap), request an App Store
            // review — once ever — for the queued first post-unlock fundamental progress set.
            guard !isShowing, pendingReviewAfterProgress else { return }
            pendingReviewAfterProgress = false
            hasRequestedAppStoreReview = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                requestReview()
            }
        }
        // First-time trigger: the resources-hint alert (which follows the tutorial
        // popup) was just dismissed — mark the intro complete and show Ready to Lift.
        .onChange(of: tutorialPresenter.showResourcesHint) { wasShowing, isShowing in
            guard wasShowing, !isShowing else { return }
            hasSeenResourcesHint = true
            maybeShowReadyToLift()
        }
        // Late-data recovery ONLY: if next-focus wasn't computed yet when the tab
        // appeared (first launch, sync still landing), fire once it first becomes
        // available. Restricted to the nil → non-nil transition on purpose — when
        // logging sets shifts the recommendation from one exercise to another
        // mid-session, the popup must NOT reappear.
        .onChange(of: nextFocus?.id) { oldValue, newValue in
            guard oldValue == nil, newValue != nil else { return }
            maybeShowReadyToLift()
        }
        .alert("Sync Failed", isPresented: $showSyncFailedAlert) {
            Button("Retry") {
                Task { await SyncService.shared.performInitialSync(isNewUser: false) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("We couldn't load your data. Check your connection and try again.")
        }
        .alert(presetHintTitle, isPresented: $showPresetHintAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(presetHintMessage)
        }
        .confirmationDialog("Sync in Progress", isPresented: $showSyncDismissConfirmation, titleVisibility: .visible) {
            Button("Continue Anyway") {
                syncOverlayDismissed = true
                withAnimation(.easeOut(duration: 0.3)) {
                    showSyncOverlay = false
                }
            }
            Button("Keep Waiting", role: .cancel) { }
        } message: {
            Text("Your data is still syncing. Logging sets before sync completes may cause duplicates or inconsistencies.")
        }
    }

    private var checkInLifecycle: some View {
        checkInContent
        .task(id: "\(exercises.compactMap(\.currentE1RMLocalCache).reduce(0, +))-\(activeGroupId)-\(allEstimated1RM.count)-\(allLiftSets.count)") {
            strengthTierResult = TrendsCalculator.strengthTierAssessment(
                from: allEstimated1RM,
                exercises: exercises,
                bodyweight: bodyweight,
                biologicalSex: biologicalSex
            )

            var e1rms: [UUID: Double] = [:]
            var trainedDates: [UUID: Date] = [:]
            // Scan the active group's exercises (for the carousel) PLUS every
            // fundamental, so the next-focus inputs (lastTrainedDates / latestE1RMs)
            // are complete regardless of which group is selected. Otherwise next-focus
            // flips depending on the active group, since the loop would only see the
            // fundamentals that happen to be in the current group.
            var exercisesToScan = activeGroupExercises
            let scannedIds = Set(activeGroupExercises.map(\.id))
            for fe in TrendsCalculator.fundamentalExercises where !scannedIds.contains(fe.id) {
                if let ex = exercises.first(where: { $0.id == fe.id }) {
                    exercisesToScan.append(ex)
                }
            }
            for ex in exercisesToScan {
                // Check allEstimated1RM for latest value for this exercise
                if let fromQuery = allEstimated1RM.filter({ $0.exercise?.id == ex.id }).max(by: { $0.createdAt < $1.createdAt }) {
                    e1rms[ex.id] = fromQuery.value
                } else if let e1rm = ex.currentE1RMLocalCache {
                    // Fall back to cache
                    e1rms[ex.id] = e1rm
                }
                if let date = ex.currentE1RMDateLocalCache {
                    trainedDates[ex.id] = date
                }
            }
            latestE1RMs = e1rms
            lastTrainedDates = trainedDates

            // Count sets logged inside the next-focus rate-limit window, per fundamental
            // exercise. The function-side gate skips any exercise at/over the cap.
            let cutoff = Date().addingTimeInterval(-TrendsCalculator.nextFocusRecentWindowSeconds)
            let fundamentalIds = Set(TrendsCalculator.fundamentalExercises.map(\.id))
            var counts: [UUID: Int] = [:]
            for set in allLiftSets {
                guard set.createdAt >= cutoff,
                      let exId = set.exercise?.id,
                      fundamentalIds.contains(exId) else { continue }
                counts[exId, default: 0] += 1
            }
            recentSetCounts = counts
        }
        .onAppear {
            // Evaluate the tutorial-popup trigger on every tab appearance
            // (not just first-appearance) so returning to Lift after unlocking
            // the tier on this same launch still fires the popup. The
            // AppStorage flag guarantees one-shot semantics.
            if syncService.initialSyncComplete {
                evaluateLiftTutorialTrigger()
            }

            // Per-launch auto-show of "Ready to lift?", evaluated on every Lift-tab
            // appearance (including returning from another tab).
            // `readyToLiftShownThisLaunch` keeps it to once per launch. Deliberately
            // NOT gated on initialSyncComplete: a returning user already has local
            // next-focus data, and gating would skip the show without the nil →
            // non-nil onChange below ever firing to recover it.
            maybeShowReadyToLift()

            if hasAppeared {
                // Re-fetch exercise data on tab return (e.g., after deleting from History)
                loadDataForSelectedLift()
                return
            }
            hasAppeared = true

            print("📋 LOCAL UserProperties on appear: bodyweight=\(String(describing: userProperties.bodyweight)), biologicalSex=\(String(describing: userProperties.biologicalSex)), weightUnit=\(userProperties.preferredWeightUnit.rawValue)")

            // Show sync overlay if sync hasn't completed and user hasn't dismissed it
            if !syncService.initialSyncComplete && !syncOverlayDismissed {
                showSyncOverlay = true
            }

            if syncService.syncFailed {
                showSyncFailedAlert = true
            }

            // Only evaluate tier journey if sync is already done (e.g., subsequent app opens)
            if syncService.initialSyncComplete {
                evaluateTierJourney()
            }

            // Load data for selected exercise — delayed to let @Query resolve
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                loadDataForSelectedLift()
            }
        }
        .onChange(of: exercises.count) { _, _ in
            // Exercises query resolved — reload selected exercise data
            if setsForExercise.isEmpty && selectedExercise != nil {
                loadDataForSelectedLift()
            }
        }
        .onChange(of: exercises.compactMap(\.currentE1RMLocalCache).count) { oldCount, newCount in
            // Reload exercise data whenever e1RM count increases and sets are empty.
            if newCount > oldCount && setsForExercise.isEmpty {
                loadDataForSelectedLift()
            }

            // Re-evaluate after sync populates data (only on first transition from 0)
            // Don't evaluate during calibration — the applyCalibration path handles tier journey
            if oldCount == 0 && newCount > 0 {
                if !showTierJourneyOverlay && pendingCalibrationSet == nil {
                    evaluateTierJourney()
                }
            }

            // In none state, default to first unlogged exercise — but NOT while the user is viewing
            // an accessory. A non-fundamental first set bumps this e1RM count too, and without this
            // guard it would yank the user onto a fundamental (selectedLiftIndex change → exits
            // accessory mode).
            if !isAccessoryMode,
               strengthTierResult.overallTier == .none,
               activeGroupId == ExerciseGroup.tierExercisesId {
                let unloggedExerciseIds = Set(
                    strengthTierResult.exerciseTiers
                        .filter { $0.e1rm == nil }
                        .map { $0.exercise.id }
                )
                if let firstUnloggedIndex = activeGroupExercises.firstIndex(where: { unloggedExerciseIds.contains($0.id) }) {
                    selectedLiftIndex = firstUnloggedIndex
                }
            }

            // Restore persisted exercise selection (overrides defaults above)
            if let restoredExerciseId = CheckInView.restoredActiveExerciseId(),
               let index = activeGroupExercises.firstIndex(where: { $0.id == restoredExerciseId }) {
                selectedLiftIndex = index
            }

            loadDataForSelectedLift()
        }
        .onChange(of: selectedLiftIndex) { _, _ in
            isAccessoryMode = false
            selectedAccessoryId = nil
            viewingDate = actualToday
            loadDataForSelectedLift()
            persistActiveExercise(selectedGroupExercise?.id)
        }
        .onChange(of: activeGroupId) { _, newValue in
            selectedLiftIndex = 0
            isAccessoryMode = false
            selectedAccessoryId = nil
            loadDataForSelectedLift()
            persistActiveGroup(newValue)
            persistActiveExercise(activeGroupExercises.first?.id)
        }
    }

    private var checkInSheets: some View {
        checkInLifecycle
        .sheet(isPresented: $showHub, onDismiss: {
            if let selectedId = hubSelectedExerciseId {
                if let index = activeGroupExercises.firstIndex(where: { $0.id == selectedId }) {
                    isAccessoryMode = false
                    selectedAccessoryId = nil
                    selectedLiftIndex = index
                } else {
                    isAccessoryMode = true
                    selectedAccessoryId = selectedId
                    loadDataForExercise(selectedId)
                }
                hubSelectedExerciseId = nil
            }
            hubDeepLinkExerciseId = nil
            hubSection = .exercises
        }) {
            HubView(
                exercises: exercises,
                selectedExercisesId: $hubSelectedExerciseId,
                selectedSection: $hubSection,
                activeGroupId: $activeGroupId,
                deepLinkExerciseId: hubDeepLinkExerciseId,
                onExerciseCreated: { name, loadType, movementType, icon in
                    createExercise(name: name, loadType: loadType, movementType: movementType, icon: icon)
                },
                onExerciseSaved: { exercise, name, movementType, icon, notes, barbellWeight in
                    saveExercise(exercise, name: name, movementType: movementType, icon: icon, notes: notes, barbellWeight: barbellWeight)
                },
                onExerciseDeleted: { exercise in
                    deleteExercise(exercise)
                    showHub = false
                }
            )
            .presentationDetents([.large])
            .presentationContentInteraction(.scrolls)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWeightPicker) {
            weightPickerSheet
                .presentationDetents([.height(480)])
                .presentationDragIndicator(.visible)
                .presentationBackground(
                    LinearGradient(
                        colors: [Color(white: 0.18), Color(white: 0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .sheet(isPresented: $showRepsPicker) {
            repsPickerSheet
                .presentationDetents([.height(480)])
                .presentationDragIndicator(.visible)
        }
        .alert("How did that feel?", isPresented: $showCalibrationAlert) {
            Button("Easy") { applyCalibration(effort: .easy) }
            Button("Moderate") { applyCalibration(effort: .moderate) }
            Button("Hard") { applyCalibration(effort: .hard) }
            Button("Near Max") { applyCalibration(effort: .progress) }
            Button("Max Effort") { applyCalibration(effortFraction: 1.0) }
            // .cancel role claims the cancel slot so iOS doesn't inject a
            // phantom Cancel button. Labeled "Cancel" so the system styling
            // matches what users expect from that label.
            Button("Cancel", role: .cancel) { discardPendingCalibration() }
        } message: {
            Text("This helps estimate your 1RM for better suggestions.")
        }
        .fullScreenCover(isPresented: $showE1RMUpsell) {
            UpsellView(initialPage: 3) { _ in showE1RMUpsell = false }
        }
        .overlay {
            if showSetsInfoSheet {
                SetsInfoOverlay(isPresented: $showSetsInfoSheet)
                    .transition(.opacity)
                    .zIndex(50)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSetsInfoSheet)
    }

    // MARK: - Phase 1: Strength Header

    private var strengthHeader: some View {
        // Blank the tier only for the genuine unlock-spoiler case (`suppressTierDisplay`, set on a
        // fundamental's first tier log). Previously this also keyed off `showCalibrationAlert`, which
        // forced the locked "Unlock Your Strength Tier" state for an already-unlocked user logging an
        // accessory's first set — flashing the checklist as the alert dismissed.
        let tier: StrengthTier = suppressTierDisplay ? .none : strengthTierResult.overallTier
        let isChecklistMode = tier == .none
        let loggedCount = strengthTierResult.exerciseTiers.filter { $0.e1rm != nil }.count
        let limitingTier = strengthTierResult.exerciseTiers
            .first(where: { $0.exercise.id == strengthTierResult.limitingExercise.id })?.tier ?? .novice

        return VStack(spacing: 4) {
            if isChecklistMode {
                let isTierGroup = activeGroupId == ExerciseGroup.tierExercisesId
                // Row 1: Title on left, dots on right
                HStack(alignment: .center) {
                    Text("Unlock Your Strength Tier")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    HStack(spacing: 6) {
                        ForEach(Array(strengthTierResult.exerciseTiers.enumerated()), id: \.offset) { _, item in
                            Circle()
                                .fill(item.e1rm != nil ? Color.appAccent : .white.opacity(0.15))
                                .overlay(
                                    item.e1rm == nil
                                        ? Circle().stroke(.white.opacity(0.3), lineWidth: 1)
                                        : nil
                                )
                                .frame(width: 8, height: 8)
                        }
                    }
                }

                // Row 2: Subtitle on left, count on right
                HStack(alignment: .center) {
                    Text(isTierGroup ? "Log at least one set of each exercise" : "Log all 5 strength tier exercises")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))

                    Spacer()

                    Text("\(loggedCount) of 5 logged")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                }
            } else {
                // Normal tier header
                // Labels row
                HStack {
                    Text("STRENGTH TIER")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .tracking(1)
                        .padding(.leading, 30)
                    Spacer()
                    if nextFocus != nil {
                        Text("NEXT FOCUS")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                            .tracking(1)
                    }
                }

                // Content row
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Image(tier.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(StrengthTier.elite.color)
                        .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - 4 }
                    Text(tier.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(tier.color)

                    Spacer()

                    if let focus = nextFocus {
                        // Chip treatment so the next-focus name reads as tappable
                        // (the tap itself is handled by the right-hand overlay
                        // below, which is sized to contain this chip). Same
                        // vocabulary as `verticalPlanSelector` — radius 7, faint
                        // fill + hairline border, accent-tinted leading icon.
                        // Kept at the original caption size, and the icon at 13pt,
                        // so the content row's height stays driven by the 22pt
                        // tier title rather than by this chip.
                        HStack(spacing: 5) {
                            Image(focus.icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .foregroundStyle(Color.appAccent.opacity(0.8))
                            Text(shortDisplayName(for: focus.name))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        // Asymmetric padding: tight on the leading edge and top/bottom
                        // so the icon can fill more of the chip, but the original 9pt
                        // kept on the trailing edge so the text keeps its breathing
                        // room. 3pt vertical caps the chip at 18 + 6 = 24pt, which
                        // still fits the row's ~26pt baseline band (see guide below).
                        .padding(.leading, 5)
                        .padding(.trailing, 9)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                        // Sit the chip inside the row's existing baseline band
                        // instead of hanging below it. Same guide the tier icon
                        // uses above: without it the chip's bottom padding extends
                        // past the 22pt title's descender and grows the row.
                        .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - 4 }
                    } else if limitingTier == .legend {
                        Text("All lifts at Legend tier")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(12)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isChecklistMode ? .white.opacity(0.15) : tier.color.opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSetData.pendingTrendsTab = .strength
            selectedSetData.pendingScrollToStrengthTop = true
            selectedTab = 0
        }
        // Right-hand NEXT FOCUS area opens the "Ready to lift?" popup instead of
        // navigating to the Strength tab. Taps elsewhere fall through to the
        // navigation gesture above.
        //
        // Sized to contain the whole next-focus chip so the visible button and its
        // hit target agree. Worst case is "Deadlifts" (the longest fundamental
        // after `shortDisplayName` shortening) at ~94pt: 18pt padding + 13pt icon
        // + 5pt spacing + ~58pt of caption text. 0.35 clears that on the narrowest
        // supported phone (~343pt card → ~120pt) while still starting well right of
        // the tier title, which ends around 186pt even for "Intermediate".
        .overlay {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Color.clear
                        .frame(width: geo.size.width * 0.35)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let focus = nextFocus {
                                mediumHaptic.impactOccurred()
                                // Warm the engine for the popup's "LET'S GO" CTA,
                                // the likely next tap.
                                mediumHaptic.prepare()
                                // A manual open counts as this launch's showing, so the
                                // automatic one can't fire later in the same session.
                                // Manual taps themselves are never gated by this flag.
                                tutorialPresenter.readyToLiftShownThisLaunch = true
                                AmplitudeService.shared.track(
                                    .readyToLiftShown(focusExercise: focus.name, trigger: "manual")
                                )
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                    showReadyToLift = true
                                }
                            } else {
                                selectedSetData.pendingTrendsTab = .strength
                                selectedSetData.pendingScrollToStrengthTop = true
                                selectedTab = 0
                            }
                        }
                }
            }
        }
    }

    // "Ready to lift?" popup — surfaces the same next-focus fundamental and, on
    // its CTA, selects that exercise on the Lift tab (navigateToTierExercise).
    /// Auto-show the "Ready to lift?" popup at most once per launch, only after the
    /// user has unlocked their starting tier AND been through the intro flow
    /// (tutorial popup + the resources-hint alert). First appearance fires right
    /// after the resources hint is dismissed; thereafter it fires on the first Lift
    /// tab view of each new launch.
    private func maybeShowReadyToLift() {
        guard !tutorialPresenter.readyToLiftShownThisLaunch,
              !showReadyToLift,
              userProperties.hasMetStrengthTierConditions,
              hasSeenResourcesHint,
              nextFocus != nil else { return }
        tutorialPresenter.readyToLiftShownThisLaunch = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            // Re-read nextFocus after the delay rather than capturing it above: the
            // event should name what was actually put on screen.
            guard let focus = nextFocus, !showReadyToLift else { return }
            AmplitudeService.shared.track(
                .readyToLiftShown(focusExercise: focus.name, trigger: "auto")
            )
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                showReadyToLift = true
            }
        }
    }

    private func readyToLiftCard(focus: TrendsCalculator.FundamentalExercise) -> some View {
        let accent = Color.appAccent
        return VStack(spacing: 16) {
            Text("NEXT FOCUS")
                .font(.interSemiBold(size: 11))
                .tracking(3)
                .foregroundStyle(accent)

            Text("Ready to Lift?")
                .font(.bebasNeue(size: 46))
                .tracking(1)
                .foregroundStyle(.white)

            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.35), accent.opacity(0.0)],
                                         center: .center, startRadius: 4, endRadius: 95))
                    .frame(width: 180, height: 180)
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 120, height: 120)
                Circle()
                    .strokeBorder(accent.opacity(0.6), lineWidth: 2)
                    .frame(width: 120, height: 120)
                Image(focus.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 68, height: 68)
                    .foregroundStyle(accent)
            }
            .frame(height: 150)

            VStack(spacing: 3) {
                Text(focus.name.uppercased())
                    .font(.bebasNeue(size: 32))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                Text("Your next recommended focus")
                    .font(.inter(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Button {
                mediumHaptic.impactOccurred()
                AmplitudeService.shared.track(.readyToLiftCTATapped(focusExercise: focus.name))
                withAnimation(.easeOut(duration: 0.18)) { showReadyToLift = false }
                navigateToTierExercise(focus.id)
            } label: {
                HStack(spacing: 8) {
                    Text("LET'S GO")
                        .font(.interSemiBold(size: 17))
                        .tracking(1)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 26)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(maxWidth: 330)
        .background(
            LinearGradient(colors: [Color(white: 0.14), Color(white: 0.09)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(accent.opacity(0.25), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                AmplitudeService.shared.track(.readyToLiftDismissed(focusExercise: focus.name))
                withAnimation(.easeOut(duration: 0.18)) { showReadyToLift = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .padding(.horizontal, 24)
    }

    // MARK: - Phase 1: Group Selector

    private var groupSelector: some View {
        VStack(spacing: 8) {
            HStack {
                Menu {
                    Button {
                        hubSection = .groups
                        showHub = true
                    } label: {
                        Label("Open Catalog", systemImage: "list.bullet")
                    }

                    Divider()

                    Section("Presets") {
                        ForEach(allGroups.filter { !$0.isCustom }.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.groupId) { group in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                activeGroupId = group.groupId
                            } label: {
                                if group.groupId == activeGroupId {
                                    Label(group.name, systemImage: "checkmark")
                                } else {
                                    Text(group.name)
                                }
                            }
                        }
                    }

                    let customGroups = allGroups.filter { $0.isCustom }.sorted(by: { $0.sortOrder < $1.sortOrder })
                    if !customGroups.isEmpty {
                        Section("Custom") {
                            ForEach(customGroups, id: \.groupId) { group in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    activeGroupId = group.groupId
                                } label: {
                                    if group.groupId == activeGroupId {
                                        Label(group.name, systemImage: "checkmark")
                                    } else {
                                        Text(group.name)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\((activeGroup?.name ?? "STRENGTH TIER").uppercased()) EXERCISES")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                            .tracking(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .animation(.none, value: activeGroupId)
                }
                Spacer()
                Button {
                    hubSection = .groups
                    showHub = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 4)

            groupSelectorContent
        }
    }

    private var groupSelectorContent: some View {
        let groupExercises = activeGroupExercises
        let fundamentalIds = Set(fundamentals.map(\.id))

        return GeometryReader { outerGeo in
            // Use at least 5 slots for sizing so items don't stretch when group has fewer exercises
            let slotCount = max(CGFloat(groupExercises.count), 5)
            let totalSpacing = CGFloat(6) * (slotCount - 1)
            let itemWidth = (outerGeo.size.width - totalSpacing) / slotCount
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(groupExercises.enumerated()), id: \.element.id) { index, exercise in
                        let isSelected = index == selectedLiftIndex && !isAccessoryMode
                        let isFundamental = fundamentalIds.contains(exercise.id)
                        let fundamentalExercise = isFundamental ? fundamentals.first(where: { $0.id == exercise.id }) : nil
                        let tier = isFundamental
                            ? (strengthTierResult.exerciseTiers.first(where: { $0.exercise.id == exercise.id })?.tier ?? .novice)
                            : nil
                        let highlightColor = Color.appAccent
                        let (nameLine1, nameLine2): (String, String?) = {
                            let name = shortDisplayName(for: exercise.name)
                            guard !isFundamental, name.count > 11 else { return (name, nil) }
                            // Find the last space at or before index 11
                            let prefix = name.prefix(12)
                            if let splitIndex = prefix.lastIndex(of: " ") {
                                return (String(name[name.startIndex..<splitIndex]), String(name[name.index(after: splitIndex)...]))
                            }
                            // No space in first 11 chars — split at first space
                            if let firstSpace = name.firstIndex(of: " ") {
                                return (String(name[name.startIndex..<firstSpace]), String(name[name.index(after: firstSpace)...]))
                            }
                            return (name, nil)
                        }()

                        VStack(spacing: 4) {
                            Spacer()

                            Image(exercise.icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .foregroundStyle(isSelected ? highlightColor : .white.opacity(0.5))

                            if isFundamental {
                                Text(nameLine1)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isSelected ? highlightColor.opacity(0.9) : .white.opacity(0.45))
                                    .lineLimit(1)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.7)
                            } else {
                                VStack(spacing: 0) {
                                    Text(nameLine1)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(isSelected ? highlightColor.opacity(0.9) : .white.opacity(0.45))
                                        .frame(width: itemWidth - 8)
                                        .lineLimit(1)
                                        .multilineTextAlignment(.center)
                                    Text(nameLine2 ?? "")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(isSelected ? highlightColor.opacity(0.9) : .white.opacity(0.45))
                                        .frame(width: itemWidth - 8)
                                        .lineLimit(1)
                                        .multilineTextAlignment(.center)
                                        .opacity(nameLine2 != nil ? 1 : 0)
                                }
                                .frame(width: itemWidth - 8, height: 30)
                            }

                            // Progress bar or checklist checkmark (only for fundamental exercises)
                            if let fundEx = fundamentalExercise, let tierVal = tier {
                                if strengthTierResult.overallTier == .none {
                                    // Checklist mode: checkmark for exercises with data
                                    let hasData = strengthTierResult.exerciseTiers.first(where: { $0.exercise.id == exercise.id })?.e1rm != nil
                                    Image(systemName: hasData ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(hasData ? Color.appAccent : .white.opacity(0.2))
                                        .padding(.top, 2)
                                        .padding(.bottom, 12)
                                } else {
                                    let progress = tierProgress(for: fundEx)
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.white.opacity(0.1))
                                                .frame(height: 4)
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(tierVal.color)
                                                .frame(width: geo.size.width * (progress ?? 1.0), height: 4)
                                        }
                                    }
                                    .frame(height: 4)
                                    .padding(.horizontal, 8)
                                    .padding(.top, 4)
                                    .padding(.bottom, 10)
                                }
                            } else {
                                // Reserve less space since non-tier text uses 2-line frame
                                Spacer()
                                    .frame(height: 4)
                            }
                        }
                        .frame(width: itemWidth)
                        .padding(.vertical, 6)
                        .frame(minHeight: 84)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? highlightColor.opacity(0.1) : Color(white: 0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    isSelected ? highlightColor.opacity(0.6) : Color.white.opacity(0.08),
                                    lineWidth: isSelected ? 1.5 : 1
                                )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            hapticFeedback.impactOccurred()
                            let wasAccessoryMode = isAccessoryMode
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedLiftIndex = index
                                isAccessoryMode = false
                                selectedAccessoryId = nil
                            }
                            // If we were in accessory mode and selectedLiftIndex didn't change,
                            // onChange won't fire, so reload manually
                            if wasAccessoryMode {
                                loadDataForSelectedLift()
                            }
                        }
                        .onLongPressGesture {
                            hapticFeedback.impactOccurred()
                            hubDeepLinkExerciseId = exercise.id
                            hubSection = .exercises
                            showHub = true
                        }
                        .id(index)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(height: strengthTierResult.overallTier == .none ? 92 : 84)
    }

    // MARK: - Phase 2: Focused Lift Panel

    private var focusedLiftPanel: some View {
        let groupExercise = selectedGroupExercise
        let fundamentalIds = Set(fundamentals.map(\.id))
        let isFundamental = groupExercise != nil && fundamentalIds.contains(groupExercise!.id)
        let fundamentalExercise = isFundamental ? fundamentals.first(where: { $0.id == groupExercise!.id }) : nil

        let rawE1rm: Double = isAccessoryMode ? current1RM : (latestE1RMs[groupExercise?.id ?? UUID()] ?? 0)
        let e1rm: Double = pendingCalibrationSet != nil ? 0.0 : rawE1rm
        let tier = isAccessoryMode
            ? StrengthTier.novice
            : (isFundamental ? (strengthTierResult.exerciseTiers.first(where: { $0.exercise.id == groupExercise!.id })?.tier ?? .novice) : nil)
        let exerciseName = isAccessoryMode ? (selectedExercise?.name ?? "") : (groupExercise?.name ?? "")
        let exerciseIcon = isAccessoryMode ? (selectedExercise?.icon ?? "") : (groupExercise?.icon ?? "")

        let nextMin: Double? = (isAccessoryMode || !isFundamental) ? nil : StrengthTierData.nextTierMinimum(
            name: fundamentalExercise!.name,
            currentTier: tier!,
            bodyweight: bodyweight,
            sex: sex
        )
        let currentMin: Double = (isAccessoryMode || !isFundamental) ? 0 : StrengthTierData.currentTierMinimum(
            name: fundamentalExercise!.name,
            tier: tier!,
            bodyweight: bodyweight,
            sex: sex
        )

        let isNoneState = strengthTierResult.overallTier == .none && !isAccessoryMode && isFundamental

        return VStack(spacing: 8) {
            // Lift name + icon
            HStack(spacing: 8) {
                Image(exerciseIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(isAccessoryMode ? Color.appAccent : (isNoneState ? Color.appAccent : (e1rm > 0 ? (tier?.color ?? .white) : Color.appAccent)))

                Text(exerciseName)
                    .font(.bebasNeue(size: 24))
                    .foregroundStyle(.white)

                Spacer()

                if !isAccessoryMode, let tier {
                    if isNoneState {
                        Image(systemName: e1rm > 0 ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(e1rm > 0 ? Color.appAccent : .white.opacity(0.25))
                    } else {
                        Text(e1rm > 0 ? tier.title : "–\u{2009}–")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(e1rm > 0 ? tier.color : .white.opacity(0.3))
                    }
                }

                if e1rm > 0 {
                    Button {
                        hapticFeedback.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showE1RMPopup = true
                        }
                    } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Hero e1RM
            HStack(alignment: .center, spacing: e1rm > 0 ? 6 : 12) {
                Text(e1rm > 0 ? "\(Int(userProperties.preferredWeightUnit.fromLbs(e1rm)))" : "–\u{200A}–")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(e1rm > 0 ? .white : .white.opacity(0.3))
                VStack(alignment: .leading, spacing: 4) {
                    Text(userProperties.preferredWeightUnit.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("e1RM")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StrengthTier.elite.color)
                }
                Spacer()
            }

            // Tier progress bar (only for fundamentals)
            if !isAccessoryMode, let nextMinVal = nextMin {
                let range = nextMinVal - currentMin
                let progress = range > 0 ? min(max((e1rm - currentMin) / range, 0), 1) : 1
                let distance = max(0, nextMinVal - e1rm)

                VStack(spacing: 4) {
                    // 7-day e1RM gain indicator (fixed height to prevent layout shift)
                    HStack(spacing: 4) {
                        Spacer()
                        let exerciseId = isAccessoryMode ? selectedExercise?.id : groupExercise?.id
                        if let eid = exerciseId, let gain = e1rmGain30Day(for: eid) {
                            Text("+\(gain, specifier: "%.2f")")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                            Text("over 7D")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .frame(height: 12)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 8)

                            if e1rm > 0 && progress > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.appAccent)
                                    .frame(width: geo.size.width * progress, height: 8)
                            }
                        }
                    }
                    .frame(height: 8)

                    if e1rm > 0 {
                        HStack {
                            // Full-precision e1RM in user's preferred weight unit
                            let convertedE1rm = userProperties.preferredWeightUnit.fromLbs(e1rm)
                            Text(String(format: "%.2f \(userProperties.preferredWeightUnit.label)", convertedE1rm))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            if !isNoneState, let nextTier = tier?.next {
                                HStack(spacing: 0) {
                                    Text("\(userProperties.preferredWeightUnit.formatWeight2dp(distance)) \(userProperties.preferredWeightUnit.label) to ")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.5))
                                    Text(nextTier.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(nextTier.color)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, e1rm > 0 ? 0 : 6)
            } else if !isAccessoryMode && tier == .legend {
                HStack {
                    Spacer()
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(tier?.color ?? .white)
                }
            }

        }
        .padding(14)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Sticky Exercise Banner

    private var stickyExerciseBanner: some View {
        let groupExercise = selectedGroupExercise
        let fundamentalIds = Set(fundamentals.map(\.id))
        let isFundamental = groupExercise != nil && fundamentalIds.contains(groupExercise!.id)

        let rawE1rm: Double = isAccessoryMode ? current1RM : (latestE1RMs[groupExercise?.id ?? UUID()] ?? 0)
        let e1rm: Double = pendingCalibrationSet != nil ? 0.0 : rawE1rm
        let tier: StrengthTier? = isAccessoryMode
            ? .novice
            : (isFundamental ? (strengthTierResult.exerciseTiers.first(where: { $0.exercise.id == groupExercise!.id })?.tier ?? .novice) : nil)
        let exerciseName = isAccessoryMode ? (selectedExercise?.name ?? "") : (groupExercise?.name ?? "")
        let exerciseIcon = isAccessoryMode ? (selectedExercise?.icon ?? "") : (groupExercise?.icon ?? "")
        let isNoneState = strengthTierResult.overallTier == .none && !isAccessoryMode && isFundamental

        return HStack(spacing: 10) {
            Image(exerciseIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(isAccessoryMode ? Color.appAccent : (isNoneState ? Color.appAccent : (e1rm > 0 ? (tier?.color ?? .white) : Color.appAccent)))

            Text(exerciseName)
                .font(.bebasNeue(size: 20))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            if e1rm > 0 {
                Text("\(Int(userProperties.preferredWeightUnit.fromLbs(e1rm))) \(userProperties.preferredWeightUnit.label)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            if !isAccessoryMode, let tier {
                if isNoneState {
                    Image(systemName: e1rm > 0 ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(e1rm > 0 ? Color.appAccent : .white.opacity(0.25))
                } else {
                    Text(e1rm > 0 ? tier.title : "–\u{2009}–")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(e1rm > 0 ? tier.color : .white.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.ignoresSafeArea(.all, edges: .top))
        .overlay(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.6), location: 0.35),
                    .init(color: .black.opacity(0.2), location: 0.7),
                    .init(color: .black.opacity(0), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            .offset(y: 40)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Sets Widget

    // MARK: - Tier Journey Evaluation

    // One-shot tutorial popup: fires the first time this tab is evaluated
    // with sync complete and the strength tier unlocked. Flag is flipped
    // before presentation so an app kill mid-video still counts as "seen".
    private func evaluateLiftTutorialTrigger() {
        guard !hasSeenLiftTutorialAfterTierUnlock,
              userProperties.hasMetStrengthTierConditions else { return }
        hasSeenLiftTutorialAfterTierUnlock = true
        TutorialPresenter.shared.showLiftTutorial = true
    }

    private func evaluateTierJourney() {
        if userProperties.hasMetStrengthTierConditions { return }

        // Don't show journey if sync hasn't populated data yet for a returning user
        let syncComplete = syncService.initialSyncComplete
        let hasData = exercises.contains(where: { $0.currentE1RMLocalCache != nil })

        // Show tier journey intro for fresh users (no e1RM data at all)
        if !hasSeenTierIntro,
           strengthTierResult.overallTier == .none,
           strengthTierResult.exerciseTiers.allSatisfy({ $0.e1rm == nil }) {
            // Only show if sync is done OR user genuinely has no data
            if syncComplete || !hasData {
                tierJourneyMode = .intro
                showTierJourneyOverlay = true
            }
        }
        // Resume tier journey for users who haven't finished logging all 5 exercises
        else if hasSeenTierIntro,
                syncComplete,
                strengthTierResult.overallTier == .none,
                strengthTierResult.exerciseTiers.contains(where: { $0.e1rm == nil }) {
            if strengthTierResult.exerciseTiers.allSatisfy({ $0.e1rm == nil }) {
                tierJourneyMode = .intro
            } else {
                tierJourneyMode = .progress(justLoggedId: nil)
            }
            showTierJourneyOverlay = true
        }
    }

    private func intensityColor(for set: LiftSet) -> Color {
        // Use the e1RM that existed *before* this set was logged (same as LegacyCheckInView)
        let priorE1RM = estimated1RMsForExercise
            .filter { $0.createdAt < set.createdAt }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        var currentMax = priorE1RM?.value ?? 0

        let estimated = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)

        if set.weight == 0 { return .white }

        // Fallback: if no prior e1RM, use the e1RM created for this set (captures calibration)
        if currentMax == 0 {
            if let thisSetE1RM = estimated1RMsForExercise.first(where: { $0.setId == set.id }) {
                currentMax = thisSetE1RM.value
            }
        }

        let isPR = (estimated - currentMax) > 0.0001 && currentMax > 0
        if isPR { return .appAccent }

        let percent = currentMax > 0 ? estimated / currentMax : 0
        let bucket = TrendsCalculator.IntensityBucket.from(percent1RM: percent)
        switch bucket {
        case .pr: return .setNearMax // not a true PR — downgrade to Near Max
        case .nearMax: return .setNearMax
        case .hard: return .setHard
        case .moderate: return .setModerate
        case .easy: return .setEasy
        }
    }

    /// The *actual* effort a logged set represents (label + color), mirroring
    /// `intensityColor(for:)` so a set logged harder/easier than planned reads
    /// accurately in the vertical-rows variant.
    private func actualEffort(for set: LiftSet) -> (label: String, color: Color) {
        let priorE1RM = estimated1RMsForExercise
            .filter { $0.createdAt < set.createdAt }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        var currentMax = priorE1RM?.value ?? 0
        let estimated = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)

        if set.weight == 0 { return ("Logged", .white) }

        if currentMax == 0 {
            if let thisSetE1RM = estimated1RMsForExercise.first(where: { $0.setId == set.id }) {
                currentMax = thisSetE1RM.value
            }
        }

        let isPR = (estimated - currentMax) > 0.0001 && currentMax > 0
        if isPR { return ("Progress", .appAccent) }

        let percent = currentMax > 0 ? estimated / currentMax : 0
        switch TrendsCalculator.IntensityBucket.from(percent1RM: percent) {
        case .pr, .nearMax: return ("Near Max", .setNearMax)
        case .hard: return ("Hard", .setHard)
        case .moderate: return ("Moderate", .setModerate)
        case .easy: return ("Easy", .setEasy)
        }
    }

    // MARK: - Tall set-plan tiles variant (FEATURE FLAG: setsWidgetStyle == .tallTiles)
    // Isolated, reversible reimagining of the tile row: taller tiles that hold
    // the effort label inside a dotted outline when unpopulated, and a colored
    // weight×reps inside a filled tile when populated. Same behavior/handlers as
    // the original row — visuals only.

    private let tallTileHeight: CGFloat = 60
    private let tallTileCorner: CGFloat = 10

    private func tallPopulatedTileVisual(set: LiftSet, showText: Bool) -> some View {
        let color = intensityColor(for: set)
        return VStack(spacing: 1) {
            if showText {
                Text("\(Int(userProperties.preferredWeightUnit.fromLbs(set.weight)))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("× \(set.reps)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, minHeight: tallTileHeight)
        .background(RoundedRectangle(cornerRadius: tallTileCorner).fill(color.opacity(0.16)))
        .overlay(
            RoundedRectangle(cornerRadius: tallTileCorner)
                .strokeBorder(color.opacity(0.55), lineWidth: 1)
        )
    }

    private func tallUnpopulatedTileVisual(effortKey: String, showText: Bool) -> some View {
        let color = effortColor(for: effortKey)
        return VStack(spacing: 1) {
            if showText {
                Text(effortLabel(for: effortKey))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: tallTileHeight)
        .background(RoundedRectangle(cornerRadius: tallTileCorner).fill(color.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: tallTileCorner)
                .strokeBorder(color.opacity(0.6),
                              style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        )
    }

    @ViewBuilder
    private func tallSetTileRow(sortedSets: [LiftSet]) -> some View {
        if isViewingToday, let plan = activeSetPlan {
            let sequence = plan.effortSequence
            let totalSlots = max(sequence.count, sortedSets.count)

            HStack(spacing: 6) {
                ForEach(0..<totalSlots, id: \.self) { index in
                    if index < sortedSets.count {
                        let set = sortedSets[index]
                        tallPopulatedTileVisual(set: set, showText: totalSlots <= 8)
                            .scaleEffect(tappedTileIndex == index ? 0.9 : 1.0)
                            .animation(.easeOut(duration: 0.15), value: tappedTileIndex)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                weight = set.weight
                                reps = set.reps
                                triggerLogSetFlash()
                                tappedTileIndex = index
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    tappedTileIndex = nil
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteSet(set)
                                } label: {
                                    Label("Delete Set", systemImage: "trash")
                                }
                            }
                    } else {
                        let effortKey = index < sequence.count ? sequence[index] : ""
                        tallUnpopulatedTileVisual(effortKey: effortKey,
                                                  showText: totalSlots <= 8 && index < sequence.count)
                            .scaleEffect(tappedTileIndex == index ? 0.9 : 1.0)
                            .animation(.easeOut(duration: 0.15), value: tappedTileIndex)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard index < sequence.count else { return }
                                let effort = sequence[index]
                                switch effort {
                                case "easy":
                                    if let s = effortShortcuts {
                                        applyPreset(s.easy, atIndex: index, effort: "easy")
                                    } else {
                                        showPresetUnavailableHint(forEffort: "Easy")
                                    }
                                case "moderate":
                                    if let s = effortShortcuts {
                                        applyPreset(s.moderate, atIndex: index, effort: "moderate")
                                    } else {
                                        showPresetUnavailableHint(forEffort: "Moderate")
                                    }
                                case "hard":
                                    if let s = effortShortcuts {
                                        applyPreset(s.hard, atIndex: index, effort: "hard")
                                    } else {
                                        showPresetUnavailableHint(forEffort: "Hard")
                                    }
                                case "redline":
                                    if let pick = nearMaxShortcut {
                                        applyPreset(pick, atIndex: index, effort: "redline")
                                    } else {
                                        showPresetUnavailableHint(forEffort: "Near Max")
                                    }
                                case "pr":
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    tappedTileIndex = index
                                    withAnimation {
                                        // Land the sets-widget bottom / progress-options top
                                        // at ~16% down the screen, i.e. just below the compact
                                        // top bar. y here maps directly to screen position
                                        // because the anchor view is zero-height.
                                        scrollProxy?.scrollTo("progressTop", anchor: UnitPoint(x: 0.5, y: 0.26))
                                    }
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        progressOptionsHighlighted = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            progressOptionsHighlighted = false
                                        }
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        if tappedTileIndex == index {
                                            tappedTileIndex = nil
                                        }
                                    }
                                default:
                                    break
                                }
                            }
                    }
                }
            }
        } else if sortedSets.isEmpty {
            Text("No sets logged")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 6) {
                ForEach(Array(sortedSets.enumerated()), id: \.element.id) { idx, set in
                    let tileId = idx + 1000
                    tallPopulatedTileVisual(set: set, showText: sortedSets.count <= 7)
                        .scaleEffect(tappedTileIndex == tileId ? 0.9 : 1.0)
                        .animation(.easeOut(duration: 0.15), value: tappedTileIndex)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            weight = set.weight
                            reps = set.reps
                            triggerLogSetFlash()
                            tappedTileIndex = tileId
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                tappedTileIndex = nil
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteSet(set)
                            } label: {
                                Label("Delete Set", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    // MARK: - Vertical set-plan rows variant (FEATURE FLAG: setsWidgetStyle == .verticalRows)
    // One row per set in the plan: "SET n · <effort>". Unpopulated rows invite a
    // tap (dotted outline + "Tap to load"); populated rows show the logged weight×
    // reps with a check. Same tap/preset/delete behavior as the original row.

    // Header: prev/next date chevrons flanking a centered stack of "Sets Today"
    // over the set-plan chip — one cohesive unit above the set rows.
    private var verticalDateAndPlanHeader: some View {
        HStack {
            Button {
                if let prev = previousSessionDate { viewingDate = prev }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(previousSessionDate != nil ? .white.opacity(0.6) : .white.opacity(0.2))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
            }
            .disabled(previousSessionDate == nil)

            Spacer()

            // "Sets Today" and the plan chip stacked as one cohesive unit, flanked
            // by the date chevrons.
            VStack(spacing: 8) {
                Button {
                    if !isViewingToday { viewingDate = actualToday }
                } label: {
                    HStack(spacing: 6) {
                        Text(isViewingToday ? "Today's Sets" : viewingDate.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isViewingToday ? .white : .white.opacity(0.6))
                        if !isViewingToday {
                            Image(systemName: "arrow.uturn.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!isViewingToday)

                verticalPlanSelector
            }

            Spacer()

            Button {
                if let next = nextSessionDate { viewingDate = next }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(nextSessionDate != nil ? .white.opacity(0.6) : .white.opacity(0.2))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
            }
            .disabled(nextSessionDate == nil)
        }
    }

    // A small, self-sizing bordered chip (catalog icon + plan name + chevron) that
    // sits just under the Today row as a group — distinct from the full-width rows.
    @ViewBuilder
    private var verticalPlanSelector: some View {
        if isViewingToday {
            Button {
                hubSection = .setPlans
                showHub = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.clipboard.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.appAccent.opacity(0.8))
                    Text(activeSetPlan?.name ?? "Freestyle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "list.clipboard.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.appAccent.opacity(0.4))
                Text(activeSetPlan?.name ?? "Freestyle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appAccent.opacity(0.5))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
    }

    /// Suggested (weight, reps) for a planned effort — the same preset a tap would
    /// apply — used to preview "Suggested 95 lbs × 8" on unperformed rows.
    private func suggestedPreset(for effortKey: String) -> (weight: Double, reps: Int)? {
        switch effortKey {
        case "easy": return effortShortcuts?.easy
        case "moderate": return effortShortcuts?.moderate
        case "hard": return effortShortcuts?.hard
        case "redline": return nearMaxShortcut
        default: return nil
        }
    }

    /// `isBaseline` renders the calibration set — the first weighted set of an
    /// exercise (`LiftSet.isBaselineSet`). It sits OUTSIDE the set plan, so it is
    /// never numbered, offers no preset to load, and before it exists it is the
    /// only row in the section.
    private func verticalPlannedRow(setNumber: Int, effortKey: String, set: LiftSet?,
                                    isNext: Bool = false, isBaseline: Bool = false) -> some View {
        let unit = userProperties.preferredWeightUnit
        let plannedColor = effortColor(for: effortKey)
        // Populated rows reflect what was ACTUALLY logged; empty rows show the plan.
        let display: (label: String, color: Color) = set != nil
            ? actualEffort(for: set!)
            : (effortLabel(for: effortKey), plannedColor)
        // A pending baseline carries no effort key, so `display.color` would fall
        // through to the faint default. Use the accent instead — it's the one
        // actionable row on screen at that moment.
        let isPendingBaseline = (isBaseline && set == nil)
        let color = isPendingBaseline ? Color.appAccent : display.color
        let isProgress = (effortKey == "pr")
        let suggestion = set == nil ? suggestedPreset(for: effortKey) : nil
        // Only the NEXT, unperformed set gets the second (suggested) line; every
        // other row is a single, thinner line. A pending baseline always takes the
        // two-line form — its instructional subtext is the whole point of the row.
        let isTwoRow = (set == nil && (isNext || isBaseline))
        // Derived, not stored: true while the log-set widget holds exactly this
        // row's suggested preset. Tapping loads the preset (→ "Loaded"); nudging
        // weight or reps afterwards makes them diverge and flips it back to
        // "Tap to load" on the next render, with no state to keep in sync.
        // Weight is compared with a tolerance since it round-trips as a Double.
        // Scoped to the NEXT row: sibling slots often share an effort (two
        // "Moderate" sets suggest the same preset), so without this every matching
        // row would light up at once.
        let isLoaded: Bool = {
            // `weight`/`reps` carry real values even while the log-set widget is
            // showing its empty placeholder — it renders from weightIsSet/repsIsSet,
            // not from the numbers. Match what's on screen, or a blank widget would
            // claim "Loaded" on arrival just because the backing state happens to
            // equal the suggestion.
            guard weightIsSet, repsIsSet else { return false }
            guard isNext, let suggestion else { return false }
            return abs(weight - suggestion.weight) < 0.0001 && reps == suggestion.reps
        }()

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: isTwoRow ? 34 : 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(isBaseline ? "BASELINE SET" : "SET \(setNumber)")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(isBaseline ? 0.75 : 0.5))
                    // A pending baseline has no effort yet — the user picks it in
                    // the "How did that feel?" prompt after logging. Once logged it
                    // shows its effort like any other populated row.
                    if !isPendingBaseline {
                        Text("·")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                        Text(display.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(color)
                    }
                }

                if isTwoRow {
                    if isPendingBaseline {
                        Text("Log your first set below to get started.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    } else if let suggestion = suggestion {
                        Text("Suggested \(Int(unit.fromLbs(suggestion.weight))) \(unit.label) × \(suggestion.reps)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    } else if isProgress {
                        Text("Pick a set to grow your e1RM")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }

            Spacer()

            // Right content, vertically centered — centers over both lines in the
            // two-row NEXT state, and over the single line otherwise.
            if let set = set {
                HStack(spacing: 7) {
                    Text("\(Int(unit.fromLbs(set.weight))) \(unit.label) × \(set.reps)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(color)
                }
            } else if isPendingBaseline {
                // No load affordance: the baseline is user-driven by definition —
                // there is no e1RM yet, so no preset exists to suggest or load.
                EmptyView()
            } else if isProgress {
                HStack(spacing: 4) {
                    if isNext {
                        Text("See options")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(plannedColor.opacity(0.7))
                }
            } else {
                HStack(spacing: 4) {
                    if isNext {
                        Text(isLoaded ? "Loaded" : "Tap to load")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(isLoaded ? 0.55 : 0.4))
                    }
                    Image(systemName: isLoaded ? "checkmark.circle" : "arrow.down.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(plannedColor.opacity(isLoaded ? 0.9 : 0.6))
                }
            }
        }
        .padding(.vertical, isTwoRow ? 10 : 7)
        .padding(.horizontal, 12)
        // Non-NEXT rows are pinned to an EXACT height (min == max) so the populated
        // and unpopulated states always match. A bare minHeight isn't enough: the
        // populated row carries taller right-side content (weight×reps text + a 15pt
        // checkmark) than the unpopulated row's lone arrow glyph, so it would grow
        // past the floor and read as a taller row. NEXT keeps a floor, not a cap —
        // it's deliberately taller and its second line must be free to size itself.
        .frame(maxWidth: .infinity,
               minHeight: isTwoRow ? 50 : 36,
               maxHeight: isTwoRow ? nil : 36)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(set != nil ? color.opacity(0.12)
                      : (isNext ? Color.appAccent.opacity(0.08) : Color.white.opacity(0.03)))
        )
        .overlay(
            Group {
                if set != nil {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(color.opacity(0.4), lineWidth: 1)
                } else if isNext {
                    // The next set to perform — always amber, solid, to draw the eye.
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.appAccent.opacity(0.85), lineWidth: 1.6)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(plannedColor.opacity(0.45),
                                      style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                }
            }
        )
        // NEXT tab — squared-off, sitting flush on the row's top border.
        .overlay(alignment: .topLeading) {
            if isNext {
                Text("NEXT")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.appAccent))
                    .offset(x: 12, y: -9)
            }
        }
    }

    /// Sentinel tap-animation id for the baseline row. Plan slots key on their
    /// index and past-day rows on `idx + 1000`, so a negative value can't collide
    /// with either and make two rows animate together.
    private var baselineTileIndex: Int { -1 }

    /// The un-performed calibration row — the only item shown for an exercise that
    /// has never been trained. It loads nothing (there is no e1RM yet, so no preset
    /// exists); tapping just points at the log-set bar, which is exactly what the
    /// superseded `setsWidgetEmptyState` button did.
    private var pendingBaselineRow: some View {
        verticalPlannedRow(setNumber: 0, effortKey: "", set: nil, isNext: true, isBaseline: true)
            .scaleEffect(tappedTileIndex == baselineTileIndex ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: tappedTileIndex)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticFeedback.impactOccurred()
                triggerLogSetFlash(markFieldsSet: false)
                tappedTileIndex = baselineTileIndex
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    tappedTileIndex = nil
                }
            }
    }

    /// A performed calibration set. Identical tap-to-load and delete affordances to
    /// any other populated row — only the label and its exclusion from the plan's
    /// numbering differ.
    private func loggedBaselineRow(_ set: LiftSet) -> some View {
        verticalPlannedRow(setNumber: 0, effortKey: "", set: set, isBaseline: true)
            .scaleEffect(tappedTileIndex == baselineTileIndex ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: tappedTileIndex)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticFeedback.impactOccurred()
                AmplitudeService.shared.track(.setPresetLoaded(
                    effort: effortToken(label: actualEffort(for: set).label), source: "logged_set"
                ))
                weight = set.weight
                reps = set.reps
                triggerLogSetFlash()
                tappedTileIndex = baselineTileIndex
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    tappedTileIndex = nil
                }
            }
            .contextMenu {
                Button(role: .destructive) {
                    deleteSet(set)
                } label: {
                    Label("Delete Set", systemImage: "trash")
                }
            }
    }

    @ViewBuilder
    private func verticalSetRows(sortedSets: [LiftSet]) -> some View {
        // The baseline is calibration, not a planned set, so it never occupies a
        // plan slot — the plan runs its full sequence alongside it. Everything
        // below iterates `planSets`, never `sortedSets`, or the baseline would
        // render twice: once as its own row and again as SET 1.
        let baselineSet = sortedSets.first(where: { $0.isBaselineSet })
        let planSets = sortedSets.filter { !$0.isBaselineSet }
        // Matches the gate the retired `setsWidgetEmptyState` used. Deliberately
        // keyed on "has this lift ever been trained" rather than "has an e1RM":
        // an exercise logged only at bodyweight never calibrates (isFirstWeightedSet
        // requires weight > 0), and would otherwise show a pending baseline forever.
        let hasE1RM = selectedExercise?.currentE1RMLocalCache != nil

        if isViewingToday && setsForExercise.isEmpty && !hasE1RM {
            pendingBaselineRow
        } else if isViewingToday, let plan = activeSetPlan {
            let sequence = plan.effortSequence
            let totalSlots = max(sequence.count, planSets.count)

            VStack(spacing: 10) {
                if let baselineSet {
                    loggedBaselineRow(baselineSet)
                }
                ForEach(0..<totalSlots, id: \.self) { index in
                    if index < planSets.count {
                        let set = planSets[index]
                        let effortKey = index < sequence.count ? sequence[index] : ""
                        verticalPlannedRow(setNumber: index + 1, effortKey: effortKey, set: set)
                            .scaleEffect(tappedTileIndex == index ? 0.97 : 1.0)
                            .animation(.easeOut(duration: 0.15), value: tappedTileIndex)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                AmplitudeService.shared.track(.setPresetLoaded(
                                    effort: effortToken(label: actualEffort(for: set).label),
                                    source: "logged_set"
                                ))
                                weight = set.weight
                                reps = set.reps
                                triggerLogSetFlash()
                                tappedTileIndex = index
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    tappedTileIndex = nil
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteSet(set)
                                } label: {
                                    Label("Delete Set", systemImage: "trash")
                                }
                            }
                    } else {
                        let effortKey = index < sequence.count ? sequence[index] : ""
                        verticalPlannedRow(setNumber: index + 1, effortKey: effortKey, set: nil,
                                           isNext: index == planSets.count)
                            // Extra headroom for the NEXT tab, but only when it's not the
                            // topmost row — a baseline row above it counts as one.
                            .padding(.top, (index == planSets.count && (index > 0 || baselineSet != nil)) ? 5 : 0)
                            .scaleEffect(tappedTileIndex == index ? 0.97 : 1.0)
                            .animation(.easeOut(duration: 0.15), value: tappedTileIndex)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard index < sequence.count else { return }
                                let effort = sequence[index]
                                switch effort {
                                case "easy":
                                    if let s = effortShortcuts {
                                        applyPreset(s.easy, atIndex: index, effort: "easy")
                                    } else {
                                        showPresetUnavailableHint(forEffort: "Easy")
                                    }
                                case "moderate":
                                    if let s = effortShortcuts {
                                        applyPreset(s.moderate, atIndex: index, effort: "moderate")
                                    } else {
                                        showPresetUnavailableHint(forEffort: "Moderate")
                                    }
                                case "hard":
                                    if let s = effortShortcuts {
                                        applyPreset(s.hard, atIndex: index, effort: "hard")
                                    } else {
                                        showPresetUnavailableHint(forEffort: "Hard")
                                    }
                                case "redline":
                                    if let pick = nearMaxShortcut {
                                        applyPreset(pick, atIndex: index, effort: "redline")
                                    } else {
                                        showPresetUnavailableHint(forEffort: "Near Max")
                                    }
                                case "pr":
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    tappedTileIndex = index
                                    withAnimation {
                                        // Land the sets-widget bottom / progress-options top
                                        // at ~16% down the screen, i.e. just below the compact
                                        // top bar. y here maps directly to screen position
                                        // because the anchor view is zero-height.
                                        scrollProxy?.scrollTo("progressTop", anchor: UnitPoint(x: 0.5, y: 0.26))
                                    }
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        progressOptionsHighlighted = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            progressOptionsHighlighted = false
                                        }
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        if tappedTileIndex == index {
                                            tappedTileIndex = nil
                                        }
                                    }
                                default:
                                    break
                                }
                            }
                    }
                }
            }
        } else if sortedSets.isEmpty {
            Text("No sets logged")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 10) {
                // Being the baseline is a permanent property of the set, so it keeps
                // its label on past days too — and stays out of the numbering, which
                // is why the remaining sets renumber from 1 rather than leaving a gap.
                if let baselineSet {
                    loggedBaselineRow(baselineSet)
                }
                ForEach(Array(planSets.enumerated()), id: \.element.id) { idx, set in
                    let tileId = idx + 1000
                    // Same row builder as today's populated rows, so past days (and
                    // Freestyle) match the plan view exactly — height, effort label,
                    // and white weight×reps text. `effortKey: ""` is the same
                    // convention used above for sets logged beyond the plan sequence:
                    // a populated row derives its label/color from `actualEffort`, so
                    // the planned key is unused once `set != nil`.
                    verticalPlannedRow(setNumber: idx + 1, effortKey: "", set: set)
                        .scaleEffect(tappedTileIndex == tileId ? 0.97 : 1.0)
                        .animation(.easeOut(duration: 0.15), value: tappedTileIndex)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            AmplitudeService.shared.track(.setPresetLoaded(
                                effort: effortToken(label: actualEffort(for: set).label),
                                source: "logged_set"
                            ))
                            weight = set.weight
                            reps = set.reps
                            triggerLogSetFlash()
                            tappedTileIndex = tileId
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                tappedTileIndex = nil
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteSet(set)
                            } label: {
                                Label("Delete Set", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    /// Replica of the NEXT badge from `verticalPlannedRow`, so the explainer points
    /// at something the reader can visually match on the row above. Same metrics as
    /// the real one.
    private var nextBadgeInline: some View {
        Text("NEXT")
            .font(.system(size: 8, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.appAccent))
    }

    /// Rasterize the badge so it can be embedded in a `Text` run. Rendered at the
    /// display scale so it stays crisp; returns nil if rendering fails, in which
    /// case the explainer degrades to a plain amber "NEXT".
    @MainActor
    private func renderNextBadge() -> Image? {
        let renderer = ImageRenderer(content: nextBadgeInline)
        renderer.scale = displayScale
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }

    /// Shared so the rendered and fallback branches can't drift apart.
    private var nextBadgeSentence: String {
        " is the set to do now. Tap it to load its suggested weight and reps, then adjust as needed while staying within the desired effort level."
    }

    private var setsWidget: some View {
        VStack(spacing: 8) {
            // Header — outside the card background. The vertical-rows variant carries
            // its own "Sets Today" heading inside the card, so drop the redundant label.
            if setsWidgetStyle != .verticalRows {
                HStack {
                    Text("SETS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1)
                    Spacer()
                }
                .padding(.leading, 4)
            }

            setsWidgetCard
        }
    }

    @ViewBuilder
    private var setsWidgetCard: some View {
        // The untrained-exercise state is no longer a whole-widget takeover: it now
        // renders inside the rows section as a single pending BASELINE SET row (see
        // `verticalSetRows`), which keeps the date header and plan chip on screen.
        setsWidgetContent
    }

    /// SUPERSEDED by the pending baseline row in `verticalSetRows`, which replaced
    /// this whole-widget empty state. Retained deliberately in case we want to bring
    /// it back or reuse its copy; nothing references it. Its tap behaviour (flash the
    /// log-set bar without marking the fields set) now lives on `pendingBaselineRow`.
    private var setsWidgetEmptyState: some View {
        Button {
            triggerLogSetFlash(markFieldsSet: false)
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.appAccent.opacity(0.5))

                Text("Log your first set below")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Text("Your set history and set plans will appear here")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 14)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.appAccent.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    private var setsWidgetContent: some View {
        VStack(spacing: 8) {
            // Date navigation with "Next: effort" hint
            if setsWidgetStyle == .verticalRows {
                verticalDateAndPlanHeader
            } else {
            HStack {
                Button {
                    if let prev = previousSessionDate {
                        viewingDate = prev
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(previousSessionDate != nil ? .white.opacity(0.6) : .white.opacity(0.2))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .disabled(previousSessionDate == nil)

                Spacer()

                VStack(spacing: 2) {
                    // Date — tap to return to today
                    Button {
                        if !isViewingToday {
                            viewingDate = actualToday
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(isViewingToday ? "Today" : viewingDate.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(isViewingToday ? .white : .white.opacity(0.6))
                            if !isViewingToday {
                                Image(systemName: "arrow.uturn.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!isViewingToday)

                    // Plan name — tap to open hub (only interactive on today)
                    if isViewingToday {
                        if setsWidgetStyle != .original {
                            // Variant: pill-styled selector so it's obviously tappable.
                            Button {
                                hubSection = .setPlans
                                showHub = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text(activeSetPlan?.name ?? "Freestyle")
                                        .font(.system(size: 11, weight: .semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .foregroundStyle(Color.appAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.appAccent.opacity(0.12)))
                                .overlay(Capsule().strokeBorder(Color.appAccent.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        } else {
                        Button {
                            hubSection = .setPlans
                            showHub = true
                        } label: {
                            HStack(spacing: 3) {
                                Text(activeSetPlan?.name ?? "Freestyle")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.appAccent)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundStyle(Color.appAccent.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                        }
                    } else {
                        Text(activeSetPlan?.name ?? "Freestyle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.appAccent.opacity(0.5))
                    }
                }
                .frame(minHeight: 30)

                Spacer()

                Button {
                    if let next = nextSessionDate {
                        viewingDate = next
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(nextSessionDate != nil ? .white.opacity(0.6) : .white.opacity(0.2))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .disabled(nextSessionDate == nil)
            }
            }

            // Set bars — fixed height region so widget doesn't shift across states
            let sortedSets = todaysSets.sorted(by: { $0.createdAt < $1.createdAt })

            switch setsWidgetStyle {
            case .verticalRows:
                verticalSetRows(sortedSets: sortedSets)
                    .padding(.top, 6)
            case .tallTiles:
                tallSetTileRow(sortedSets: sortedSets)
                    .frame(minHeight: 64, alignment: .center)
            case .original:
            Group {
                if isViewingToday, let plan = activeSetPlan {
                    // Today with active plan: slots match plan sequence width
                    let sequence = plan.effortSequence
                    let totalSlots = max(sequence.count, sortedSets.count)

                    HStack(spacing: 3) {
                        ForEach(0..<totalSlots, id: \.self) { index in
                            if index < sortedSets.count {
                                let set = sortedSets[index]
                                let color = intensityColor(for: set)
                                VStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(color)
                                        .frame(height: 4)

                                    if totalSlots <= 8 {
                                        VStack(spacing: 0) {
                                            Text("\(Int(userProperties.preferredWeightUnit.fromLbs(set.weight)))")
                                                .font(.system(size: 8, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.7))
                                            Text("x\(set.reps)")
                                                .font(.system(size: 8, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                    }
                                }
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
                                .scaleEffect(tappedTileIndex == index ? 0.85 : 1.0)
                                .animation(.easeOut(duration: 0.15), value: tappedTileIndex)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    weight = set.weight
                                    reps = set.reps
                                    triggerLogSetFlash()
                                    tappedTileIndex = index
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        tappedTileIndex = nil
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteSet(set)
                                    } label: {
                                        Label("Delete Set", systemImage: "trash")
                                    }
                                }
                            } else {
                                VStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.1))
                                        .frame(height: 4)

                                    if totalSlots <= 8, index < sequence.count {
                                        Text(shortEffortLabel(for: sequence[index]))
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundStyle(effortColor(for: sequence[index]))
                                    }
                                }
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
                                .scaleEffect(tappedTileIndex == index ? 0.85 : 1.0)
                                .animation(.easeOut(duration: 0.15), value: tappedTileIndex)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard index < sequence.count else { return }
                                    let effort = sequence[index]
                                    switch effort {
                                    case "easy":
                                        if let s = effortShortcuts {
                                            applyPreset(s.easy, atIndex: index, effort: "easy")
                                        } else {
                                            showPresetUnavailableHint(forEffort: "Easy")
                                        }
                                    case "moderate":
                                        if let s = effortShortcuts {
                                            applyPreset(s.moderate, atIndex: index, effort: "moderate")
                                        } else {
                                            showPresetUnavailableHint(forEffort: "Moderate")
                                        }
                                    case "hard":
                                        if let s = effortShortcuts {
                                            applyPreset(s.hard, atIndex: index, effort: "hard")
                                        } else {
                                            showPresetUnavailableHint(forEffort: "Hard")
                                        }
                                    case "redline":
                                        if let pick = nearMaxShortcut {
                                            applyPreset(pick, atIndex: index, effort: "redline")
                                        } else {
                                            showPresetUnavailableHint(forEffort: "Near Max")
                                        }
                                    case "pr":
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        tappedTileIndex = index
                                        withAnimation {
                                            scrollProxy?.scrollTo("setsWidget", anchor: .top)
                                        }
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            progressOptionsHighlighted = true
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            withAnimation(.easeInOut(duration: 0.5)) {
                                                progressOptionsHighlighted = false
                                            }
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                            if tappedTileIndex == index {
                                                tappedTileIndex = nil
                                            }
                                        }
                                    default:
                                        break
                                    }
                                }
                            }
                        }
                    }
                } else if sortedSets.isEmpty {
                    Text("No sets logged")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                } else {
                    // Past days or no plan: just show logged sets
                    HStack(spacing: 3) {
                        ForEach(Array(sortedSets.enumerated()), id: \.element.id) { idx, set in
                            let color = intensityColor(for: set)
                            let tileId = idx + 1000
                            VStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color)
                                    .frame(height: 4)

                                if sortedSets.count <= 7 {
                                    VStack(spacing: 0) {
                                        Text("\(Int(userProperties.preferredWeightUnit.fromLbs(set.weight)))")
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.7))
                                        Text("x\(set.reps)")
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }
                            }
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
                            .scaleEffect(tappedTileIndex == tileId ? 0.85 : 1.0)
                            .animation(.easeOut(duration: 0.15), value: tappedTileIndex)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                weight = set.weight
                                reps = set.reps
                                triggerLogSetFlash()
                                tappedTileIndex = tileId
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    tappedTileIndex = nil
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteSet(set)
                                } label: {
                                    Label("Delete Set", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 44, alignment: .center)
            }

            // Faint divider so the sets read as a finite list, distinct from the
            // ranges-expansion chevron below (vertical-rows variant only).
            if setsWidgetStyle == .verticalRows {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }

            // Disclosure toggle for the inline explainer + effort ranges.
            // Deliberately LABELLED: a bare chevron at the foot of a card reads as
            // "there's more to scroll", not "tap to learn what this widget is". The
            // chevron survives only as a small trailing rotation indicator, which is
            // the standard disclosure idiom — the label is what carries the meaning.
            Button {
                hapticFeedback.impactOccurred()
                AmplitudeService.shared.track(
                    .setsHowItWorksToggled(isExpanded: !isSetsRangesExpanded)
                )
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSetsRangesExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isSetsRangesExpanded ? "Hide" : "How this works")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(isSetsRangesExpanded ? 180 : 0))
                        .offset(y: setsRangesChevronBob ? 2 : 0)
                }
                .foregroundStyle(Color.appAccent.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .padding(.bottom, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSetsRangesExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The set sequence above serves as a guide based on your selected set plan.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)

                        // The badge is an image inside the Text run, so the sentence
                        // wraps underneath it as a normal paragraph rather than
                        // hanging to its right.
                        Group {
                            if let badge = nextBadgeRendered {
                                Text(badge).baselineOffset(-2) + Text(nextBadgeSentence)
                            } else {
                                Text("NEXT")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundColor(.appAccent)
                                + Text(nextBadgeSentence)
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)

                        Text("The categories below show what percent of your e1RM each effort level covers.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.leading)
                    .onAppear {
                        // Rasterize once, the first time the explainer is opened.
                        if nextBadgeRendered == nil {
                            nextBadgeRendered = renderNextBadge()
                        }
                    }

                    SetsEffortRangesCard()

                    // Gateway to the full Sets Guide — centered pill at the
                    // foot of the expansion. Replaces the top-right info icon
                    // we removed.
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            hapticFeedback.impactOccurred()
                            AmplitudeService.shared.track(.setsGuideOpened)
                            showSetsInfoSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Open the full Sets Guide")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(Color.appAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.appAccent.opacity(0.12), in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.appAccent.opacity(0.32), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 6)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .onAppear {
            guard !hasBobbedChevron else { return }
            hasBobbedChevron = true
            // Five down-and-back bobs to draw initial attention, then settle
            // at rest (offset 0). Explicit toggle loop instead of
            // repeatCount(autoreverses:) so the final visual state is
            // guaranteed to match the underlying state value (no SwiftUI
            // snap-back when the animation completes).
            Task { @MainActor in
                for _ in 0..<5 {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        setsRangesChevronBob = true
                    }
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation(.easeInOut(duration: 0.45)) {
                        setsRangesChevronBob = false
                    }
                    try? await Task.sleep(for: .milliseconds(450))
                }
            }
        }
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Phase 3: e1RM Progress Options

    private var progressOptionsWidget: some View {
        VStack(spacing: 8) {
            // Header — outside the card. Hidden in the vertical-rows variant, matching
            // the hidden "SETS" label above the sets widget.
            if setsWidgetStyle != .verticalRows {
                HStack {
                    Text("PROGRESS OPTIONS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1)

                    Spacer()
                }
                .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                // e1RM Progress Options header with expand button
                HStack {
                    Text("e1RM Progress Options")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(current1RM > 0 ? .white : .white.opacity(0.4))

                    Spacer()

                    if current1RM > 0, let ex = selectedExercise {
                        let inc = ex.effectiveWeightIncrement
                        let displayInc = userProperties.preferredWeightUnit.fromLbs(inc)
                        let incStr = displayInc.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(displayInc))" : String(format: "%.1f", displayInc)
                        Text("±\(incStr) \(userProperties.preferredWeightUnit.label) · \(userProperties.progressMinReps)-\(userProperties.progressMaxReps) reps")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    Button {
                        hapticFeedback.impactOccurred()
                        showExpandedProgressOptions = true
                    } label: {
                        ViewfinderPulse(size: 14, color: .white.opacity(0.5))
                            .frame(width: 30, height: 30)
                            .background(Color(white: 0.16))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 10)

                progressOptionsContent

                quickPickCards
            }
            .padding(14)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(progressOptionsHighlighted ? Color.yellow : Color.white.opacity(0.08), lineWidth: progressOptionsHighlighted ? 2 : 1)
            )
        }
        .sheet(isPresented: $showExpandedProgressOptions) {
            ExpandedProgressOptionsSheet(
                suggestions: filteredSuggestions,
                sortColumn: $sortColumn,
                sortAscending: $sortAscending,
                weightDelta: $weightDelta,
                availableWeightDeltas: availableWeightDeltas,
                minWeightDelta: minWeightDelta,
                maxWeightDelta: maxWeightDelta,
                minReps: Binding(
                    get: { userProperties.progressMinReps },
                    set: { userProperties.progressMinReps = $0 }
                ),
                maxReps: Binding(
                    get: { userProperties.progressMaxReps },
                    set: { userProperties.progressMaxReps = $0 }
                ),
                onRepRangeChanged: { scheduleRepRangeSync() },
                onSelect: { suggestion in
                    weight = suggestion.weight
                    reps = suggestion.reps
                    triggerLogSetFlash()
                },
                hasWeightDeltaChanges: hasWeightDeltaChanges,
                onSaveWeightDelta: { saveWeightDelta() },
                isBarbell: selectedExercise?.exerciseLoadType.isBarbell == true,
                barbellWeight: Binding(
                    get: { selectedExercise?.barbellWeight },
                    set: { selectedExercise?.barbellWeight = $0 }
                ),
                onSaveBarbellWeight: { saveBarbellWeight() },
                weightUnit: userProperties.preferredWeightUnit
            )
        }
    }

    @ViewBuilder
    private var progressOptionsContent: some View {
        if current1RM <= 0 || selectedExercise == nil {
            VStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.appAccent.opacity(0.5))

                Text(selectedExercise?.exerciseLoadType == .bodyweightPlusSingleLoad
                     ? "Log a weighted set to unlock suggestions"
                     : "Log a set to unlock suggestions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Text("Personalized weight and rep targets will appear here")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            let filtered = filteredSuggestions

            if filtered.isEmpty {
                HStack {
                    Text("No suggestions for current rep range")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                let sorted = sortedProgressSuggestions(filtered)

                VStack(spacing: 4) {
                    // Column headers
                    progressColumnHeaders
                        .padding(.bottom, 4)

                    // Option cards
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { _, suggestion in
                        Button {
                            hapticFeedback.impactOccurred()
                            weight = suggestion.weight
                            reps = suggestion.reps
                            triggerLogSetFlash()
                        } label: {
                            ProgressOptionCard(
                                suggestion: suggestion,
                                isSelected: weight == suggestion.weight && reps == suggestion.reps,
                                sortColumn: sortColumn,
                                columnHighlighted: columnHighlighted,
                                weightUnit: userProperties.preferredWeightUnit
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var progressColumnHeaders: some View {
        HStack(spacing: 0) {
            progressColumnButton(title: "WEIGHT", column: .weight)
            progressColumnButton(title: "REPS", column: .reps)
            progressColumnButton(title: "e1RM", column: .est1RM)
            progressColumnButton(title: "GAIN", column: .gain)
        }
        .padding(.horizontal, 12)
    }

    private func progressColumnButton(title: String, column: SortColumn) -> some View {
        Button {
            handleProgressColumnTap(column)
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(columnHighlighted && sortColumn == column ? Color.appAccent : Color.appLabel)
                    .animation(.easeInOut(duration: 0.15), value: columnHighlighted)
                if sortColumn == column || (column == .est1RM && sortColumn == .gain) || (column == .gain && sortColumn == .est1RM) {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.appLabel)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func sortedProgressSuggestions(_ suggestions: [OneRMCalculator.Suggestion]) -> [OneRMCalculator.Suggestion] {
        switch sortColumn {
        case .weight:
            return suggestions.sorted { sortAscending ? $0.weight < $1.weight : $0.weight > $1.weight }
        case .reps:
            return suggestions.sorted { sortAscending ? $0.reps < $1.reps : $0.reps > $1.reps }
        case .est1RM:
            return suggestions.sorted { sortAscending ? $0.projected1RM < $1.projected1RM : $0.projected1RM > $1.projected1RM }
        case .gain:
            return suggestions.sorted { sortAscending ? $0.delta < $1.delta : $0.delta > $1.delta }
        }
    }

    private func handleProgressColumnTap(_ column: SortColumn) {
        hapticFeedback.impactOccurred()

        if (sortColumn == column) ||
           (sortColumn == .est1RM && column == .gain) ||
           (sortColumn == .gain && column == .est1RM) {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }

        columnHighlighted = true
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                columnHighlighted = false
            }
        }
    }

    private func saveWeightDelta() {
        guard let exercise = selectedExercise else { return }
        exercise.weightIncrement = weightDelta
        try? modelContext.save()
        initialWeightDelta = weightDelta
        Task {
            await SyncService.shared.syncExercise(exercise)
        }
    }

    private func saveBarbellWeight() {
        guard let exercise = selectedExercise else { return }
        try? modelContext.save()
        Task {
            await SyncService.shared.syncExercise(exercise)
        }
    }

    private func scheduleRepRangeSync() {
        repRangeDebounceTask?.cancel()
        let min = userProperties.progressMinReps
        let max = userProperties.progressMaxReps
        try? modelContext.save()
        repRangeDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await SyncService.shared.updateProgressRepRange(
                minReps: min, maxReps: max
            )
        }
    }

    // MARK: - Hub helpers

    private func createExercise(name: String, loadType: ExerciseLoadType, movementType: ExerciseMovementType, icon: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ex = Exercise(name: trimmed, isCustom: true, loadType: loadType, movementType: movementType, icon: icon)
        modelContext.insert(ex)
        AmplitudeService.shared.track(.exerciseCreated(loadType: ex.loadType, movementType: ex.movementType, isCustom: ex.isCustom))
        hubSelectedExerciseId = ex.id
        Task { await SyncService.shared.syncExercise(ex) }
    }

    private func saveExercise(_ exercise: Exercise, name: String, movementType: ExerciseMovementType, icon: String, notes: String?, barbellWeight: Double?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if exercise.isBuiltIn {
            exercise.notes = notes
        } else {
            exercise.name = trimmed
            exercise.icon = icon
            exercise.exerciseMovementType = movementType
            exercise.notes = notes
        }
        exercise.barbellWeight = barbellWeight
        try? modelContext.save()
        Task { await SyncService.shared.syncExercise(exercise) }
    }

    private func deleteExercise(_ exercise: Exercise) {
        guard !exercise.isBuiltIn else { return }
        let exerciseId = exercise.id
        let setsDescriptor = FetchDescriptor<LiftSet>(
            predicate: #Predicate { $0.exercise?.id == exerciseId }
        )
        let setsToDelete = (try? modelContext.fetch(setsDescriptor)) ?? []
        for set in setsToDelete { modelContext.delete(set) }

        let e1rmDescriptor = FetchDescriptor<Estimated1RM>(
            predicate: #Predicate { $0.exercise?.id == exerciseId }
        )
        let estimatesToDelete = (try? modelContext.fetch(e1rmDescriptor)) ?? []
        for estimate in estimatesToDelete { modelContext.delete(estimate) }

        exercise.deleted = true
        try? modelContext.save()
        Task { await SyncService.shared.syncExercise(exercise) }
    }

    // MARK: - Weight Picker

    private var weightPickerSheet: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(calculatorExpressionDisplay.isEmpty ? " " : calculatorExpressionDisplay)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(calculatorExpressionDisplay.isEmpty ? 0 : 0.6))
                    .frame(height: 24)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(calculatorResultDisplay)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(userProperties.preferredWeightUnit.label)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(height: 110)
            .padding(.horizontal, 16)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(["1", "2", "3"], id: \.self) { number in calcButton(number) }
                    Button { handleCalcBackspace() } label: {
                        Image(systemName: "delete.left")
                            .font(.title2).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(Color(white: 0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                HStack(spacing: 10) {
                    ForEach(["4", "5", "6"], id: \.self) { number in calcButton(number) }
                    calcOperatorButton("+")
                }
                HStack(spacing: 10) {
                    ForEach(["7", "8", "9"], id: \.self) { number in calcButton(number) }
                    calcOperatorButton("−")
                }
                HStack(spacing: 10) {
                    calcButton(".")
                    calcButton("0")
                    Button {
                        calculatorTokens = []
                        currentCalcInput = ""
                    } label: {
                        Text("C").font(.title2).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(Color(white: 0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button { evaluateAndCommit() } label: {
                        Text("=").font(.title2).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(Color.appAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal)

            Button {
                let result = evaluateCalculator()
                let lbsResult = userProperties.preferredWeightUnit.toLbs(result)
                let loadType = selectedExercise?.exerciseLoadType
                let minWeight = (loadType?.allowsZeroWeight == true) ? 0.0 : 0.01
                if lbsResult >= minWeight && lbsResult <= 1000 {
                    weight = lbsResult
                    weightIsSet = true
                }
                showWeightPicker = false
            } label: {
                Text("Done")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 55)
                    .background(Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top, 16)
        .onAppear {
            calculatorTokens = []
            let displayWeight = userProperties.preferredWeightUnit.fromLbs(weight).rounded1()
            currentCalcInput = displayWeight.formatted(.number.precision(.fractionLength(0...2)))
            weightInputIsFirstKeypress = true
        }
    }

    private func calcButton(_ value: String) -> some View {
        Button {
            handleCalcInput(value)
        } label: {
            Text(value).font(.title2).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Color(white: 0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func calcOperatorButton(_ op: String) -> some View {
        Button {
            handleCalcOperator(op)
        } label: {
            Text(op).font(.title2).foregroundStyle(.black)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Color.appAccent.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var calculatorExpressionDisplay: String {
        var display = calculatorTokens.joined(separator: " ")
        if !currentCalcInput.isEmpty {
            if !display.isEmpty { display += " " }
            display += currentCalcInput
        }
        return display.isEmpty ? "" : display
    }

    private var calculatorResultDisplay: String {
        let result = evaluateCalculator()
        if result == 0 && calculatorTokens.isEmpty && currentCalcInput.isEmpty { return "---" }
        if result == floor(result) { return String(format: "%.0f", result) }
        return String(format: "%.2f", result).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }

    private func handleCalcInput(_ digit: String) {
        if weightInputIsFirstKeypress {
            weightInputIsFirstKeypress = false
            if digit == "." {
                currentCalcInput = "0."
            } else {
                currentCalcInput = digit
            }
            return
        }
        if digit == "." {
            if currentCalcInput.isEmpty { currentCalcInput = "0." }
            else if !currentCalcInput.contains(".") { currentCalcInput += "." }
            return
        }
        if currentCalcInput == "0" && digit != "." { currentCalcInput = digit; return }
        if currentCalcInput.contains(".") {
            let parts = currentCalcInput.split(separator: ".")
            if parts.count > 1 && parts[1].count >= 2 { currentCalcInput = digit; return }
        } else {
            if currentCalcInput.count >= 3 { currentCalcInput = digit; return }
        }
        currentCalcInput += digit
    }

    private func handleCalcOperator(_ op: String) {
        if !currentCalcInput.isEmpty {
            calculatorTokens.append(currentCalcInput)
            currentCalcInput = ""
        } else if calculatorTokens.isEmpty {
            calculatorTokens.append(weight.rounded1().formatted(.number.precision(.fractionLength(0...2))))
        }
        if let last = calculatorTokens.last, last == "+" || last == "−" { calculatorTokens.removeLast() }
        calculatorTokens.append(op)
    }

    private func handleCalcBackspace() {
        if !currentCalcInput.isEmpty { currentCalcInput.removeLast() }
        else if !calculatorTokens.isEmpty { calculatorTokens.removeLast() }
    }

    private func evaluateCalculator() -> Double {
        var tokens = calculatorTokens
        if !currentCalcInput.isEmpty { tokens.append(currentCalcInput) }
        if tokens.isEmpty { return 0 }
        var result: Double = 0
        var currentOp: String = "+"
        for token in tokens {
            if token == "+" || token == "−" { currentOp = token }
            else if let value = Double(token) {
                if currentOp == "+" { result += value }
                else if currentOp == "−" { result -= value }
            }
        }
        return max(0, result)
    }

    private func evaluateAndCommit() {
        let result = evaluateCalculator()
        calculatorTokens = []
        currentCalcInput = result > 0 ? result.rounded1().formatted(.number.precision(.fractionLength(0...2))) : ""
    }

    // MARK: - Reps Picker

    private var repsPickerSheet: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 20)
            VStack(spacing: 4) {
                Text(repsInput.isEmpty || repsInput == "---" ? "---" : repsInput)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(height: 60)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("reps")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            VStack(spacing: 12) {
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { number in
                            Button { handleRepsInput(number) } label: {
                                Text(number).font(.title2).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).frame(height: 60)
                                    .background(Color(white: 0.18))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                HStack(spacing: 12) {
                    Color.clear.frame(maxWidth: .infinity).frame(height: 60)
                    Button { handleRepsInput("0") } label: {
                        Text("0").font(.title2).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 60)
                            .background(Color(white: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        if !repsInput.isEmpty && repsInput != "---" {
                            repsInput.removeLast()
                            if repsInput.isEmpty { repsInput = "---" }
                        }
                    } label: {
                        Image(systemName: "delete.left").font(.title2).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 60)
                            .background(Color(white: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button {
                    repsInput = "---"
                } label: {
                    Text("Clear").font(.title3.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 55)
                        .background(Color(white: 0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button {
                    if repsInput != "---", let value = Int(repsInput), value > 0, value <= 99 {
                        reps = value
                        repsIsSet = true
                    }
                    showRepsPicker = false
                } label: {
                    Text("Done").font(.title3.weight(.semibold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 55)
                        .background(Color.appAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(
            LinearGradient(colors: [Color(white: 0.18), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
        )
        .onAppear {
            repsInput = "\(reps)"
            repsInputIsFirstKeypress = true
        }
    }

    private func handleRepsInput(_ digit: String) {
        if repsInputIsFirstKeypress {
            repsInputIsFirstKeypress = false
            if digit != "0" { repsInput = digit }
            return
        }
        if repsInput == "---" {
            if digit != "0" { repsInput = digit }
            return
        }
        if repsInput == "0" { repsInput = digit; return }
        if repsInput.count >= 2 { repsInput = digit; return }
        let testInput = repsInput + digit
        if let value = Int(testInput), value <= 99 { repsInput += digit }
    }

    // MARK: - Effort Shortcuts

    // Returns the most recent LiftSet (from the in-memory 3-month window) whose
    // current percent of e1RM falls inside `bounds`. Used to prefer a real past
    // set over a computed fresh suggestion when pre-filling Easy/Mod/Hard.
    private func mostRecentSet(inBounds bounds: ClosedRange<Double>, currentE1RM: Double) -> (weight: Double, reps: Int)? {
        guard currentE1RM > 0 else { return nil }
        // setsForExercise is fetched newest-first via the descriptor's SortDescriptor.
        for set in setsForExercise where !set.deleted {
            let estimated = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)
            let percent = estimated / currentE1RM * 100.0
            if bounds.contains(percent) {
                // Most recent set at this effort band. If it's high-rep (>12), skip the historical
                // override and let the caller use the calculated recommendation instead.
                if set.reps > UserProperties.repRangeMax { return nil }
                return (set.weight, set.reps)
            }
        }
        return nil
    }

    private var effortShortcuts: (easy: (weight: Double, reps: Int), moderate: (weight: Double, reps: Int), hard: (weight: Double, reps: Int))? {
        let e1rm = current1RM
        guard e1rm > 0, let ex = selectedExercise else { return nil }
        let loadType = ex.exerciseLoadType
        let barWt = ex.effectiveBarbellWeight
        let macroWeights = OneRMCalculator.efficientPlateWeights(loadType: loadType, barWeight: barWt)

        struct TierConfig {
            let targets: [Double]
            let bounds: ClosedRange<Double>
            let repRange: ClosedRange<Int>
        }

        let tiers: [TierConfig] = [
            TierConfig(targets: [0.55, 0.60, 0.65], bounds: 0...70, repRange: 8...12),
            TierConfig(targets: [0.73, 0.76, 0.79], bounds: 70...82, repRange: 6...10),
            TierConfig(targets: [0.84, 0.87, 0.90], bounds: 82...92, repRange: 3...6),
        ]

        var picks: [(weight: Double, reps: Int)] = []

        for tier in tiers {
            // 1. Prefer the most recent set whose current percent still classifies
            //    in this effort bucket — usually the user's last matching set.
            if let recent = mostRecentSet(inBounds: tier.bounds, currentE1RM: e1rm) {
                picks.append(recent)
                continue
            }

            // 2. Fallback: synthesize a fresh suggestion using the existing logic.
            var results = OneRMCalculator.effortSuggestions(
                current1RM: e1rm,
                targetPercent1RMs: tier.targets,
                loadType: loadType,
                repRange: tier.repRange,
                barWeight: barWt
            )
            results = results.filter { tier.bounds.contains($0.percent1RM) }

            // Sort by weight ascending, then promote macro-plate-friendly weights
            results.sort { $0.weight < $1.weight }
            let final = results.filter { macroWeights.contains($0.weight) } + results.filter { !macroWeights.contains($0.weight) }

            guard let first = final.first else { return nil }
            picks.append((first.weight, first.reps))
        }

        guard picks.count == 3 else { return nil }
        return (easy: picks[0], moderate: picks[1], hard: picks[2])
    }

    // Standalone Near Max shortcut. Kept separate from `effortShortcuts` so the
    // existing Easy/Moderate/Hard tuple shape is untouched, and so that Near Max
    // failing (e.g. no recent sets and no synthesizable suggestion) doesn't
    // nil-out the other shortcuts. Used only by the Sets widget tile-tap when
    // a plan's effortSequence includes "redline" — there's no Jump-to button
    // for Near Max in the log bar.
    private var nearMaxShortcut: (weight: Double, reps: Int)? {
        let e1rm = current1RM
        guard e1rm > 0, let ex = selectedExercise else { return nil }

        // 1. Prefer the most recent set whose current percent still classifies as Near Max.
        if let recent = mostRecentSet(inBounds: 92...100, currentE1RM: e1rm) {
            return recent
        }

        // 2. Fallback: synthesize a Near Max suggestion (heavy singles-to-triples).
        let loadType = ex.exerciseLoadType
        let barWt = ex.effectiveBarbellWeight
        let macroWeights = OneRMCalculator.efficientPlateWeights(loadType: loadType, barWeight: barWt)

        var results = OneRMCalculator.effortSuggestions(
            current1RM: e1rm,
            targetPercent1RMs: [0.93, 0.95, 0.97],
            loadType: loadType,
            repRange: 1...3,
            barWeight: barWt
        )
        results = results.filter { (92.0...100.0).contains($0.percent1RM) }
        results.sort { $0.weight < $1.weight }
        let final = results.filter { macroWeights.contains($0.weight) } + results.filter { !macroWeights.contains($0.weight) }

        guard let first = final.first else { return nil }
        return (first.weight, first.reps)
    }

    // Applies a preset (weight, reps) pick to the log bar with the same haptic,
    // flash, and tile-press animation as the inline tile-tap code used previously.
    /// Normalizes an effort to the snake_case token used in analytics, so a
    /// suggestion load and a logged-set copy report comparable values. Routing the
    /// key through `SetPlan.effortLabel` first is what keeps the legacy "redline"
    /// key out of the event stream: it reports as "near_max", matching the effort
    /// property on `baselineSetLogged`.
    private func effortToken(forKey key: String) -> String {
        effortToken(label: SetPlan.effortLabel(for: key))
    }

    private func effortToken(label: String) -> String {
        label.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    private func applyPreset(_ pick: (weight: Double, reps: Int), atIndex index: Int, effort: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AmplitudeService.shared.track(
            .setPresetLoaded(effort: effortToken(forKey: effort), source: "suggestion")
        )
        weight = pick.weight
        reps = pick.reps
        triggerLogSetFlash()
        tappedTileIndex = index
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if tappedTileIndex == index {
                tappedTileIndex = nil
            }
        }
    }

    // Shows the preset-unavailable informational alert. Distinguishes "no e1RM
    // baseline yet" (user hasn't logged a set for this exercise) from "synthesis
    // failed for this effort despite having a baseline" — the latter usually
    // means the user's available plates can't hit a clean weight in the bucket.
    private func showPresetUnavailableHint(forEffort effort: String) {
        // Tapping a set cell always confirms itself with haptics, even when no
        // preset could be synthesized. `applyPreset` fires its own on the success
        // path, so this is the only branch that would otherwise feel dead.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if current1RM > 0 {
            presetHintTitle = "Preset Unavailable"
            presetHintMessage = "We couldn't generate a \(effort) preset for this exercise. Try entering the weight and reps manually for this set."
        } else {
            presetHintTitle = "No Baseline Yet"
            presetHintMessage = "Log a set for this exercise first. Once you have a baseline e1RM, the app can fill in matching weights for each effort level."
        }
        showPresetHintAlert = true
    }

    // MARK: - Phase 3: Recommendation Cards

    @ViewBuilder
    private var quickPickCards: some View {
        let e1rm = current1RM
        if e1rm > 0, let ex = selectedExercise {
            let increment = ex.effectiveWeightIncrement
            let suggestions = OneRMCalculator.minimizedSuggestions(current1RM: e1rm, increment: increment)
            let minReps = userProperties.progressMinReps
            let maxReps = userProperties.progressMaxReps
            let filtered = suggestions.filter { $0.reps >= minReps && $0.reps <= maxReps }

            if filtered.count >= 2 {
                let sorted = filtered.sorted(by: { $0.delta < $1.delta })
                let conservative = sorted.first!
                let stretch = sorted.last!
                let midIndex = sorted.count / 2
                let advancement = sorted[midIndex]

                let cards: [(label: String, subtitle: String, suggestion: OneRMCalculator.Suggestion, color: Color)] = {
                    var result: [(label: String, subtitle: String, suggestion: OneRMCalculator.Suggestion, color: Color)] = [
                        ("Conservative Win", "Solid volume, guaranteed gain", conservative, .setEasy),
                        ("Advancement", "Push into new territory", advancement, .setModerate),
                        ("Stretch Attempt", "Go for a major PR", stretch, .appAccent),
                    ]

                    // Tier Breaker card: only for core exercises with tier thresholds, not at Legend
                    if StrengthTierData.thresholds[ex.name] != nil {
                        let currentTier = StrengthTierData.tierForExercise(
                            name: ex.name, e1rm: e1rm, bodyweight: bodyweight, sex: sex
                        )
                        if let nextTierE1RM = StrengthTierData.nextTierMinimum(
                            name: ex.name, currentTier: currentTier, bodyweight: bodyweight, sex: sex
                        ),
                           nextTierE1RM - e1rm <= 20,
                           let nextTier = StrengthTier(rawValue: currentTier.rawValue + 1),
                           let tierBreaker = OneRMCalculator.tierBreakerSuggestion(
                               current1RM: e1rm, targetE1RM: nextTierE1RM, increment: increment
                           )
                        {
                            result.append(("Tier Breaker", "Reach \(nextTier.title)", tierBreaker, nextTier.color))
                        }
                    }

                    return result
                }()

                Divider()
                    .background(.white.opacity(0.1))
                    .padding(.vertical, 10)

                Text("Quick Picks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)

                VStack(spacing: 6) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    Button {
                        hapticFeedback.impactOccurred()
                        weight = card.suggestion.weight
                        reps = card.suggestion.reps
                        triggerLogSetFlash()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(card.color)

                                Text("\(userProperties.preferredWeightUnit.formatWeightTrimmed(card.suggestion.weight)) × \(card.suggestion.reps)")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 3) {
                                Text("e1RM +\(userProperties.preferredWeightUnit.formatWeight2dp(card.suggestion.delta)) \(userProperties.preferredWeightUnit.label)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(card.color)

                                Text(card.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .padding(12)
                        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(card.color.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                }
            }
        }
    }

    // MARK: - Phase 3: Log Set Controls

    private var floatingLogBar: some View {
        // +/- always steps by the unit's smallest plate pair (2.5 lbs / 1.25 kg)
        // and snaps off-multiple values (e.g. 47.3 lbs) to the nearest multiple
        // in the direction of the button rather than naively adding the step.
        let unit = userProperties.preferredWeightUnit
        let projected = OneRMCalculator.estimate1RM(weight: weight, reps: reps)
        return VStack(spacing: 6) {
            // Top row: intensity label (when inputs are set) + Jump-to shortcuts.
            // The left half is kept in the layout always so the Jump-to shortcuts
            // stay anchored in the same physical location regardless of whether
            // the intensity label is visible.
            if current1RM > 0 {
                let showIntensity = weightIsSet && repsIsSet
                let percent = projected / current1RM
                let isProgress = (projected - current1RM) > 0.0001
                let bucket = TrendsCalculator.IntensityBucket.from(percent1RM: percent)
                let bucketColor: Color = {
                    if isProgress { return .appAccent }
                    switch bucket {
                    case .easy: return .setEasy
                    case .moderate: return .setModerate
                    case .hard: return .setHard
                    case .nearMax: return .setNearMax
                    case .pr: return .appAccent
                    }
                }()
                let bucketLabel = isProgress ? "Progress" : bucket.rawValue

                HStack(spacing: 0) {
                    // Left half: intensity info — invisible (but layout-preserving)
                    // when inputs are still in their empty/placeholder state.
                    HStack(spacing: 6) {
                        Circle()
                            .fill(bucketColor)
                            .frame(width: 6, height: 6)
                        Text(bucketLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(bucketColor)
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                        if isProgress {
                            // Drop "e1RM" label to make room for the gain readout —
                            // the most informative number for a Progress set.
                            // Keep full precision normally, but shorten both percent
                            // and gain to tenths place when the gain reaches 100+
                            // to keep the row from wrapping.
                            let gain = userProperties.preferredWeightUnit.fromLbs(projected - current1RM)
                            let useShort = gain >= 100.0
                            let percentStr = useShort
                                ? String(format: "%.1f", percent * 100)
                                : String(format: "%.2f", percent * 100)
                            let gainStr = useShort
                                ? String(format: "+%.1f", gain)
                                : String(format: "+%.2f", gain)
                            Text("\(percentStr)%")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Text("·")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                            Text(gainStr)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.appAccent)
                        } else {
                            Text("\(String(format: "%.2f", percent * 100))% e1RM")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(showIntensity ? 1 : 0)

                    Text("|")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.2))
                        .opacity(showIntensity ? 1 : 0)

                    // Right half: effort shortcuts, centered
                    if let shortcuts = effortShortcuts {
                        HStack(spacing: 10) {
                            Text("Jump to →")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.35))
                            Button {
                                weight = shortcuts.easy.weight
                                reps = shortcuts.easy.reps
                                triggerLogSetFlash()
                            } label: {
                                Text("Easy")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.setEasy)
                            }
                            .buttonStyle(.plain)
                            Button {
                                weight = shortcuts.moderate.weight
                                reps = shortcuts.moderate.reps
                                triggerLogSetFlash()
                            } label: {
                                Text("Mod")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.setModerate)
                            }
                            .buttonStyle(.plain)
                            Button {
                                weight = shortcuts.hard.weight
                                reps = shortcuts.hard.reps
                                triggerLogSetFlash()
                            } label: {
                                Text("Hard")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.setHard)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 6) {
                // Weight with increment/decrement
                HStack(spacing: 4) {
                    Button {
                        weightIsSet = true
                        weight = unit.toLbs(unit.snappedDown(unit.fromLbs(weight)))
                        hapticFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                              .font(.system(size: 18))
                            .foregroundStyle(Color.appAccent)
                    }

                    Button {
                        showWeightPicker = true
                    } label: {
                        VStack(spacing: 0) {
                            if weightIsSet {
                                let displayW = userProperties.preferredWeightUnit.fromLbs(weight)
                                let formatted: String = {
                                    if displayW == floor(displayW) { return "\(Int(displayW))" }
                                    let oneDP = String(format: "%.1f", displayW)
                                    let twoDP = String(format: "%.2f", displayW)
                                    // Use 2dp only if meaningful (e.g., 45.25 not 45.20)
                                    if abs(displayW - Double(oneDP)!) > 0.01 && !twoDP.hasSuffix("0") {
                                        return twoDP
                                    }
                                    return oneDP
                                }()
                                let needsSmaller = formatted.count > 5
                                Text(formatted)
                                    .font(.system(size: needsSmaller ? 13 : 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            } else {
                                ViewfinderPulse(size: 16)
                            }
                            Text(userProperties.preferredWeightUnit.label)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(width: 56)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    Button {
                        weightIsSet = true
                        weight = unit.toLbs(unit.snappedUp(unit.fromLbs(weight)))
                        hapticFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.appAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(weightHighlight ? Color.appAccent : Color.yellow, lineWidth: 1.5)
                        .opacity(logSetFlashActive || weightHighlight ? 1 : 0)
                )

                // Reps
                HStack(spacing: 4) {
                    Button {
                        repsIsSet = true
                        reps = max(1, reps - 1)
                        hapticFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.appAccent)
                    }

                    Button {
                        showRepsPicker = true
                    } label: {
                        VStack(spacing: 0) {
                            if repsIsSet {
                                Text("\(reps)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            } else {
                                ViewfinderPulse(size: 16)
                            }
                            Text("reps")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(width: 36)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    Button {
                        repsIsSet = true
                        reps = min(99, reps + 1)
                        hapticFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.appAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(repsHighlight ? Color.appAccent : Color.yellow, lineWidth: 1.5)
                        .opacity(logSetFlashActive || repsHighlight ? 1 : 0)
                )

                // Log Set button
                Button {
                    if !weightIsSet || !repsIsSet {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        triggerFieldHighlights()
                    } else {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        logSet()
                    }
                } label: {
                    Text("Log Set")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.appAccent.opacity(weightIsSet && repsIsSet ? 1 : 0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            Color(white: 0.10)
                .ignoresSafeArea(.container, edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
        }
    }

    // MARK: - Phase 4: Accessory Section

    @ViewBuilder
    private var accessorySection: some View {
        VStack(spacing: 10) {
            // Accessory toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAccessories.toggle()
                }
            } label: {
                HStack {
                    Text("ACCESSORIES")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1)
                    Spacer()
                    Image(systemName: showAccessories ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(12)
                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if showAccessories {
                let accessoryList = nonGroupExercises

                if accessoryList.isEmpty {
                    Text("No accessories configured")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.vertical, 8)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(accessoryList) { exercise in
                                let isSelected = isAccessoryMode && selectedAccessoryId == exercise.id

                                Button {
                                    hapticFeedback.impactOccurred()
                                    if isSelected {
                                        // Deselect → back to fundamental mode
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isAccessoryMode = false
                                            selectedAccessoryId = nil
                                        }
                                        loadDataForSelectedLift()
                                    } else {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isAccessoryMode = true
                                            selectedAccessoryId = exercise.id
                                        }
                                        loadDataForExercise(exercise.id)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(exercise.icon)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 18, height: 18)
                                            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))

                                        Text(exercise.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected ? Color.white.opacity(0.15) : Color(white: 0.15))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(isSelected ? Color.white.opacity(0.3) : .clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    // MARK: - Overlays

    // MARK: - Sync In Progress Overlay

    private var syncInProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // X dismiss button
                HStack {
                    Spacer()
                    Button {
                        showSyncDismissConfirmation = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Animated icon
                ZStack {
                    Circle()
                        .stroke(Color.appAccent.opacity(syncPulsePhase ? 0.3 : 0.1), lineWidth: 2)
                        .frame(width: 80, height: 80)

                    Circle()
                        .stroke(Color.appAccent.opacity(syncPulsePhase ? 0.15 : 0.05), lineWidth: 1)
                        .frame(width: 100, height: 100)

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.appAccent)
                        .rotationEffect(.degrees(syncPulsePhase ? 360 : 0))
                }
                .frame(width: 100, height: 100)
                .drawingGroup()
                .onAppear {
                    withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                        syncPulsePhase = true
                    }
                }

                Text("Syncing Your Data")
                    .font(.bebasNeue(size: 24))
                    .foregroundStyle(.white)

                Text(syncService.liftSetSyncProgress ?? "Preparing…")
                    .font(.inter(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .animation(.easeInOut(duration: 0.2), value: syncService.liftSetSyncProgress)

                Text("Hang tight — we're pulling in your training history.")
                    .font(.inter(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()
            }
            .padding(.top, 10)
        }
    }

    private var submitOverlay: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showSubmitOverlay = false
                    }
                }

            VStack(spacing: 10) {
                if overlayDidIncrease {
                    Image("LiftTheBullIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundStyle(Color.appLogoColor)

                    VStack(spacing: 4) {
                        Text("Increased 1RM by")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Text("+\(userProperties.preferredWeightUnit.formatWeight2dp(overlayDelta)) \(userProperties.preferredWeightUnit.label)")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(Color.appLogoColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(overlayIntensityColor.opacity(0.3))
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(overlayIntensityColor, lineWidth: 2)
                        )

                    VStack(spacing: 2) {
                        Text(overlayIntensityLabel)
                            .font(.bebasNeue(size: 32))
                            .foregroundStyle(.white)
                        Text("Set Logged")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .frame(width: 180, height: 180)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.appLogoColor.opacity(0.5), lineWidth: 1.5)
            )
        }
    }

    private var milestoneOverlay: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Milestone Achieved")
                    .font(.bebasNeue(size: 24))
                    .foregroundStyle(overlayMilestoneTier.color)

                ZStack {
                    Circle()
                        .fill(overlayMilestoneTier.color.opacity(0.2))
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(overlayMilestoneTier.color.opacity(0.7), lineWidth: 3)
                        .frame(width: 72, height: 72)
                    if overlayMilestoneTier == .legend {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(overlayMilestoneTier.color)
                    } else {
                        Image(overlayMilestoneExerciseIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .foregroundStyle(overlayMilestoneTier.color)
                    }
                }

                Text(overlayMilestoneExerciseName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Text(overlayMilestoneTargetLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showSubmitOverlay = false
                    }
                    selectedSetData.pendingTrendsTab = .strength
                    selectedSetData.pendingScrollToMilestones = true
                    selectedTab = 0
                } label: {
                    Text("See Milestones")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(overlayMilestoneTier.color, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.bottom, 4)
            }
            .padding(16)
            .frame(width: 220)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(overlayMilestoneTier.color.opacity(0.5), lineWidth: 1.5)
            )
        }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.18)) {
                showSubmitOverlay = false
            }
        }
    }

    private func deleteSet(_ set: LiftSet) {
        let setId = set.id
        let exercise = set.exercise

        set.deleted = true

        // Find and soft-delete the associated Estimated1RM via manual fetch
        var estimated1RMId: UUID? = nil
        let e1rmDescriptor = FetchDescriptor<Estimated1RM>(
            predicate: #Predicate { !$0.deleted && $0.setId == setId }
        )
        if let associated1RM = try? modelContext.fetch(e1rmDescriptor).first {
            associated1RM.deleted = true
            estimated1RMId = associated1RM.id
        }

        // Recompute exercise.currentE1RMLocalCache from remaining records
        if let ex = exercise {
            let exerciseId = ex.id
            let remainingDescriptor = FetchDescriptor<Estimated1RM>(
                predicate: #Predicate { !$0.deleted && $0.exercise?.id == exerciseId },
                sortBy: [SortDescriptor(\.value, order: .reverse)]
            )
            if let maxRecord = try? modelContext.fetch(remainingDescriptor).first {
                ex.currentE1RMLocalCache = maxRecord.value
                ex.currentE1RMDateLocalCache = maxRecord.createdAt
                latestE1RMs[exerciseId] = maxRecord.value
            } else {
                ex.currentE1RMLocalCache = nil
                ex.currentE1RMDateLocalCache = nil
                latestE1RMs.removeValue(forKey: exerciseId)
            }
        }

        // Immediately remove from in-memory arrays
        setsForExercise.removeAll { $0.id == setId }
        estimated1RMsForExercise.removeAll { $0.setId == setId || $0.id == estimated1RMId }

        try? modelContext.save()

        Task {
            await SyncService.shared.deleteLiftSet(setId)
            if let e1rmId = estimated1RMId {
                await SyncService.shared.deleteEstimated1RM(estimated1RMId: e1rmId, liftSetId: setId)
            }
        }
    }

    // MARK: - Actions

    private func loadDataForSelectedLift() {
        guard let exercise = selectedExercise else { return }
        loadDataForExercise(exercise.id)
    }

    private func loadDataForExercise(_ exerciseId: UUID, preserveInputs: Bool = false) {
        let cutoff = Calendar.current.date(byAdding: .month, value: Self.e1rmQueryMonths, to: Date())!
        let setDescriptor = FetchDescriptor<LiftSet>(
            predicate: #Predicate { !$0.deleted && $0.exercise?.id == exerciseId && $0.createdAt >= cutoff },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        setsForExercise = (try? modelContext.fetch(setDescriptor)) ?? []

        let e1rmDescriptor = FetchDescriptor<Estimated1RM>(
            predicate: #Predicate { !$0.deleted && $0.exercise?.id == exerciseId && $0.createdAt >= cutoff },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        estimated1RMsForExercise = (try? modelContext.fetch(e1rmDescriptor)) ?? []

        // Set initial values based on load type (used when user first taps +/-)
        // Skip reset when preserving inputs after logging a set
        if !preserveInputs {
            if let ex = selectedExercise {
                if ex.exerciseLoadType == .bodyweightPlusSingleLoad {
                    weight = 0
                    reps = 5
                } else if current1RM > 0 {
                    let loadType = ex.exerciseLoadType
                    let repRange = EffortMode.easy.repRange(from: userProperties)
                    let targets = EffortMode.easy.targetPercent1RMs ?? [0.55, 0.60, 0.65]
                    let bounds = EffortMode.easy.percent1RMBounds ?? (0...70)
                    var results = OneRMCalculator.effortSuggestions(
                        current1RM: current1RM,
                        targetPercent1RMs: targets,
                        loadType: loadType,
                        repRange: repRange,
                        barWeight: ex.effectiveBarbellWeight
                    )
                    results = results.filter { bounds.contains($0.percent1RM) }
                    if let first = results.first {
                        weight = first.weight
                        reps = first.reps
                    } else {
                        weight = 92.5
                        reps = 5
                    }
                } else {
                    weight = 92.5
                    reps = 5
                }
                // Snap to a whole number in the user's displayed unit so the
                // weight field doesn't open on a fractional value (e.g., 0.56 kg
                // from a tiny lbs-rounded suggestion).
                let unit = userProperties.preferredWeightUnit
                weight = unit.toLbs(unit.fromLbs(weight).rounded())
            }
            weightIsSet = false
            repsIsSet = false
        }

        // Initialize weightDelta from exercise
        if let ex = selectedExercise {
            let persisted = ex.effectiveWeightIncrement
            if availableWeightDeltas.contains(where: { abs($0 - persisted) < 0.01 }) {
                weightDelta = persisted
            } else {
                weightDelta = availableWeightDeltas.min(by: { abs($0 - persisted) < abs($1 - persisted) }) ?? 5.0
            }
            initialWeightDelta = weightDelta
        }
    }

    private func logSet() {
        guard let ex = selectedExercise else { return }
        // Snapshot BEFORE any mutation: the unlock flag is flipped mid-function on the
        // unlocking set, and this gates the post-start milestone/tier-achievement events.
        let startingTierWasUnlocked = userPropertiesItems.first?.hasMetStrengthTierConditions ?? false
        if !isViewingToday { viewingDate = actualToday }

        let isFirstWeightedSet = !allEstimated1RM.contains(where: { $0.exercise?.id == ex.id }) && ex.currentE1RMLocalCache == nil && weight > 0

        let before = current1RM
        let set = LiftSet(exercise: ex, reps: reps, weight: weight)
        if isFirstWeightedSet {
            set.isBaselineSet = true
        }
        modelContext.insert(set)

        let newEstimate = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)
        let after = max(before, newEstimate)
        let d = after - before
        let increased = d > 0.0001

        // Milestone detection
        var isMilestone = false
        var isFirstTierLog = false
        var milestoneTier: StrengthTier = .novice
        var milestoneIcon: String = ""
        var milestoneName: String = ""
        var milestoneTargetLabel: String = ""

        if increased,
           let fundamental = TrendsCalculator.fundamentalExercises.first(where: { $0.id == ex.id }) {
            let oldTier = StrengthTierData.tierForExercise(name: fundamental.name, e1rm: before, bodyweight: bodyweight, sex: sex)
            let newTier = StrengthTierData.tierForExercise(name: fundamental.name, e1rm: after, bodyweight: bodyweight, sex: sex)
            if newTier > oldTier {
                isMilestone = true
                isFirstTierLog = oldTier == .none
                milestoneTier = newTier
                milestoneIcon = fundamental.icon
                milestoneName = fundamental.name
                if let threshold = StrengthTierData.thresholds[fundamental.name]?[sex]?[newTier] {
                    if newTier == .novice {
                        milestoneTargetLabel = "1 Set Logged"
                    } else if threshold.isAbsolute {
                        milestoneTargetLabel = "\(userProperties.preferredWeightUnit.formatWeightRounded(threshold.min)) \(userProperties.preferredWeightUnit.label)"
                    } else {
                        let m = threshold.min
                        milestoneTargetLabel = m == floor(m) ? "\(Int(m))× BW" : "\(String(format: "%g", m))× BW"
                    }
                }
            }
        }

        // Amplitude: fire "Set Logged" now for regular sets. Baseline (first-weighted)
        // sets are deferred to applyCalibration() so the event can include the effort
        // the user selects in the "How did that feel?" prompt — and so a cancelled
        // calibration doesn't leave a phantom Set Logged behind.
        if !isFirstWeightedSet {
            AmplitudeService.shared.track(.setLogged(SetLogProperties(
                exerciseName: ex.name,
                exerciseId: ex.id.uuidString,
                loadType: ex.loadType,
                reps: set.reps,
                weight: set.weight,
                isBaselineSet: set.isBaselineSet,
                estimated1RM: newEstimate,
                e1rmIncreased: increased,
                isMilestone: isMilestone,
                isFirstTierLog: isFirstTierLog
            )))
        }

        // Create Estimated1RM (running max)
        let estimated = Estimated1RM(exercise: ex, value: after, setId: set.id)

        // Capture overall tier before model write so we can detect tier-ups
        let previousOverallTier = strengthTierResult.overallTier

        // First weighted set: defer model save and data refresh until calibration is applied
        if isFirstWeightedSet {
            // Suppress tier display before model write to prevent spoiler during overlay
            if isFirstTierLog {
                suppressTierDisplay = true
            }
            if ex.exerciseLoadType == .bodyweightPlusSingleLoad && weight <= 10 && reps < 5 {
                pendingCalibrationSet = set
                pendingCalibrationEstimated = estimated
                let autoEffort: EffortMode
                if reps <= 2 { autoEffort = .easy }
                else if reps == 3 { autoEffort = .moderate }
                else { autoEffort = .hard }
                applyCalibration(effort: autoEffort)
                return
            }
            pendingCalibrationSet = set
            pendingCalibrationEstimated = estimated
            showCalibrationAlert = true
            return
        }

        // Post-start per-exercise milestone: fires for every fundamental tier crossing after
        // the starting tier is unlocked (never on the unlocking set or its constituent tiers).
        if isMilestone && startingTierWasUnlocked {
            AmplitudeService.shared.track(.strengthMilestoneAchieved(
                exercise: milestoneName, tier: milestoneTier.title, estimated1RM: after))
        }

        // Non-first-weighted-set: save model and sync now
        if isFirstTierLog {
            suppressTierDisplay = true
        }
        modelContext.insert(estimated)

        // Update exercise's cached currentE1RMLocalCache
        if after > (ex.currentE1RMLocalCache ?? 0) {
            ex.currentE1RMLocalCache = after
            ex.currentE1RMDateLocalCache = Date()
            latestE1RMs[ex.id] = after
        }

        // Capture current inputs before save (save triggers @Query onChange which may reset them)
        let savedWeight = weight
        let savedReps = reps

        try? modelContext.save()

        // Refresh data but preserve the current weight/reps inputs
        loadDataForExercise(ex.id, preserveInputs: true)

        // Re-assert inputs on next run loop in case an onChange cleared them
        DispatchQueue.main.async {
            weight = savedWeight
            reps = savedReps
            weightIsSet = true
            repsIsSet = true
        }

        let crumb = Breadcrumb(level: .info, category: "training")
        crumb.message = "Set logged: \(ex.name) \(set.weight)×\(set.reps)"
        SentrySDK.addBreadcrumb(crumb)

        // Determine tier unlock before sync so we can trigger it after sync completes
        var tierToUnlock: StrengthTier? = nil

        if isFirstTierLog {
            let tierResult = TrendsCalculator.strengthTierAssessment(
                from: allEstimated1RM,
                exercises: exercises,
                bodyweight: bodyweight,
                biologicalSex: biologicalSex
            )
            let loggedAfterThis = tierResult.exerciseTiers.filter { $0.e1rm != nil }.count
            if loggedAfterThis >= 5 {
                tierJourneyMode = .completion(tier: tierResult.overallTier)
                tierJourneyHideTierName = !(userPropertiesItems.first?.hasMetStrengthTierConditions ?? false)
                tierToUnlock = tierResult.overallTier
                if let props = userPropertiesItems.first, !props.hasMetStrengthTierConditions {
                    props.hasMetStrengthTierConditions = true
                    try? modelContext.save()
                    AmplitudeService.shared.track(.startingStrengthTierUnlocked(tier: tierResult.overallTier.title))
                    Task {
                        let request = UserPropertiesRequest(hasMetStrengthTierConditions: true)
                        _ = try? await APIService.shared.updateUserProperties(request)
                    }
                }
            } else {
                tierJourneyMode = .progress(justLoggedId: ex.id)
            }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                showTierJourneyOverlay = true
            }

            // Sync data, then trigger tier unlock after backend has the e1RM
            Task {
                await SyncService.shared.syncLiftSet(set, isPremiumOnClient: isPremium)
                await SyncService.shared.syncEstimated1RM(estimated)
                if let tier = tierToUnlock {
                    await NarrativeBadgeService.shared.triggerTierUnlock(tier: tier)
                }
            }
            return
        }

        // Overall tier-up detection (non-journey milestone that bumps overall tier).
        // `strengthTierResult` is @State and doesn't reflect the just-inserted
        // Estimated1RM inside this function call, so we substitute the logged
        // exercise's new tier into the existing list and recompute the overall
        // tier (= min across all five) ourselves.
        if isMilestone {
            let allTiersAfter: [StrengthTier] = strengthTierResult.exerciseTiers.map { item in
                item.exercise.id == ex.id ? milestoneTier : item.tier
            }
            let newOverallTier = allTiersAfter.min() ?? .none
            if newOverallTier > previousOverallTier && newOverallTier > .none {
                tierJourneyMode = .completion(tier: newOverallTier)
                tierJourneyHideTierName = !(userPropertiesItems.first?.hasMetStrengthTierConditions ?? false)
                tierToUnlock = newOverallTier
                if startingTierWasUnlocked {
                    AmplitudeService.shared.track(.strengthTierAchieved(
                        tier: newOverallTier.title, previousTier: previousOverallTier.title, drivingExercise: milestoneName))
                }
                if let props = userPropertiesItems.first, !props.hasMetStrengthTierConditions {
                    props.hasMetStrengthTierConditions = true
                    try? modelContext.save()
                    Task {
                        let request = UserPropertiesRequest(hasMetStrengthTierConditions: true)
                        _ = try? await APIService.shared.updateUserProperties(request)
                    }
                }
                suppressTierDisplay = true
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    showTierJourneyOverlay = true
                }

                // Sync data, then trigger tier unlock after backend has the e1RM
                Task {
                    await SyncService.shared.syncLiftSet(set, isPremiumOnClient: isPremium)
                    await SyncService.shared.syncEstimated1RM(estimated)
                    if let tier = tierToUnlock {
                        await NarrativeBadgeService.shared.triggerTierUnlock(tier: tier)
                    }
                }
                return
            }
        }

        // No tier unlock — sync normally
        Task {
            await SyncService.shared.syncLiftSet(set, isPremiumOnClient: isPremium)
            await SyncService.shared.syncEstimated1RM(estimated)
        }

        // Not a tier journey redirect — clear suppress flag
        suppressTierDisplay = false

        // Set overlay state
        overlayDidIncrease = increased
        overlayDelta = d
        overlayNew1RM = after
        overlayIsMilestone = isMilestone
        overlayMilestoneTier = milestoneTier
        overlayMilestoneExerciseIcon = milestoneIcon
        overlayMilestoneExerciseName = milestoneName
        overlayMilestoneTargetLabel = milestoneTargetLabel

        if !increased {
            if set.weight == 0 {
                overlayIntensityColor = .white
                overlayIntensityLabel = "Bodyweight"
            } else {
                let rawPercent = before > 0 ? newEstimate / before : 0
                // Clamp below 1.0 since !increased means this isn't a true PR
                let percent1RM = min(rawPercent, 0.9999)
                let bucket = TrendsCalculator.IntensityBucket.from(percent1RM: percent1RM)
                overlayIntensityLabel = bucket == .pr ? "Progress" : bucket.rawValue
                switch bucket {
                case .pr, .nearMax: overlayIntensityColor = .setNearMax
                case .hard: overlayIntensityColor = .setHard
                case .moderate: overlayIntensityColor = .setModerate
                case .easy: overlayIntensityColor = .setEasy
                }
            }
        } else {
            overlayIntensityColor = .appAccent
            overlayIntensityLabel = "Progress"
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            showSubmitOverlay = true
        }

        // Queue a one-time App Store review request: fires after this increase dialog dismisses,
        // on the user's first e1RM progress on a fundamental lift once the starting tier is unlocked.
        let isFundamentalLift = TrendsCalculator.fundamentalExercises.contains { $0.id == ex.id }
        if startingTierWasUnlocked, increased, !isMilestone, isFundamentalLift, !hasRequestedAppStoreReview {
            pendingReviewAfterProgress = true
        }

        // Auto-dismiss after 2s if not milestone
        if !isMilestone {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showSubmitOverlay = false
                    }
                }
            }
        }
    }

    /// Roll the pending first-set calibration back to the pre-submit state.
    /// `logSet` inserts the LiftSet before the alert appears, so we soft-delete
    /// it here (matching the codebase's `deleteSet` convention so `@Query` and
    /// the in-memory `setsForExercise`/`estimated1RMsForExercise` caches all
    /// drop it). The Estimated1RM is held in memory only (never inserted) so
    /// it just needs to be nil'd. No backend sync is needed: the set has not
    /// been pushed to the API yet (sync only fires from the post-alert path).
    private func discardPendingCalibration() {
        if let set = pendingCalibrationSet {
            let setId = set.id
            set.deleted = true
            setsForExercise.removeAll { $0.id == setId }
            estimated1RMsForExercise.removeAll { $0.setId == setId }
            try? modelContext.save()
            if let exId = set.exercise?.id {
                loadDataForExercise(exId, preserveInputs: true)
            }
        }
        pendingCalibrationSet = nil
        pendingCalibrationEstimated = nil
        suppressTierDisplay = false
    }

    private func applyCalibration(effort: EffortMode) {
        guard let fraction = effort.calibrationMidpoint else {
            pendingCalibrationSet = nil
            pendingCalibrationEstimated = nil
            return
        }
        applyCalibration(effortFraction: fraction, effort: effort)
    }

    private func applyCalibration(effortFraction fraction: Double, effort: EffortMode? = nil) {
        guard let set = pendingCalibrationSet,
              let estimated = pendingCalibrationEstimated else {
            pendingCalibrationSet = nil
            pendingCalibrationEstimated = nil
            return
        }

        let calibratedValue = OneRMCalculator.calibrated1RM(
            weight: set.weight, reps: set.reps, effortFraction: fraction
        )

        // Milestone detection before model write (to suppress tier display if needed)
        var isMilestone = false
        var milestoneTier: StrengthTier = .novice
        var milestoneIcon: String = ""
        var milestoneName: String = ""
        var milestoneTargetLabel: String = ""

        if let exercise = set.exercise,
           let fundamental = TrendsCalculator.fundamentalExercises.first(where: { $0.id == exercise.id }) {
            let newTier = StrengthTierData.tierForExercise(name: fundamental.name, e1rm: calibratedValue, bodyweight: bodyweight, sex: sex)
            if newTier > .none {
                isMilestone = true
                milestoneTier = newTier
                milestoneIcon = fundamental.icon
                milestoneName = fundamental.name
                if let threshold = StrengthTierData.thresholds[fundamental.name]?[sex]?[newTier] {
                    if newTier == .novice {
                        milestoneTargetLabel = "1 Set Logged"
                    } else if threshold.isAbsolute {
                        milestoneTargetLabel = "\(userProperties.preferredWeightUnit.formatWeightRounded(threshold.min)) \(userProperties.preferredWeightUnit.label)"
                    } else {
                        let m = threshold.min
                        milestoneTargetLabel = m == floor(m) ? "\(Int(m))× BW" : "\(String(format: "%g", m))× BW"
                    }
                }
            }
        }

        // Capture overall tier before model write so we can detect tier-ups
        let previousOverallTier = strengthTierResult.overallTier

        // Suppress tier display before model write to prevent spoiler during overlay
        // In calibration path, isMilestone with newTier > .none means first tier log
        if isMilestone {
            suppressTierDisplay = true
        }

        estimated.value = calibratedValue
        modelContext.insert(estimated)

        // Update exercise's cached currentE1RMLocalCache
        if let ex = set.exercise {
            ex.currentE1RMLocalCache = calibratedValue
            ex.currentE1RMDateLocalCache = Date()
            latestE1RMs[ex.id] = calibratedValue
        }

        try? modelContext.save()

        // Amplitude: the baseline (first-weighted) set is now committed with the user's
        // effort selection. Baseline sets fire ONLY "Baseline Set Logged" (named per-lift for
        // the five strength-tier exercises) — not "Set Logged", to avoid a duplicate event.
        let effortLabel: String
        if let effort {
            switch effort {
            case .easy: effortLabel = "easy"
            case .moderate: effortLabel = "moderate"
            case .hard: effortLabel = "hard"
            // Amplitude wire value. Deliberately NOT the same as the persisted
            // set-plan effort key, which is still the legacy string "redline" —
            // don't "unify" these two. Renamed at the Near Max release, so any
            // query spanning that boundary must union "redline" and "near_max".
            case .progress: effortLabel = "near_max"
            }
        } else {
            effortLabel = "max_effort"
        }
        let baselineProps = SetLogProperties(
            exerciseName: set.exercise?.name ?? "",
            exerciseId: set.exercise?.id.uuidString ?? "",
            loadType: set.exercise?.loadType ?? "",
            reps: set.reps,
            weight: set.weight,
            isBaselineSet: set.isBaselineSet,
            estimated1RM: calibratedValue,
            e1rmIncreased: true,
            isMilestone: isMilestone,
            isFirstTierLog: isMilestone,
            effort: effortLabel
        )
        let baselineFundamentalName = set.exercise.flatMap { exercise in
            TrendsCalculator.fundamentalExercises.first(where: { $0.id == exercise.id })?.name
        }
        AmplitudeService.shared.track(.baselineSetLogged(fundamentalName: baselineFundamentalName, properties: baselineProps))

        if let exId = set.exercise?.id {
            loadDataForExercise(exId)
        }

        // Determine tier unlock before sync
        var calibrationTierToUnlock: StrengthTier? = nil

        // Redirect tier journey milestones (first log of any tier exercise during journey)
        // Compute fresh tier result since @State may not have updated yet
        if isMilestone, let exerciseForJourney = set.exercise {
            let tierResult = TrendsCalculator.strengthTierAssessment(
                from: allEstimated1RM,
                exercises: exercises,
                bodyweight: bodyweight,
                biologicalSex: biologicalSex
            )
            let loggedAfterThis = tierResult.exerciseTiers.filter { $0.e1rm != nil }.count
            if loggedAfterThis >= 5 {
                tierJourneyMode = .completion(tier: tierResult.overallTier)
                tierJourneyHideTierName = !(userPropertiesItems.first?.hasMetStrengthTierConditions ?? false)
                calibrationTierToUnlock = tierResult.overallTier
                if let props = userPropertiesItems.first, !props.hasMetStrengthTierConditions {
                    props.hasMetStrengthTierConditions = true
                    try? modelContext.save()
                    AmplitudeService.shared.track(.startingStrengthTierUnlocked(tier: tierResult.overallTier.title))
                    Task {
                        let request = UserPropertiesRequest(hasMetStrengthTierConditions: true)
                        _ = try? await APIService.shared.updateUserProperties(request)
                    }
                }
            } else {
                tierJourneyMode = .progress(justLoggedId: exerciseForJourney.id)
            }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                showTierJourneyOverlay = true
            }

            Task {
                await SyncService.shared.syncLiftSet(set, isPremiumOnClient: isPremium)
                await SyncService.shared.syncEstimated1RM(estimated)
                if let tier = calibrationTierToUnlock {
                    await NarrativeBadgeService.shared.triggerTierUnlock(tier: tier)
                }
            }
            pendingCalibrationSet = nil
            pendingCalibrationEstimated = nil
            return
        }

        // Overall tier-up detection (non-journey milestone that bumps overall tier).
        // Same fix as the regular log path: `strengthTierResult` is @State and
        // won't reflect the just-inserted estimate yet, so we substitute the
        // logged exercise's new tier and take the min.
        if isMilestone {
            let allTiersAfter: [StrengthTier] = strengthTierResult.exerciseTiers.map { item in
                item.exercise.id == set.exercise?.id ? milestoneTier : item.tier
            }
            let newOverallTier = allTiersAfter.min() ?? .none
            if newOverallTier > previousOverallTier && newOverallTier > .none {
                tierJourneyMode = .completion(tier: newOverallTier)
                tierJourneyHideTierName = !(userPropertiesItems.first?.hasMetStrengthTierConditions ?? false)
                calibrationTierToUnlock = newOverallTier
                if let props = userPropertiesItems.first, !props.hasMetStrengthTierConditions {
                    props.hasMetStrengthTierConditions = true
                    try? modelContext.save()
                    Task {
                        let request = UserPropertiesRequest(hasMetStrengthTierConditions: true)
                        _ = try? await APIService.shared.updateUserProperties(request)
                    }
                }
                suppressTierDisplay = true
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    showTierJourneyOverlay = true
                }

                Task {
                    await SyncService.shared.syncLiftSet(set, isPremiumOnClient: isPremium)
                    await SyncService.shared.syncEstimated1RM(estimated)
                    if let tier = calibrationTierToUnlock {
                        await NarrativeBadgeService.shared.triggerTierUnlock(tier: tier)
                    }
                }
                pendingCalibrationSet = nil
                pendingCalibrationEstimated = nil
                return
            }
        }

        // No tier unlock — sync normally
        Task {
            await SyncService.shared.syncLiftSet(set, isPremiumOnClient: isPremium)
            await SyncService.shared.syncEstimated1RM(estimated)
        }

        // Not a tier journey redirect — clear suppress flag
        suppressTierDisplay = false

        // Show milestone overlay if detected, otherwise calibration overlay
        overlayDidIncrease = isMilestone
        overlayDelta = 0
        overlayNew1RM = calibratedValue
        overlayIsMilestone = isMilestone
        overlayMilestoneTier = milestoneTier
        overlayMilestoneExerciseIcon = milestoneIcon
        overlayMilestoneExerciseName = milestoneName
        overlayMilestoneTargetLabel = milestoneTargetLabel
        if !isMilestone {
            // Max Effort path (effort == nil) sits above Near Max in intensity, so reuse the setNearMax color.
            if let effort {
                overlayIntensityColor = effort == .progress ? .setNearMax : effort.tileColor
            } else {
                overlayIntensityColor = .setNearMax
            }
            overlayIntensityLabel = "Calibrated"
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            showSubmitOverlay = true
        }

        // Auto-dismiss after 2s if not milestone
        if !isMilestone {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.18)) { showSubmitOverlay = false }
                }
            }
        }

        pendingCalibrationSet = nil
        pendingCalibrationEstimated = nil
    }

    private func navigateToTierExercise(_ exerciseId: UUID) {
        let needsGroupChange = activeGroupId != ExerciseGroup.tierExercisesId
        if needsGroupChange {
            activeGroupId = ExerciseGroup.tierExercisesId
            DispatchQueue.main.async {
                if let index = activeGroupExercises.firstIndex(where: { $0.id == exerciseId }) {
                    selectedLiftIndex = index
                }
                // Highlight log set inputs after navigation (beat then flash)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    triggerLogSetFlash(markFieldsSet: false)
                }
            }
        } else {
            if let index = activeGroupExercises.firstIndex(where: { $0.id == exerciseId }) {
                selectedLiftIndex = index
            }
            // Highlight log set inputs after navigation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                triggerLogSetFlash(markFieldsSet: false)
            }
        }
    }

    private func shortDisplayName(for name: String) -> String {
        switch name {
        case "Overhead Press": return "OH Press"
        case "Bench Press": return "Bench"
        case "Barbell Rows": return "Rows"
        default: return name
        }
    }

    private func tierProgress(for exercise: TrendsCalculator.FundamentalExercise) -> Double? {
        guard let item = strengthTierResult.exerciseTiers.first(where: { $0.exercise.id == exercise.id }) else { return nil }
        guard item.tier != .legend else { return nil }
        guard let e1rm = item.e1rm else { return 0 }

        let currentMin = StrengthTierData.currentTierMinimum(
            name: item.exercise.name,
            tier: item.tier,
            bodyweight: bodyweight,
            sex: sex
        )
        guard let nextMin = StrengthTierData.nextTierMinimum(
            name: item.exercise.name,
            currentTier: item.tier,
            bodyweight: bodyweight,
            sex: sex
        ) else { return nil }

        let range = nextMin - currentMin
        guard range > 0 else { return 1.0 }
        return min(max((e1rm - currentMin) / range, 0), 1.0)
    }

    /// Returns the e1RM gain over the last 7 days for a given exercise ID, or nil if no gain / no prior data.
    private func e1rmGain30Day(for exerciseId: UUID) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let descriptor = FetchDescriptor<Estimated1RM>(
            predicate: #Predicate { !$0.deleted && $0.exercise?.id == exerciseId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        guard let latest = records.first, let earliest = records.last else { return nil }

        // Baseline = the e1RM entering the 7-day window (newest record at/older than the
        // cutoff). If the lift has no history older than the window, fall back to the
        // earliest record so a recent gain (incl. the set just logged) still shows
        // instead of nothing.
        let baseline = records.first(where: { $0.createdAt <= cutoff }) ?? earliest

        let gain = latest.value - baseline.value
        return gain > 0.1 ? gain : nil
    }

    // MARK: - Helpers

    private func triggerFieldHighlights() {
        withAnimation(.easeIn(duration: 0.15)) {
            if !weightIsSet { weightHighlight = true }
            if !repsIsSet { repsHighlight = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.4)) {
                weightHighlight = false
                repsHighlight = false
            }
        }
    }

    private func triggerLogSetFlash(markFieldsSet: Bool = true) {
        if markFieldsSet {
            weightIsSet = true
            repsIsSet = true
        }
        withAnimation(.easeIn(duration: 0.15)) {
            logSetFlashActive = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.4)) {
                logSetFlashActive = false
            }
        }
    }

    private func effortColor(for key: String) -> Color {
        switch key {
        case "easy": return .setEasy
        case "moderate": return .setModerate
        case "hard": return .setHard
        case "redline": return .setNearMax
        case "pr": return .appAccent
        default: return .white.opacity(0.3)
        }
    }

    /// Single source of truth lives on `SetPlan` so this and the set-plan catalog
    /// legend can't drift apart again.
    private func effortLabel(for key: String) -> String {
        SetPlan.effortLabel(for: key)
    }

    private func shortEffortLabel(for key: String) -> String {
        switch key {
        case "easy": return "easy"
        case "moderate": return "mod"
        case "hard": return "hard"
        case "redline": return "near max"
        case "pr": return "progress"
        default: return String(key.prefix(4))
        }
    }

    // MARK: - Active Group Persistence (UserDefaults, 6-hour expiry)

    private static func restoredActiveGroupId() -> UUID {
        let defaults = UserDefaults.standard
        guard let idString = defaults.string(forKey: "activeGroupId"),
              let id = UUID(uuidString: idString),
              let timestamp = defaults.object(forKey: "activeGroupIdTimestamp") as? Date,
              Date().timeIntervalSince(timestamp) < 6 * 3600,
              id != ExerciseGroup.tierExercisesId
        else { return ExerciseGroup.tierExercisesId }
        return id
    }

    private func persistActiveGroup(_ id: UUID) {
        let defaults = UserDefaults.standard
        if id == ExerciseGroup.tierExercisesId {
            defaults.removeObject(forKey: "activeGroupId")
            defaults.removeObject(forKey: "activeGroupIdTimestamp")
        } else {
            defaults.set(id.uuidString, forKey: "activeGroupId")
            defaults.set(Date(), forKey: "activeGroupIdTimestamp")
        }
    }

    // MARK: - Active Exercise Persistence (UserDefaults, 6-hour expiry)

    private static func restoredActiveExerciseId() -> UUID? {
        let defaults = UserDefaults.standard
        guard let idString = defaults.string(forKey: "activeExerciseId"),
              let id = UUID(uuidString: idString),
              let timestamp = defaults.object(forKey: "activeExerciseIdTimestamp") as? Date,
              Date().timeIntervalSince(timestamp) < 6 * 3600
        else { return nil }
        return id
    }

    private func persistActiveExercise(_ id: UUID?) {
        let defaults = UserDefaults.standard
        if let id {
            defaults.set(id.uuidString, forKey: "activeExerciseId")
            defaults.set(Date(), forKey: "activeExerciseIdTimestamp")
        } else {
            defaults.removeObject(forKey: "activeExerciseId")
            defaults.removeObject(forKey: "activeExerciseIdTimestamp")
        }
    }
}

// MARK: - Animated Viewfinder Indicator

private struct ViewfinderPulse: View {
    var size: CGFloat = 16
    var color: Color = .white.opacity(0.35)
    @State private var isAnimating = false
    @State private var isActive = true

    var body: some View {
        Image(systemName: "viewfinder.rectangular")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
            .scaleEffect(isAnimating ? 1.15 : 1.0)
            .opacity(isAnimating ? 0.8 : 0.5)
            .padding(.bottom, 2)
            .onAppear {
                isActive = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if isActive { animate() }
                }
            }
            .onDisappear {
                isActive = false
                isAnimating = false
            }
    }

    private func animate() {
        guard isActive else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            isAnimating = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard isActive else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                isAnimating = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                guard isActive else { return }
                animate()
            }
        }
    }
}

// MARK: - Sets Info Overlay

/// Centered modal-style explainer for the unlocked-state Sets widget. Built
/// as an `.overlay` on the parent view (not a `.sheet`/`.fullScreenCover`)
/// so it floats at a fixed size, no detent dragging, no slide-from-bottom
/// takeover. Covers e1RM, the five effort categories with left-aligned
/// percent-of-e1RM ranges, how to change the active plan, and what each
/// control on the widget does.
private struct SetsInfoOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack {
                    Text("Sets Guide")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider().background(.white.opacity(0.08))

                ScrollView {
                    SetsGuideContent()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }
            .frame(maxWidth: 340)
            .frame(maxHeight: 560)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 22, x: 0, y: 10)
            .padding(.horizontal, 24)
        }
    }
}

/// Reusable guide body. Used both inside the modal `SetsInfoOverlay` and
/// inline when the Sets widget itself is expanded via its bottom chevron.
/// No header, no scroll wrapper — the caller provides whatever chrome it
/// wants.
private struct SetsGuideContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // e1RM
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("ESTIMATED 1RM (e1RM)")
                (
                    run("Your ") + term("e1RM")
                    + run(" is an estimate of the heaviest weight you could lift for a single rep. It increases each time you log a ")
                    + term("Progress Set") + run(".")
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            // Baseline set
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("YOUR BASELINE SET")
                (
                    run("The first set you log for an exercise is its baseline. Right after you log it we ask how hard it felt. That answer is what determines your starting ")
                    + term("e1RM")
                    + run(". The suggestions the app makes afterwards build from that starting point.")
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            // Effort categories
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("EFFORT CATEGORIES")
                (
                    run("Every set falls into one of five categories based on what percent of your ")
                    + term("e1RM")
                    + run(" you're lifting. Easier sets build volume; harder sets push your ceiling.")
                )
                .fixedSize(horizontal: false, vertical: true)

                SetsEffortRangesCard()
                    .padding(.top, 2)
            }

            // Logging a Progress Set
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("LOGGING A PROGRESS SET")
                (
                    run("A ") + term("Progress Set") + run(" raises your ") + term("e1RM")
                    + run(". The ") + term("e1RM Progress Options")
                    + run(" suggest weight and rep combinations that will do exactly that. Pick an option with a smaller gain to inch forward, or a larger one when you're ready to push.")
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            // Set plan
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("YOUR SET PLAN")
                (
                    Text("The rows on the Sets widget come from your active plan, one row per set, in order. To switch plans, tap the plan chip under the date heading (the one with the ")
                    + Text(Image(systemName: "chevron.down"))
                    + Text("). That opens the plan hub where you can pick a different one.")
                )
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            }

            // Widget controls
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("WIDGET CONTROLS")
                VStack(alignment: .leading, spacing: 8) {
                    controlRow(icon: "chevron.left.chevron.right", text: "Tap the left chevron to view a previous session. The right chevron only activates while you're already in the past, to step forward toward today.")
                    controlRow(icon: "list.bullet.rectangle", text: "Tap the plan chip to change your active plan.")
                    controlRow(icon: "arrow.down.circle", text: "Loaded means those suggested values are already in the inputs. Change either one and it goes back to Tap to load.")
                    controlRow(icon: "hand.tap", text: "Tap a set row to load values into the inputs. A logged row copies the weight and reps you actually lifted; an upcoming row loads the suggestion for its effort level.")
                    controlRow(icon: "trash", text: "Long-press a logged set row to delete it.")
                }
            }

            // Tip card
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.appAccent)
                    .padding(.top, 1)
                Text("Match the target effort for each set by choosing weights and reps that hit your target percent of e1RM.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.appAccent.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Color.appAccent.opacity(0.85))
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Plain body run, for paragraphs assembled by concatenation. Colour is set on
    /// the run itself rather than via an outer `.foregroundStyle`, so a `term` run
    /// in the same paragraph can't be overridden by it.
    private func run(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.8))
    }

    /// Key app vocabulary — e1RM, Progress Set — tinted amber so it reads as a named
    /// concept rather than prose.
    private func term(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.appAccent)
    }

    private func controlRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.appAccent.opacity(0.85))
                .frame(width: 22, alignment: .center)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Centered rounded-rect card listing the 5 effort categories with their
/// percent-of-e1RM ranges. Used by both the full `SetsGuideContent` and the
/// inline expansion on the Sets widget itself.
private struct SetsEffortRangesCard: View {
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                SetsEffortRow(color: .setEasy, label: "Easy", range: "< 70% e1RM")
                SetsEffortRow(color: .setModerate, label: "Moderate", range: "70–82% e1RM")
                SetsEffortRow(color: .setHard, label: "Hard", range: "82–92% e1RM")
                SetsEffortRow(color: .setNearMax, label: "Near Max", range: "92–100% e1RM")
                SetsEffortRow(color: .appAccent, label: "Progress", range: "> 100% e1RM")
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            Spacer(minLength: 0)
        }
    }
}

/// Effort row inside the info overlay. Label gets a fixed-width column so
/// every range starts at the same X. No trailing Spacer — the row stays
/// intrinsic-width so the parent can center the whole group.
private struct SetsEffortRow: View {
    let color: Color
    let label: String
    let range: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 80, alignment: .leading)
            Text(range)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
