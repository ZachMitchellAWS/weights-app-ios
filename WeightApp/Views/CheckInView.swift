import SwiftUI
import SwiftData

struct CheckInView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Exercise> { !$0.deleted }, sort: \Exercise.createdAt) private var exercises: [Exercise]
    @Query private var userPropertiesItems: [UserProperties]
    @Query(filter: #Predicate<Estimated1RM> { !$0.deleted }, sort: \Estimated1RM.createdAt) private var allEstimated1RM: [Estimated1RM]
    @Query(filter: #Predicate<SetPlan> { !$0.deleted }) private var allTemplates: [SetPlan]
    @Query(filter: #Predicate<ExerciseGroup> { !$0.deleted }) private var allGroups: [ExerciseGroup]
    @Query private var entitlementRecords: [EntitlementGrant]

    @ObservedObject var selectedSetData: SelectedSetData
    @Binding var selectedTab: Int

    // MARK: - State

    @State private var selectedLiftIndex: Int = 0
    @State private var viewingDate = Calendar.current.startOfDay(for: Date())
    @State private var setsForExercise: [LiftSet] = []
    @State private var estimated1RMsForExercise: [Estimated1RM] = []
    @State private var weight: Double = 45.0
    @State private var reps: Int = 5
    @State private var showAccessories = false
    @State private var selectedAccessoryId: UUID? = nil
    @State private var isAccessoryMode = false
    @State private var showHub = false
    @State private var hubSection: HubSection = .exercises
    @State private var hubDeepLinkExerciseId: UUID? = nil
    @State private var hubSelectedExerciseId: UUID? = nil
    @State private var activeGroupId: UUID = ExerciseGroup.tierExercisesId

    // Weight/Reps picker state
    @State private var showWeightPicker = false
    @State private var showRepsPicker = false
    @State private var calculatorTokens: [String] = []
    @State private var currentCalcInput: String = ""
    @State private var repsInput: String = ""

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
    @State private var weightIsSet: Bool = true
    @State private var repsIsSet: Bool = true
    @State private var weightHighlight: Bool = false
    @State private var repsHighlight: Bool = false

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

    private var strengthTierResult: TrendsCalculator.StrengthTierResult {
        TrendsCalculator.strengthTierAssessment(
            from: allEstimated1RM,
            bodyweight: bodyweight,
            biologicalSex: biologicalSex
        )
    }

    private var latestE1RMs: [UUID: Double] {
        let groupIds = Set(activeGroupExercises.map(\.id))
        let grouped = Dictionary(grouping: allEstimated1RM.filter { rec in
            guard let eid = rec.exercise?.id else { return false }
            return groupIds.contains(eid)
        }) { $0.exercise!.id }

        var result: [UUID: Double] = [:]
        for (exerciseId, records) in grouped {
            if let mostRecent = records.max(by: { $0.createdAt < $1.createdAt }) {
                result[exerciseId] = mostRecent.value
            }
        }
        return result
    }

    private var lastTrainedDates: [UUID: Date] {
        let groupIds = Set(activeGroupExercises.map(\.id))
        let grouped = Dictionary(grouping: allEstimated1RM.filter { rec in
            guard let eid = rec.exercise?.id else { return false }
            return groupIds.contains(eid)
        }) { $0.exercise!.id }

        var result: [UUID: Date] = [:]
        for (exerciseId, records) in grouped {
            if let mostRecent = records.max(by: { $0.createdAt < $1.createdAt }) {
                result[exerciseId] = mostRecent.createdAt
            }
        }
        return result
    }

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
        if let latest = estimated1RMsForExercise.first {
            return latest.value
        }
        return 0
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
            $0.reps >= userProperties.minReps && $0.reps <= userProperties.maxReps
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
        return allTemplates.first(where: { $0.id == planId })
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    strengthHeader
                    groupSelector
                    focusedLiftPanel
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
                        if case .intro = tierJourneyMode {
                            hasSeenTierIntro = true
                        }
                        suppressTierDisplay = false
                        withAnimation(.easeOut(duration: 0.18)) {
                            showTierJourneyOverlay = false
                        }
                    },
                    onNavigateToExercise: { exerciseId in
                        navigateToTierExercise(exerciseId)
                    },
                    onNavigateToStrength: {
                        selectedSetData.pendingTrendsTab = .strength
                        selectedTab = 0
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(21)
            }
        }
        .onAppear {
            // Show tier journey intro for fresh users
            if !hasSeenTierIntro,
               strengthTierResult.overallTier == .none,
               strengthTierResult.exerciseTiers.allSatisfy({ $0.e1rm == nil }) {
                tierJourneyMode = .intro
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    showTierJourneyOverlay = true
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
            loadDataForSelectedLift()
        }
        .onChange(of: selectedLiftIndex) { _, _ in
            isAccessoryMode = false
            selectedAccessoryId = nil
            viewingDate = actualToday
            loadDataForSelectedLift()
        }
        .onChange(of: activeGroupId) { _, _ in
            selectedLiftIndex = 0
            isAccessoryMode = false
            selectedAccessoryId = nil
            loadDataForSelectedLift()
        }
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
    }

    // MARK: - Phase 1: Strength Header

    private var strengthHeader: some View {
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
                        .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
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

                    ForEach(allGroups.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.groupId) { group in
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
                        let displayName = shortDisplayName(for: exercise.name)

                        Button {
                            hapticFeedback.impactOccurred()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedLiftIndex = index
                                isAccessoryMode = false
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Spacer()

                                Image(exercise.icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(isSelected ? highlightColor : .white.opacity(0.5))

                                Text(displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isSelected ? highlightColor.opacity(0.9) : .white.opacity(0.45))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)

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
                                    Spacer()
                                        .frame(height: 18)
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
                        }
                        .buttonStyle(.plain)
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

        let e1rm = isAccessoryMode ? current1RM : (latestE1RMs[groupExercise?.id ?? UUID()] ?? 0)
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
                    .foregroundStyle(isAccessoryMode ? .white : (isNoneState ? Color.appAccent : (e1rm > 0 ? (tier?.color ?? .white) : Color.appAccent)))

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
                            Text("+\(gain, specifier: "%.1f")")
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

    // MARK: - Sets Widget

    private func intensityColor(for set: LiftSet) -> Color {
        // Use the e1RM that existed *before* this set was logged (same as LegacyCheckInView)
        let priorE1RM = estimated1RMsForExercise
            .filter { $0.createdAt < set.createdAt }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        let currentMax = priorE1RM?.value ?? 0

        let estimated = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)

        if set.weight == 0 { return .white }

        let isPR = (estimated - currentMax) > 0.0001 && currentMax > 0
        if isPR { return .setPR }

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
        if setsForExercise.isEmpty && isViewingToday {
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
                LegendItem(color: .setPR, label: "e1RM ↑")
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
                        Text("±\(incStr) \(userProperties.preferredWeightUnit.label) · \(userProperties.minReps)-\(userProperties.maxReps) reps")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    Button {
                        hapticFeedback.impactOccurred()
                        showExpandedProgressOptions = true
                    } label: {
                        Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
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
                    get: { userProperties.minReps },
                    set: { userProperties.minReps = $0 }
                ),
                maxReps: Binding(
                    get: { userProperties.maxReps },
                    set: { userProperties.maxReps = $0 }
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
            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.appAccent.opacity(0.4))

                Text("Log a set to unlock suggestions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
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
        let props = userProperties
        let min = props.minReps
        let max = props.maxReps
        let easyMin = props.easyMinReps
        let easyMax = props.easyMaxReps
        let modMin = props.moderateMinReps
        let modMax = props.moderateMaxReps
        let hardMin = props.hardMinReps
        let hardMax = props.hardMaxReps
        try? modelContext.save()
        repRangeDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await SyncService.shared.updateAllRepRanges(
                minReps: min, maxReps: max,
                easyMinReps: easyMin, easyMaxReps: easyMax,
                moderateMinReps: modMin, moderateMaxReps: modMax,
                hardMinReps: hardMin, hardMaxReps: hardMax
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
        }
    }

    private func handleRepsInput(_ digit: String) {
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
        let props = userProperties
        let macroWeights = OneRMCalculator.efficientPlateWeights(loadType: loadType)

        struct TierConfig {
            let targets: [Double]
            let bounds: ClosedRange<Double>
            let repRange: ClosedRange<Int>
        }

        let tiers: [TierConfig] = [
            TierConfig(targets: [0.55, 0.60, 0.65], bounds: 0...70, repRange: props.easyMinReps...props.easyMaxReps),
            TierConfig(targets: [0.73, 0.76, 0.79], bounds: 70...82, repRange: props.moderateMinReps...props.moderateMaxReps),
            TierConfig(targets: [0.84, 0.87, 0.90], bounds: 82...92, repRange: props.hardMinReps...props.hardMaxReps),
        ]

        var picks: [(weight: Double, reps: Int)] = []

        for tier in tiers {
            var results = OneRMCalculator.effortSuggestions(
                current1RM: e1rm,
                targetPercent1RMs: tier.targets,
                loadType: loadType,
                repRange: tier.repRange
            )
            results = results.filter { tier.bounds.contains($0.percent1RM) }

            // Find lastSetMatch: newest set whose %e1RM falls in bounds
            var lastSetMatch: (weight: Double, reps: Int)? = nil
            for set in setsForExercise.reversed() {
                let pct = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps) / e1rm * 100.0
                if tier.bounds.contains(pct) {
                    lastSetMatch = (set.weight, set.reps)
                    break
                }
            }

            // If lastSetMatch exists and not already in results, append it
            if let match = lastSetMatch {
                let alreadyPresent = results.contains { $0.weight == match.weight && $0.reps == match.reps }
                if !alreadyPresent {
                    let pct = OneRMCalculator.estimate1RM(weight: match.weight, reps: match.reps) / e1rm * 100.0
                    results.append(OneRMCalculator.EffortSuggestion(reps: match.reps, weight: match.weight, percent1RM: pct))
                }
            }

            // Sort by weight ascending
            results.sort { $0.weight < $1.weight }

            // Promote macro-plate-friendly weights to top
            let macroFirst = results.filter { macroWeights.contains($0.weight) } + results.filter { !macroWeights.contains($0.weight) }

            // Promote lastSetMatch to position 0 if it exists
            var final = macroFirst
            if let match = lastSetMatch, let idx = final.firstIndex(where: { $0.weight == match.weight && $0.reps == match.reps }) {
                let item = final.remove(at: idx)
                final.insert(item, at: 0)
            }

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
            let minReps = userProperties.minReps
            let maxReps = userProperties.maxReps
            let filtered = suggestions.filter { $0.reps >= minReps && $0.reps <= maxReps }

            if filtered.count >= 2 {
                let sorted = filtered.sorted(by: { $0.delta < $1.delta })
                let conservative = sorted.first!
                let stretch = sorted.last!
                let midIndex = sorted.count / 2
                let advancement = sorted[midIndex]

                let cards: [(label: String, subtitle: String, suggestion: OneRMCalculator.Suggestion, color: Color)] = [
                    ("Conservative Win", "Solid volume, guaranteed gain", conservative, .setEasy),
                    ("Advancement", "Push into new territory", advancement, .setModerate),
                    ("Stretch Attempt", "Go for a major PR", stretch, .setPR),
                ]

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
        let increment = ex?.effectiveWeightIncrement ?? 5.0
        let projected = OneRMCalculator.estimate1RM(weight: weight, reps: reps)
        let delta = current1RM > 0 ? projected - current1RM : 0.0

        return VStack(spacing: 6) {
            // Intensity label + percent of e1RM
            if current1RM > 0 {
                let percent = projected / current1RM
                let isProgress = (projected - current1RM) > 0.0001
                let bucket = TrendsCalculator.IntensityBucket.from(percent1RM: percent)
                let bucketColor: Color = {
                    if isProgress { return .setPR }
                    switch bucket {
                    case .easy: return .setEasy
                    case .moderate: return .setModerate
                    case .hard: return .setHard
                    case .redline: return .setNearMax
                    case .pr: return .setPR
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
                                Text("\(displayW == floor(displayW) ? "\(Int(displayW))" : String(format: "%.1f", displayW))")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            } else {
                                Text("–\u{2009}–")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            Text(userProperties.preferredWeightUnit.label)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(width: 56)
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
                                Text("–\u{2009}–")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            Text("reps")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(width: 36)
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
                    selectedSetData.pendingScrollToStrengthTop = true
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

        set.deleted = true

        var estimated1RMId: UUID? = nil
        if let associated1RM = allEstimated1RM.first(where: { $0.setId == setId }) {
            associated1RM.deleted = true
            estimated1RMId = associated1RM.id
        }

        try? modelContext.save()

        Task {
            await SyncService.shared.deleteLiftSet(setId)
            if let e1rmId = estimated1RMId {
                await SyncService.shared.deleteEstimated1RM(estimated1RMId: e1rmId, liftSetId: setId)
            }
        }

        loadDataForSelectedLift()
    }

    // MARK: - Actions

    private func loadDataForSelectedLift() {
        guard let exercise = selectedExercise else { return }
        loadDataForExercise(exercise.id)
    }

    private func loadDataForExercise(_ exerciseId: UUID) {
        let setDescriptor = FetchDescriptor<LiftSet>(
            predicate: #Predicate { !$0.deleted && $0.exercise?.id == exerciseId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        setsForExercise = (try? modelContext.fetch(setDescriptor)) ?? []

        let e1rmDescriptor = FetchDescriptor<Estimated1RM>(
            predicate: #Predicate { !$0.deleted && $0.exercise?.id == exerciseId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        estimated1RMsForExercise = (try? modelContext.fetch(e1rmDescriptor)) ?? []

        // Set initial weight/reps based on easy effort suggestions
        if current1RM > 0, let ex = selectedExercise {
            let loadType = ex.exerciseLoadType
            let repRange = EffortMode.easy.repRange(from: userProperties)
            let targets = EffortMode.easy.targetPercent1RMs ?? [0.55, 0.60, 0.65]
            let bounds = EffortMode.easy.percent1RMBounds ?? (0...70)
            var results = OneRMCalculator.effortSuggestions(
                current1RM: current1RM,
                targetPercent1RMs: targets,
                loadType: loadType,
                repRange: repRange
            )
            results = results.filter { bounds.contains($0.percent1RM) }
            if let first = results.first {
                weight = first.weight
                reps = first.reps
            } else {
                weight = 45
                reps = 8
            }
            weightIsSet = true
            repsIsSet = true
        } else {
            // No historical data — mark as unset so log bar shows dashes
            weight = 45
            reps = 5
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

        let isFirstWeightedSet = !setsForExercise.contains(where: { $0.weight > 0 }) && weight > 0

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

        // Suppress tier display before model write to prevent spoiler during overlay
        if isFirstTierLog {
            suppressTierDisplay = true
        }

        modelContext.insert(estimated)
        try? modelContext.save()

        // Sync to backend
        Task {
            await SyncService.shared.syncLiftSet(set, isPremiumOnClient: isPremium)
            await SyncService.shared.syncEstimated1RM(estimated)
        }

        // First weighted set: defer data refresh until calibration is applied
        if isFirstWeightedSet {
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

        // Capture logged values before refresh (which resets weight/reps)
        let loggedWeight = weight
        let loggedReps = reps

        // Refresh data
        loadDataForExercise(ex.id)

        // Restore the weight/reps the user had selected
        weight = loggedWeight
        reps = loggedReps

        // Redirect tier journey milestones (first log of any tier exercise during journey)
        if isFirstTierLog {
            let tierResult = strengthTierResult
            let loggedAfterThis = tierResult.exerciseTiers.filter { $0.e1rm != nil }.count
            if loggedAfterThis >= 5 {
                tierJourneyMode = .completion(tier: tierResult.overallTier)
            } else {
                tierJourneyMode = .progress(justLoggedId: ex.id)
            }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                showTierJourneyOverlay = true
            }
            return
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
            if loggedWeight == 0 {
                overlayIntensityColor = .white
                overlayIntensityLabel = "Bodyweight"
            } else {
                let rawPercent = before > 0 ? OneRMCalculator.estimate1RM(weight: loggedWeight, reps: loggedReps) / before : 0
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
            overlayIntensityColor = .setPR
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

        // Suppress tier display before model write to prevent spoiler during overlay
        // In calibration path, isMilestone with newTier > .none means first tier log
        if isMilestone {
            suppressTierDisplay = true
        }

        estimated.value = calibratedValue

        Task {
            await SyncService.shared.syncEstimated1RM(estimated)
        }

        if let exId = set.exercise?.id {
            let loggedWeight = weight
            let loggedReps = reps
            loadDataForExercise(exId)
            weight = loggedWeight
            reps = loggedReps
        }

        // Redirect tier journey milestones (first log of any tier exercise during journey)
        if isMilestone, let exerciseForJourney = set.exercise {
            let tierResult = strengthTierResult
            let loggedAfterThis = tierResult.exerciseTiers.filter { $0.e1rm != nil }.count
            if loggedAfterThis >= 5 {
                tierJourneyMode = .completion(tier: tierResult.overallTier)
            } else {
                tierJourneyMode = .progress(justLoggedId: exerciseForJourney.id)
            }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                showTierJourneyOverlay = true
            }
            pendingCalibrationSet = nil
            pendingCalibrationEstimated = nil
            return
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
            }
        } else {
            if let index = activeGroupExercises.firstIndex(where: { $0.id == exerciseId }) {
                selectedLiftIndex = index
            }
        }
    }

    private func shortDisplayName(for name: String) -> String {
        switch name {
        case "Overhead Press": return "OH Press"
        case "Bench Press": return "Bench"
        case "Barbell Row": return "Rows"
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
        let records = allEstimated1RM.filter { $0.exercise?.id == exerciseId }
        guard let latest = records.max(by: { $0.createdAt < $1.createdAt }) else { return nil }

        let oldRecords = records.filter { $0.createdAt <= cutoff }
        guard let baseline = oldRecords.max(by: { $0.createdAt < $1.createdAt }) else { return nil }

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
        case "pr": return .setPR
        default: return .white.opacity(0.3)
        }
    }

    private func effortLabel(for key: String) -> String {
        switch key {
        case "easy": return "Easy"
        case "moderate": return "Moderate"
        case "hard": return "Hard"
        case "pr": return "Progress"
        default: return key.capitalized
        }
    }

    private func shortEffortLabel(for key: String) -> String {
        switch key {
        case "easy": return "easy"
        case "moderate": return "mod"
        case "hard": return "hard"
        case "pr": return "e1RM ↑"
        default: return String(key.prefix(4))
        }
    }
}
