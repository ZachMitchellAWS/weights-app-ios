import SwiftUI
import SwiftData
import Sentry

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

    // Tier journey overlay state
    @AppStorage("hasSeenTierIntro") private var hasSeenTierIntro = false
    @State private var showTierJourneyOverlay = false
    @State private var tierJourneyMode: TierJourneyMode = .intro
    @State private var suppressTierDisplay = false

    // Baseline calibration state
    @State private var pendingCalibrationSet: LiftSet? = nil
    @State private var pendingCalibrationEstimated: Estimated1RM? = nil
    @State private var showCalibrationAlert = false

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
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

    private var nextFocus: TrendsCalculator.FundamentalExercise? {
        TrendsCalculator.nextFocusExercise(
            exerciseTiers: strengthTierResult.exerciseTiers,
            lastTrainedDates: lastTrainedDates,
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
            }
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
        .task(id: "\(exercises.compactMap(\.currentE1RMLocalCache).reduce(0, +))-\(activeGroupId)-\(allEstimated1RM.count)") {
            strengthTierResult = TrendsCalculator.strengthTierAssessment(
                from: allEstimated1RM,
                exercises: exercises,
                bodyweight: bodyweight,
                biologicalSex: biologicalSex
            )

            var e1rms: [UUID: Double] = [:]
            var trainedDates: [UUID: Date] = [:]
            for ex in activeGroupExercises {
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
        }
        .onAppear {
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

            // In none state, default to first unlogged exercise
            if strengthTierResult.overallTier == .none,
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
            Button("Redline") { applyCalibration(effort: .progress) }
        } message: {
            Text("This helps estimate your 1RM for better suggestions.")
        }
        .fullScreenCover(isPresented: $showE1RMUpsell) {
            UpsellView(initialPage: 3) { _ in showE1RMUpsell = false }
        }
    }

    // MARK: - Phase 1: Strength Header

    private var strengthHeader: some View {
        let tier: StrengthTier = (suppressTierDisplay || showCalibrationAlert) ? .none : strengthTierResult.overallTier
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
                        Text(shortDisplayName(for: focus.name))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
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
                            let ratio = e1rm / bodyweight
                            Text(String(format: "%.2f× BW", ratio))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            if !isNoneState, let nextTier = tier?.next {
                                HStack(spacing: 0) {
                                    Text("\(Int(userProperties.preferredWeightUnit.fromLbs(distance))) \(userProperties.preferredWeightUnit.label) to ")
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
        case .pr: return .setNearMax // not a true PR — downgrade to redline
        case .redline: return .setNearMax
        case .hard: return .setHard
        case .moderate: return .setModerate
        case .easy: return .setEasy
        }
    }

    private var setsWidget: some View {
        VStack(spacing: 8) {
            // Header — outside the card background
            HStack {
                Text("SETS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1)
                Spacer()
            }
            .padding(.leading, 4)

            setsWidgetCard
        }
    }

    @ViewBuilder
    private var setsWidgetCard: some View {
        // Don't show "log first set" if exercise has e1RM data — sets just haven't loaded yet
        let hasE1RM = selectedExercise?.currentE1RMLocalCache != nil
        if setsForExercise.isEmpty && isViewingToday && !hasE1RM {
            setsWidgetEmptyState
        } else {
            setsWidgetContent
        }
    }

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

            // Set bars — fixed height region so widget doesn't shift across states
            let sortedSets = todaysSets.sorted(by: { $0.createdAt < $1.createdAt })

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
                                    if index < sequence.count {
                                        let effort = sequence[index]
                                        if let shortcuts = effortShortcuts {
                                            switch effort {
                                            case "easy":
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                weight = shortcuts.easy.weight
                                                reps = shortcuts.easy.reps
                                                triggerLogSetFlash()
                                                tappedTileIndex = index
                                            case "moderate":
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                weight = shortcuts.moderate.weight
                                                reps = shortcuts.moderate.reps
                                                triggerLogSetFlash()
                                                tappedTileIndex = index
                                            case "hard":
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                weight = shortcuts.hard.weight
                                                reps = shortcuts.hard.reps
                                                triggerLogSetFlash()
                                                tappedTileIndex = index
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
                                            default:
                                                break
                                            }
                                            if tappedTileIndex == index {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                                    tappedTileIndex = nil
                                                }
                                            }
                                        }
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

            // Intensity legend
            Divider()
                .background(.white.opacity(0.1))

            HStack(spacing: 10) {
                LegendItem(color: .setEasy, label: "Easy")
                LegendItem(color: .setModerate, label: "Moderate")
                LegendItem(color: .setHard, label: "Hard")
                LegendItem(color: .setNearMax, label: "Redline")
                LegendItem(color: .appAccent, label: "e1RM ↑")
            }
        }
        .padding(14)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Phase 3: e1RM Progress Options

    private var progressOptionsWidget: some View {
        VStack(spacing: 8) {
            // Header — outside the card
            HStack {
                Text("PROGRESS OPTIONS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1)

                Spacer()
            }
            .padding(.leading, 4)

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

                                Text("\(Int(userProperties.preferredWeightUnit.fromLbs(card.suggestion.weight))) × \(card.suggestion.reps)")
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
        let ex = selectedExercise
        // In kg mode, use 1.0 kg increments (≈2.2 lbs) for clean display values
        let increment = userProperties.preferredWeightUnit == .kg
            ? userProperties.preferredWeightUnit.toLbs(1.0)
            : (ex?.effectiveWeightIncrement ?? 2.5)
        let projected = OneRMCalculator.estimate1RM(weight: weight, reps: reps)
        return VStack(spacing: 6) {
            // Intensity label + percent of e1RM
            if current1RM > 0 {
                let percent = projected / current1RM
                let isProgress = (projected - current1RM) > 0.0001
                let bucket = TrendsCalculator.IntensityBucket.from(percent1RM: percent)
                let bucketColor: Color = {
                    if isProgress { return .appAccent }
                    switch bucket {
                    case .easy: return .setEasy
                    case .moderate: return .setModerate
                    case .hard: return .setHard
                    case .redline: return .setNearMax
                    case .pr: return .appAccent
                    }
                }()
                let bucketLabel = isProgress ? "Progress" : bucket.rawValue

                HStack(spacing: 0) {
                    // Left half: intensity info
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
                        Text("\(String(format: "%.2f", percent * 100))% e1RM")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("|")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.2))

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
                        weight = max(0, weight - increment)
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
                        weight += increment
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
                        milestoneTargetLabel = "\(Int(userProperties.preferredWeightUnit.fromLbs(threshold.min))) \(userProperties.preferredWeightUnit.label)"
                    } else {
                        let m = threshold.min
                        milestoneTargetLabel = m == floor(m) ? "\(Int(m))× BW" : "\(String(format: "%g", m))× BW"
                    }
                }
            }
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
                tierToUnlock = tierResult.overallTier
                if let props = userPropertiesItems.first, !props.hasMetStrengthTierConditions {
                    props.hasMetStrengthTierConditions = true
                    try? modelContext.save()
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

        // Overall tier-up detection (non-journey milestone that bumps overall tier)
        if isMilestone {
            let newOverallTier = strengthTierResult.overallTier
            if newOverallTier > previousOverallTier && newOverallTier > .none {
                tierJourneyMode = .completion(tier: newOverallTier)
                tierToUnlock = newOverallTier
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
                case .pr, .redline: overlayIntensityColor = .setNearMax
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

    private func applyCalibration(effort: EffortMode) {
        guard let set = pendingCalibrationSet,
              let estimated = pendingCalibrationEstimated,
              let fraction = effort.calibrationMidpoint else {
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
                        milestoneTargetLabel = "\(Int(userProperties.preferredWeightUnit.fromLbs(threshold.min))) \(userProperties.preferredWeightUnit.label)"
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
                calibrationTierToUnlock = tierResult.overallTier
                if let props = userPropertiesItems.first, !props.hasMetStrengthTierConditions {
                    props.hasMetStrengthTierConditions = true
                    try? modelContext.save()
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

        // Overall tier-up detection (non-journey milestone that bumps overall tier)
        if isMilestone {
            let newOverallTier = strengthTierResult.overallTier
            if newOverallTier > previousOverallTier && newOverallTier > .none {
                tierJourneyMode = .completion(tier: newOverallTier)
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
            overlayIntensityColor = effort == .progress ? .setNearMax : effort.tileColor
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
        guard let latest = records.first else { return nil }

        let oldRecords = records.filter { $0.createdAt <= cutoff }
        guard let baseline = oldRecords.first else { return nil }

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

    private func effortLabel(for key: String) -> String {
        switch key {
        case "easy": return "Easy"
        case "moderate": return "Moderate"
        case "hard": return "Hard"
        case "redline": return "Redline"
        case "pr": return "Progress"
        default: return key.capitalized
        }
    }

    private func shortEffortLabel(for key: String) -> String {
        switch key {
        case "easy": return "easy"
        case "moderate": return "mod"
        case "hard": return "hard"
        case "redline": return "redline"
        case "pr": return "e1RM ↑"
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
