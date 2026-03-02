import SwiftUI
import SwiftData
import Charts

struct CheckInView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var today = Calendar.current.startOfDay(for: Date())

    @Query(filter: #Predicate<Exercise> { !$0.deleted }, sort: \Exercise.createdAt) private var exercises: [Exercise]
    @Query private var userPropertiesItems: [UserProperties]
    @Query(filter: #Predicate<WorkoutSplit> { !$0.deleted }) private var allSplits: [WorkoutSplit]
    @Query(filter: #Predicate<SetPlan> { !$0.deleted }) private var allTemplates: [SetPlan]

    @State private var setsForExercise: [LiftSet] = []
    @State private var estimated1RMsForExercise: [Estimated1RM] = []
    @State private var todaySetCounts: [UUID: Int] = [:]

    @ObservedObject var selectedSetData: SelectedSetData
    var initialExerciseId: UUID? = nil

    @State private var selectedExercisesId: UUID?
    @State private var hasAppliedInitialExercise = false

    @State private var reps: Int = 8
    @State private var weight: Double = 20.0
    @State private var hasSetInitialValues = false
    @State private var hasSetWeight = false
    @State private var hasSetReps = false
    @State private var hasSelectedOption = false
    @State private var logSetFlash = false


    @State private var showSubmitOverlay = false
    @State private var overlayDidIncrease = false
    @State private var overlayDelta: Double = 0
    @State private var overlayNew1RM: Double = 0
    @State private var overlayIntensityColor: Color = .setEasy
    @State private var overlayIntensityLabel: String = "Easy"

    @State private var showWeightPicker = false
    @State private var weightInput: String = ""
    @State private var calculatorTokens: [String] = []  // Alternating numbers and operators
    @State private var currentCalcInput: String = ""    // Current number being typed
    @State private var showRepsPicker = false
    @State private var repsInput: String = ""
    @State private var showLogConfirmation = false
    @State private var weightDelta: Double = 5.0
    @State private var showHub = false
    @State private var hubSection: HubSection = .exercises
    @State private var hubDeepLinkExerciseId: UUID?
    @State private var selectedSquareId: UUID? = nil
    @State private var sessionScrollTarget: UUID? = nil
    @State private var showNoExercisesAlert = false
    @State private var isRetryingSync = false
    @State private var showIncrementSelection = false
    @State private var showExpandedProgressOptions = false
    @State private var showExerciseSelectedOverlay = false
    @State private var exerciseOverlayDismissTask: Task<Void, Never>?
    @State private var activeSplitId: UUID? = WorkoutSplitStore.activeSplitId()
    @State private var activeDayId: UUID? = WorkoutSplitStore.activeDayId()
    @State private var repRangeDebounceTask: Task<Void, Never>?
    @State private var showE1RMPopup = false
    @State private var showCalibrationAlert = false
    @State private var pendingCalibrationSet: LiftSet? = nil
    @State private var pendingCalibrationEstimated: Estimated1RM? = nil

    enum EffortMode: Int, CaseIterable {
        case easy = 0, moderate = 1, hard = 2, progress = 3

        var title: String {
            switch self {
            case .easy: return "Easy Options"
            case .moderate: return "Moderate Options"
            case .hard: return "Hard Options"
            case .progress: return "Progress Options"
            }
        }

        var chipLabel: String {
            switch self {
            case .easy: return "Easy Options"
            case .moderate: return "Moderate Options"
            case .hard: return "Hard Options"
            case .progress: return "e1RM Progress Options"
            }
        }

        var subtitle: String {
            switch self {
            case .easy: return "< 70% e1RM"
            case .moderate: return "70-82% e1RM"
            case .hard: return "82-92% e1RM"
            case .progress: return "Sets to ↑ e1RM"
            }
        }

        var targetPercent1RMs: [Double]? {
            switch self {
            case .easy: return [0.55, 0.60, 0.65]
            case .moderate: return [0.73, 0.76, 0.79]
            case .hard: return [0.84, 0.87, 0.90]
            case .progress: return nil
            }
        }

        func repRange(from props: UserProperties) -> ClosedRange<Int> {
            switch self {
            case .easy: return props.easyMinReps...props.easyMaxReps
            case .moderate: return props.moderateMinReps...props.moderateMaxReps
            case .hard: return props.hardMinReps...props.hardMaxReps
            case .progress: return props.minReps...props.maxReps
            }
        }

        /// The valid %1RM range for this effort category (values are percentages, e.g. 70 = 70%).
        /// Suggestions whose recalculated %1RM falls outside this range are filtered out.
        var percent1RMBounds: ClosedRange<Double>? {
            switch self {
            case .easy: return 0...70
            case .moderate: return 70...82
            case .hard: return 82...92
            case .progress: return nil
            }
        }

        var calibrationMidpoint: Double? {
            switch self {
            case .easy: return 0.60
            case .moderate: return 0.76
            case .hard: return 0.87
            case .progress: return 0.96
            }
        }

        var tileColor: Color {
            switch self {
            case .easy: return .setEasy
            case .moderate: return .setModerate
            case .hard: return .setHard
            case .progress: return .setPR
            }
        }

        var effortKey: String {
            switch self {
            case .easy: return "easy"
            case .moderate: return "moderate"
            case .hard: return "hard"
            case .progress: return "pr"
            }
        }

        static func from(effort: String) -> EffortMode {
            switch effort {
            case "easy": return .easy
            case "moderate": return .moderate
            case "hard": return .hard
            case "pr": return .progress
            default: return .easy
            }
        }
    }

    enum SortColumn {
        case weight, reps, est1RM, gain
    }
    enum EffortSortColumn {
        case weight, reps, percent1RM
    }
    @State private var effortMode: EffortMode? = nil
    @State private var selectedPlanTileIndex: Int? = nil
    @State private var highlightedPlanTileIndex: Int? = nil
    @State private var highlightDismissTask: Task<Void, Never>? = nil
    @State private var showExpandedEffortOptions = false
    @State private var sortColumn: SortColumn = .gain
    @State private var sortAscending: Bool = true
    @State private var columnHighlighted = false
    @State private var effortSortColumn: EffortSortColumn = .weight
    @State private var effortSortAscending: Bool = true
    @State private var effortColumnHighlighted = false
    @State private var effortSortUserModified: Bool = false
    @State private var weightColumnHighlighted = false
    @State private var cachedSetsWithPRInfo: [SetWithPR] = []

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    private let lastSelectedExerciseKey = "lastSelectedExerciseId"

    private var sequencedExercises: [Exercise] {
        guard let activeId = activeDayId,
              let split = activeSplit,
              let day = split.days.first(where: { $0.id == activeId }) else {
            return exercises
        }
        let exerciseMap = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let resolved = day.exerciseIds.compactMap { exerciseMap[$0] }
        return resolved.isEmpty ? exercises : resolved
    }

    private var activeSplit: WorkoutSplit? {
        guard let id = activeSplitId else { return nil }
        return allSplits.first(where: { $0.id == id })
    }

    private var daysForActiveSplit: [WorkoutDay] {
        guard let split = activeSplit else { return [] }
        return split.days
    }

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var availablePlates: [Double] {
        userProperties.availableChangePlates.sorted { $0 > $1 }
    }

    private var selectedExercises: Exercise? {
        guard let id = selectedExercisesId else { return nil }
        return exercises.first(where: { $0.id == id })
    }

    private var setsForSelected: [LiftSet] {
        setsForExercise
    }

    private func todaySetCount(for exercise: Exercise) -> Int {
        todaySetCounts[exercise.id] ?? 0
    }

    private var estimated1RMsForSelected: [Estimated1RM] {
        estimated1RMsForExercise
    }

    private var activeSetPlan: SetPlan? {
        guard let templateId = userProperties.activeSetPlanId else { return nil }
        return allTemplates.first(where: { $0.id == templateId })
    }

    private var displaySetPlan: [String] {
        activeSetPlan?.effortSequence ?? []
    }

    private var nextPlannedEffortMode: EffortMode? {
        let nextIndex = todaysSets.count
        guard nextIndex < displaySetPlan.count else { return nil }
        let effortKey = displaySetPlan[nextIndex]
        return EffortMode.from(effort: effortKey)
    }

    struct SetWithPR {
        let set: LiftSet
        let estimated1RM: Double
        let increases1RM: Bool
        let percent1RM: Double  // estimate1RM / currentMax ratio (0-1+), 0 for baselines
        let percentageOfCurrent: Double  // kept for chart bar heights
    }

    static func computeSetsWithPRInfo(for exercise: Exercise, from allSets: [LiftSet], estimated1RMs: [Estimated1RM]) -> [SetWithPR] {
        // Get all sets for this exercise in chronological order (oldest first)
        // Filter for valid sets (weight >= 0, reps >= 1)
        let sets = allSets
            .filter { $0.exercise?.id == exercise.id && $0.weight >= 0 && $0.reps >= 1 }
            .sorted { $0.createdAt < $1.createdAt }

        var result: [SetWithPR] = []
        var currentMax: Double = 0
        var maxReps: Int = 0

        for set in sets {
            let estimated = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)

            // Baseline sets: never flag as increases1RM, color by reported effort
            if set.isBaselineSet {
                let baselineEstimate = estimated1RMs.first(where: { $0.setId == set.id })?.value ?? estimated
                let percentage = baselineEstimate > 0 ? (estimated / baselineEstimate) * 100 : 100.0
                let pct1RM = baselineEstimate > 0 ? (estimated / baselineEstimate) * 100 : 0
                result.append(SetWithPR(set: set, estimated1RM: estimated, increases1RM: false, percent1RM: pct1RM, percentageOfCurrent: percentage))
                currentMax = max(currentMax, baselineEstimate)
                continue
            }

            // For 0-weight sets, PR is based on reps; otherwise based on 1RM
            let increases1RM: Bool
            if set.weight == 0 {
                increases1RM = set.reps > maxReps
            } else {
                increases1RM = estimated > currentMax
            }

            // Calculate percentage of current 1RM (before this set) — kept for chart bar heights
            let percentage = currentMax > 0 ? (estimated / currentMax) * 100 : 100.0

            // Compute percent1RM ratio for effort classification
            let percent1RM: Double = currentMax > 0 ? estimated / currentMax : 0

            if increases1RM {
                currentMax = max(currentMax, estimated)
                maxReps = max(maxReps, set.reps)
            }
            result.append(SetWithPR(set: set, estimated1RM: estimated, increases1RM: increases1RM, percent1RM: percent1RM, percentageOfCurrent: percentage))
        }

        return result
    }

    private func recomputeSetsWithPRInfo() {
        guard let ex = selectedExercises else {
            cachedSetsWithPRInfo = []
            return
        }
        // Defer computation so the UI can process animations and touches first
        Task { @MainActor in
            cachedSetsWithPRInfo = Self.computeSetsWithPRInfo(for: ex, from: setsForExercise, estimated1RMs: estimated1RMsForExercise)
        }
    }

    private func fetchDataForExercise(_ exerciseId: UUID) {
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
    }

    private func refreshTodaySetCounts() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        let descriptor = FetchDescriptor<LiftSet>(
            predicate: #Predicate { !$0.deleted && $0.createdAt >= todayStart && $0.createdAt < tomorrowStart }
        )
        let todaySets = (try? modelContext.fetch(descriptor)) ?? []

        var counts: [UUID: Int] = [:]
        for set in todaySets {
            if let exId = set.exercise?.id {
                counts[exId, default: 0] += 1
            }
        }
        todaySetCounts = counts
    }

    private var todayHasWeightedE1RMPR: Bool {
        let calendar = Calendar.current
        let today = self.today
        return cachedSetsWithPRInfo.contains { info in
            info.increases1RM &&
            info.set.weight > 0 &&
            calendar.isDate(info.set.createdAt, inSameDayAs: today)
        }
    }

    private var current1RM: Double {
        // Latest Estimated1RM value is the running max (each record stores the max at time of creation)
        if let latest = estimated1RMsForSelected.first {
            return latest.value
        }
        return OneRMCalculator.current1RM(from: setsForSelected)
    }

    private var lastPRPlusOneSuggestion: OneRMCalculator.Suggestion? {
        guard let lastPR = cachedSetsWithPRInfo.last(where: { $0.increases1RM }),
              lastPR.set.weight > 0 else { return nil }
        let newReps = lastPR.set.reps + 1
        guard newReps >= userProperties.minReps,
              newReps <= userProperties.maxReps else { return nil }
        let projected = OneRMCalculator.estimate1RM(weight: lastPR.set.weight, reps: newReps)
        return OneRMCalculator.Suggestion(
            reps: newReps, weight: lastPR.set.weight,
            projected1RM: projected, delta: projected - current1RM
        )
    }

    private var smallestPlateIncrement: Double {
        // Get the smallest available plate weight
        // For barbell: plate × 2 (both sides)
        // For single load / bodyweight+single load: plate × 1 (one side only)
        let smallestPlate = availablePlates.min() ?? 2.5
        let multiplier = selectedExercises?.exerciseLoadType == .barbell ? 2.0 : 1.0
        return smallestPlate * multiplier
    }

    private var availableWeightDeltas: [Double] {
        // Calculate all physically achievable increments from available plates
        // For barbell: plate × 2 (both sides)
        // For single load / bodyweight+single load: plate × 1 (one side only)
        var deltas = Set<Double>()
        let multiplier = selectedExercises?.exerciseLoadType == .barbell ? 2.0 : 1.0
        for plateWeight in availablePlates {
            let increment = plateWeight * multiplier
            if increment <= 5.0 {
                deltas.insert(increment)
            }
        }
        // Always include 5.0 as an option
        deltas.insert(5.0)
        return Array(deltas).sorted()
    }

    private var minWeightDelta: Double {
        return availableWeightDeltas.first ?? 5.0
    }

    private var maxWeightDelta: Double {
        return 5.0
    }

    private var suggestions: [OneRMCalculator.Suggestion] {
        return OneRMCalculator.minimizedSuggestions(current1RM: current1RM, increment: weightDelta)
    }

    private var filteredSuggestions: [OneRMCalculator.Suggestion] {
        guard current1RM > 0 else { return [] }
        var filtered = suggestions.filter {
            $0.reps >= userProperties.minReps && $0.reps <= userProperties.maxReps
        }
        if let prPlusOne = lastPRPlusOneSuggestion,
           !filtered.contains(where: { $0.weight == prPlusOne.weight && $0.reps == prPlusOne.reps }) {
            filtered.append(prPlusOne)
        }
        return filtered
    }

    private var topThreeSuggestions: [OneRMCalculator.Suggestion] {
        let filtered = filteredSuggestions

        let sorted: [OneRMCalculator.Suggestion]
        switch sortColumn {
        case .weight:
            sorted = filtered.sorted { sortAscending ? $0.weight < $1.weight : $0.weight > $1.weight }
        case .reps:
            sorted = filtered.sorted { sortAscending ? $0.reps < $1.reps : $0.reps > $1.reps }
        case .est1RM, .gain:
            // EST. 1RM and GAIN are correlated, so they share the same sorting
            sorted = filtered.sorted { sortAscending ? $0.projected1RM < $1.projected1RM : $0.projected1RM > $1.projected1RM }
        }

        return Array(sorted.prefix(5))
    }

    private var effortSuggestions: [OneRMCalculator.EffortSuggestion] {
        guard let mode = effortMode,
              let targetPercent1RMs = mode.targetPercent1RMs,
              let loadType = selectedExercises?.exerciseLoadType else { return [] }
        var results = OneRMCalculator.effortSuggestions(
            current1RM: current1RM,
            targetPercent1RMs: targetPercent1RMs,
            loadType: loadType,
            repRange: mode.repRange(from: userProperties)
        )
        if let bounds = mode.percent1RMBounds {
            results = results.filter { bounds.contains($0.percent1RM) }
        }
        if let match = lastSetMatchForEffort {
            let repRange = mode.repRange(from: userProperties)
            if repRange.contains(match.reps),
               !results.contains(where: { $0.weight == match.weight && $0.reps == match.reps }) {
                let estimated = OneRMCalculator.estimate1RM(weight: match.weight, reps: match.reps)
                let pct = (estimated / current1RM) * 100.0
                results.append(OneRMCalculator.EffortSuggestion(reps: match.reps, weight: match.weight, percent1RM: pct))
            }
        }
        var sorted: [OneRMCalculator.EffortSuggestion]
        switch effortSortColumn {
        case .weight:
            sorted = results.sorted { effortSortAscending ? $0.weight < $1.weight : $0.weight > $1.weight }
        case .reps:
            sorted = results.sorted { effortSortAscending ? $0.reps < $1.reps : $0.reps > $1.reps }
        case .percent1RM:
            sorted = results.sorted { effortSortAscending ? $0.percent1RM < $1.percent1RM : $0.percent1RM > $1.percent1RM }
        }
        if !effortSortUserModified, let match = lastSetMatchForEffort {
            if let idx = sorted.firstIndex(where: { $0.weight == match.weight && $0.reps == match.reps }), idx > 0 {
                let item = sorted.remove(at: idx)
                sorted.insert(item, at: 0)
            }
        }
        return sorted
    }

    private var lastSetMatchForEffort: (weight: Double, reps: Int)? {
        guard let mode = effortMode,
              let bounds = mode.percent1RMBounds else { return nil }
        let e1rm = current1RM
        guard e1rm > 0 else { return nil }

        // Find the most recent set whose percent1RM falls in this mode's bounds
        // setsForExercise is already sorted newest-first
        for set in setsForExercise {
            guard set.weight > 0 else { continue }
            let estimated = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)
            let pct = (estimated / e1rm) * 100.0
            if bounds.contains(pct) {
                return (weight: set.weight, reps: set.reps)
            }
        }
        return nil
    }

    private var weightOptions: [Double] {
        var options: [Double] = []
        var value: Double = 0
        while value <= 500 {
            options.append(value)
            value += smallestPlateIncrement
        }
        return options
    }

    var body: some View {
        VStack(spacing: 0) {
        NavigationStack {
            ZStack {
                // Main content
                VStack(spacing: 12) {
                    programWidget
                        .padding(.top, 12)

                    mainExerciseWidget
                    Divider()
                        .background(.white.opacity(0.35))
                        .padding(.horizontal, 4)
                    // Log Set Section
                    logSetSection
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)

                // Overlays
                if showSubmitOverlay {
                    Color.black.opacity(0.01)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.18)) {
                                showSubmitOverlay = false
                            }
                        }
                        .zIndex(9)

                    SubmitOverlayView(
                        didIncrease: overlayDidIncrease,
                        delta: overlayDelta,
                        new1RM: overlayNew1RM,
                        intensityLabel: overlayIntensityLabel,
                        intensityColor: overlayIntensityColor
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showSubmitOverlay = false
                        }
                    }
                }

                if showExerciseSelectedOverlay, let ex = selectedExercises {
                    VStack(spacing: 14) {
                        ExerciseIconView(exercise: ex, size: 72)
                            .foregroundStyle(Color.appAccent)

                        Text(ex.name)
                            .font(.bebasNeue(size: 24))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 12)
                    }
                    .frame(minWidth: 160, maxWidth: 220)
                    .frame(height: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(white: 0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.appLogoColor.opacity(0.5), lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 5)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(10)
                    .allowsHitTesting(false)
                }

                if showLogConfirmation {
                    ConfirmationOverlayView(
                        exercise: selectedExercises,
                        reps: reps,
                        weight: weight,
                        onConfirm: {
                            hapticFeedback.impactOccurred()
                            showLogConfirmation = false
                            logSet()
                        },
                        onCancel: {
                            hapticFeedback.impactOccurred()
                            showLogConfirmation = false
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(11)
                }

                if showE1RMPopup, let exercise = selectedExercises {
                    // Dimmed backdrop
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showE1RMPopup = false
                            }
                        }
                        .zIndex(11.5)

                    // Popup card
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("e1RM Progression")
                                    .font(.interSemiBold(size: 13))
                                    .foregroundStyle(.white.opacity(0.85))
                                Text(exercise.name)
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
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .frame(width: 26, height: 26)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.12), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                        // Divider
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.horizontal, 16)

                        // Chart
                        OneRMProgressionChart(
                            dataPoints: TrendsCalculator.oneRMProgression(
                                from: estimated1RMsForSelected,
                                exerciseName: exercise.name
                            )
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 18)
                    }
                    .background(
                        LinearGradient(colors: [Color(white: 0.18), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
                            .cornerRadius(16)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(12)
                }
            }
            .onAppear {
                validateWeightDelta()
                if exercises.isEmpty {
                    showNoExercisesAlert = true
                }
                // Apply initial exercise from onboarding (only once)
                if let initialId = initialExerciseId, !hasAppliedInitialExercise {
                    selectedExercisesId = initialId
                    hasAppliedInitialExercise = true
                } else if selectedExercisesId == nil {
                    // Load last selected exercise from UserDefaults
                    if let savedIdString = UserDefaults.standard.string(forKey: lastSelectedExerciseKey),
                       let savedId = UUID(uuidString: savedIdString),
                       exercises.contains(where: { $0.id == savedId }) {
                        selectedExercisesId = savedId
                    }
                }
                if let id = selectedExercisesId {
                    fetchDataForExercise(id)
                }
                refreshTodaySetCounts()
            }
            .onChange(of: selectedExercisesId) { oldId, newId in
                if let newId {
                    fetchDataForExercise(newId)
                    // Auto-select the day that contains this exercise
                    if let matchingDay = daysForActiveSplit.first(where: { $0.exerciseIds.contains(newId) }) {
                        activeDayId = matchingDay.id
                        WorkoutSplitStore.setActiveDayId(matchingDay.id)
                    } else {
                        activeDayId = nil
                    }
                }
                resetToDefaults()
                validateWeightDelta()
                recomputeSetsWithPRInfo()
                selectedPlanTileIndex = nil
                highlightPlanTile(nil)
                effortMode = nil
                // Auto-advance to next set plan effort level
                // (deferred to let todaysSets recompute after exercise change)
                DispatchQueue.main.async {
                    if !setsForSelected.isEmpty, let next = nextPlannedEffortMode {
                        effortMode = next
                        let nextIndex = todaysSets.count
                        selectedPlanTileIndex = nextIndex
                        highlightPlanTile(nextIndex)
                    }
                }
// Save selected exercise to UserDefaults
                if let id = newId {
                    UserDefaults.standard.set(id.uuidString, forKey: lastSelectedExerciseKey)
                }
                // Show exercise selected overlay when selection changes (skip initial load)
                if oldId != nil, oldId != newId, newId != nil, selectedExercises != nil {
                    exerciseOverlayDismissTask?.cancel()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showExerciseSelectedOverlay = true
                    }
                    exerciseOverlayDismissTask = Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.25)) {
                                showExerciseSelectedOverlay = false
                            }
                        }
                    }
                }
            }
            .onChange(of: setsForExercise.count) { _, _ in
                recomputeSetsWithPRInfo()
            }
            .onChange(of: selectedSetData.shouldPopulate) { _, shouldPopulate in
                if shouldPopulate {
                    populateFromSelectedSet()
                    selectedSetData.shouldPopulate = false
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    let currentDay = Calendar.current.startOfDay(for: Date())
                    if currentDay != today {
                        today = currentDay
                    }
                    // Refresh data when returning to app (e.g. after sync completes)
                    if let id = selectedExercisesId {
                        fetchDataForExercise(id)
                    }
                    refreshTodaySetCounts()
                }
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
            .sheet(isPresented: $showHub, onDismiss: {
                activeSplitId = WorkoutSplitStore.activeSplitId()
                hubDeepLinkExerciseId = nil
                hubSection = .exercises  // Reset so next open detects the change
            }) {
                HubView(
                    exercises: exercises,
                    selectedExercisesId: $selectedExercisesId,
                    selectedSection: $hubSection,
                    deepLinkExerciseId: hubDeepLinkExerciseId,
                    onExerciseCreated: { name, loadType, movementType, icon in
                        createExercise(name: name, loadType: loadType, movementType: movementType, icon: icon)
                    },
                    onExerciseSaved: { exercise, name, movementType, icon, notes in
                        saveExercise(exercise, name: name, movementType: movementType, icon: icon, notes: notes)
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
                .sheet(isPresented: $showIncrementSelection) {
                    AvailableChangePlatesView()
                        .presentationDetents([.height(480), .large])
                        .presentationContentInteraction(.scrolls)
                        .presentationDragIndicator(.visible)
                }
                .alert("No Exercise Found", isPresented: $showNoExercisesAlert) {
                    Button("Try Again") {
                        retryFetchExercises()
                    }
                    .disabled(isRetryingSync)
                    Button("Use Defaults") {
                        useDefaultExercises()
                    }
                    Button("Dismiss", role: .cancel) { }
                } message: {
                    Text("Unable to load your exercises. You can retry or start with default exercises.")
                }
                .alert("How did that feel?", isPresented: $showCalibrationAlert) {
                    Button("Easy") { applyCalibration(effort: .easy) }
                    Button("Moderate") { applyCalibration(effort: .moderate) }
                    Button("Hard") { applyCalibration(effort: .hard) }
                    Button("Redline") { applyCalibration(effort: .progress) }
                } message: {
                    Text("This helps estimate your 1RM for better suggestions.")
                }
            .navigationBarHidden(true)
        }
        }
        .ignoresSafeArea(.keyboard)
    }


    private var weightPickerSheet: some View {
        VStack(spacing: 12) {
            // Expression display
            VStack(spacing: 4) {
                // Expression line (always present with fixed height)
                Text(calculatorExpressionDisplay.isEmpty ? " " : calculatorExpressionDisplay)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(calculatorExpressionDisplay.isEmpty ? 0 : 0.6))
                    .frame(height: 24)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                // Result display (centered, fixed height)
                Text(calculatorResultDisplay)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text("lbs")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(height: 110)
            .padding(.horizontal, 16)
            .background(Color(white: 0.12))
            .cornerRadius(12)
            .padding(.horizontal)

            // Calculator pad
            VStack(spacing: 10) {
                // Row 1: 1, 2, 3, backspace
                HStack(spacing: 10) {
                    ForEach(["1", "2", "3"], id: \.self) { number in
                        calcButton(number)
                    }
                    Button {
                        handleCalcBackspace()
                    } label: {
                        Image(systemName: "delete.left")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color(white: 0.25))
                            .cornerRadius(12)
                    }
                }

                // Row 2: 4, 5, 6, +
                HStack(spacing: 10) {
                    ForEach(["4", "5", "6"], id: \.self) { number in
                        calcButton(number)
                    }
                    calcOperatorButton("+")
                }

                // Row 3: 7, 8, 9, -
                HStack(spacing: 10) {
                    ForEach(["7", "8", "9"], id: \.self) { number in
                        calcButton(number)
                    }
                    calcOperatorButton("−")
                }

                // Row 4: ., 0, C, =
                HStack(spacing: 10) {
                    calcButton(".")
                    calcButton("0")

                    Button {
                        calculatorTokens = []
                        currentCalcInput = ""
                    } label: {
                        Text("C")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color(white: 0.25))
                            .cornerRadius(12)
                    }

                    Button {
                        evaluateAndCommit()
                    } label: {
                        Text("=")
                            .font(.title2)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.appAccent)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)

            // Done button
            Button {
                let result = evaluateCalculator()
                // Allow zero for single load (bodyweight) exercises
                let loadType = selectedExercises?.exerciseLoadType
                let minWeight = (loadType == .singleLoad) ? 0.0 : 0.01
                if result >= minWeight && result <= 1000 {
                    weight = result
                    hasSetInitialValues = true
                    hasSetWeight = true
                }
                showWeightPicker = false
            } label: {
                Text("Done")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 55)
                    .background(Color.appAccent)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top, 16)
        .onAppear {
            calculatorTokens = []
            if hasSetInitialValues {
                currentCalcInput = weight.rounded1().formatted(.number.precision(.fractionLength(0...2)))
            } else {
                currentCalcInput = ""
            }
        }
    }

    private func calcButton(_ value: String) -> some View {
        Button {
            handleCalcInput(value)
        } label: {
            Text(value)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(white: 0.18))
                .cornerRadius(12)
        }
    }

    private func calcOperatorButton(_ op: String) -> some View {
        Button {
            handleCalcOperator(op)
        } label: {
            Text(op)
                .font(.title2)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.appAccent.opacity(0.8))
                .cornerRadius(12)
        }
    }

    private var calculatorExpressionDisplay: String {
        var display = calculatorTokens.joined(separator: " ")
        if !currentCalcInput.isEmpty {
            if !display.isEmpty {
                display += " "
            }
            display += currentCalcInput
        }
        return display.isEmpty ? "" : display
    }

    private var calculatorResultDisplay: String {
        let result = evaluateCalculator()
        if result == 0 && calculatorTokens.isEmpty && currentCalcInput.isEmpty {
            return "---"
        }
        // Format nicely - remove trailing zeros
        if result == floor(result) {
            return String(format: "%.0f", result)
        } else {
            return String(format: "%.2f", result).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
        }
    }

    private func handleCalcInput(_ digit: String) {
        // Handle decimal point
        if digit == "." {
            if currentCalcInput.isEmpty {
                currentCalcInput = "0."
            } else if !currentCalcInput.contains(".") {
                currentCalcInput += "."
            }
            return
        }

        // Handle leading zero
        if currentCalcInput == "0" && digit != "." {
            currentCalcInput = digit
            return
        }

        // Check limits based on whether we have a decimal
        if currentCalcInput.contains(".") {
            // With decimal: on 3rd decimal digit, clear and start over
            let parts = currentCalcInput.split(separator: ".")
            if parts.count > 1 && parts[1].count >= 2 {
                currentCalcInput = digit
                return
            }
        } else {
            // Without decimal: on 4th digit, clear and start over
            if currentCalcInput.count >= 3 {
                currentCalcInput = digit
                return
            }
        }

        currentCalcInput += digit
    }

    private func handleCalcOperator(_ op: String) {
        // If we have a current input, commit it first
        if !currentCalcInput.isEmpty {
            calculatorTokens.append(currentCalcInput)
            currentCalcInput = ""
        } else if calculatorTokens.isEmpty {
            // No input yet, use current weight as starting point if available
            if hasSetInitialValues {
                calculatorTokens.append(weight.rounded1().formatted(.number.precision(.fractionLength(0...2))))
            } else {
                return // Nothing to operate on
            }
        }

        // If last token is an operator, replace it
        if let last = calculatorTokens.last, last == "+" || last == "−" {
            calculatorTokens.removeLast()
        }

        calculatorTokens.append(op)
    }

    private func handleCalcBackspace() {
        if !currentCalcInput.isEmpty {
            currentCalcInput.removeLast()
        } else if !calculatorTokens.isEmpty {
            calculatorTokens.removeLast()
        }
    }

    private func evaluateCalculator() -> Double {
        var tokens = calculatorTokens
        if !currentCalcInput.isEmpty {
            tokens.append(currentCalcInput)
        }

        if tokens.isEmpty {
            return 0
        }

        // Parse and evaluate left to right
        var result: Double = 0
        var currentOp: String = "+"

        for token in tokens {
            if token == "+" || token == "−" {
                currentOp = token
            } else if let value = Double(token) {
                if currentOp == "+" {
                    result += value
                } else if currentOp == "−" {
                    result -= value
                }
            }
        }

        return max(0, result) // Don't allow negative weights
    }

    private func evaluateAndCommit() {
        let result = evaluateCalculator()
        calculatorTokens = []
        if result > 0 {
            currentCalcInput = result.rounded1().formatted(.number.precision(.fractionLength(0...2)))
        } else {
            currentCalcInput = ""
        }
    }

    private var repsPickerSheet: some View {
        VStack(spacing: 20) {
            // Reps display
            Spacer()
                .frame(height: 20)
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
            .cornerRadius(12)
            .padding(.horizontal)

            // Number pad
            VStack(spacing: 12) {
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { number in
                            Button {
                                handleRepsInput(number)
                            } label: {
                                Text(number)
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 60)
                                    .background(Color(white: 0.18))
                                    .cornerRadius(12)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    // Empty space (no decimal for reps)
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)

                    Button {
                        handleRepsInput("0")
                    } label: {
                        Text("0")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color(white: 0.18))
                            .cornerRadius(12)
                    }

                    Button {
                        if !repsInput.isEmpty && repsInput != "---" {
                            repsInput.removeLast()
                            if repsInput.isEmpty {
                                repsInput = "---"
                            }
                        }
                    } label: {
                        Image(systemName: "delete.left")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color(white: 0.18))
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)

            // Bottom buttons
            HStack(spacing: 12) {
                Button {
                    repsInput = "---"
                } label: {
                    Text("Clear")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color(white: 0.25))
                        .cornerRadius(12)
                }

                Button {
                    if repsInput != "---", let value = Int(repsInput), value > 0, value <= 99 {
                        reps = value
                        hasSetInitialValues = true
                        hasSetReps = true
                    }
                    showRepsPicker = false
                } label: {
                    Text("Done")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color.appAccent)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear {
            if hasSetReps {
                repsInput = "\(reps)"
            } else {
                repsInput = "---"
            }
        }
    }

    private func handleRepsInput(_ digit: String) {
        // If starting from "---", replace with digit (ignore 0 as first digit)
        if repsInput == "---" {
            if digit != "0" {
                repsInput = digit
            }
            return
        }

        // If input is "0", replace it with the new digit (prevent leading zeros)
        if repsInput == "0" {
            repsInput = digit
            return
        }

        // If we have 2 digits already, overwrite with new digit
        if repsInput.count >= 2 {
            repsInput = digit
            return
        }

        // Otherwise, append the digit if within limits
        let testInput = repsInput + digit
        if let value = Int(testInput), value <= 99 {
            repsInput += digit
        }
    }

    private var programWidget: some View {
        VStack(spacing: 0) {
            // Section 1 — Day pills (compact)
            HStack(spacing: 6) {
                // Split-editor button (stationary)
                Button {
                    hapticFeedback.impactOccurred()
                    hubSection = .splits
                    hubDeepLinkExerciseId = nil
                    showHub = true
                } label: {
                    HStack(spacing: 6) {
                        Image("LiftTheBullIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text("Splits")
                            .font(.bebasNeue(size: 14))
                            .kerning(1.5)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.appAccent)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .frame(minWidth: 76)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.appAccent.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.appAccent.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .padding(.trailing, 4)

                // Day chips
                if daysForActiveSplit.isEmpty {
                    Spacer()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                        ForEach(daysForActiveSplit) { day in
                            let isSelected = activeDayId == day.id
                            Button {
                                hapticFeedback.impactOccurred()
                                if isSelected {
                                    activeDayId = nil
                                    WorkoutSplitStore.setActiveDayId(nil)
                                    selectedExercisesId = nil
                                } else {
                                    activeDayId = day.id
                                    WorkoutSplitStore.setActiveDayId(day.id)
                                }
                            } label: {
                                Text("\(day.name) Day")
                                    .font(.bebasNeue(size: 14))
                                    .kerning(1.5)
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.4))
                                    .lineLimit(1)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                    .frame(height: 26)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(isSelected ? Color.appAccent.opacity(0.2) : Color(white: 0.10))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .stroke(isSelected ? Color.appAccent : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: activeDayId)
                        }
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 12)
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(height: 42)
            .overlay {
                if daysForActiveSplit.isEmpty {
                    Text("Free Training")
                        .font(.bebasNeue(size: 14))
                        .kerning(1.5)
                        .foregroundStyle(.white.opacity(0.25))
                        .allowsHitTesting(false)
                }
            }

            // Separator
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 12)

            // Section 2 — Exercise chips
            HStack(spacing: 0) {
                // Exercise selection button (stationary)
                Button {
                    hapticFeedback.impactOccurred()
                    hubSection = .exercises; hubDeepLinkExerciseId = nil; showHub = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("All")
                            .font(.bebasNeue(size: 14))
                            .kerning(1.5)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.appAccent)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .frame(minWidth: 76)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.appAccent.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.appAccent.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .padding(.trailing, 4)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sequencedExercises) { exercise in
                            let isSelected = selectedExercisesId == exercise.id
                            Button {
                                hapticFeedback.impactOccurred()
                                if isSelected {
                                    selectedExercisesId = nil
                                } else {
                                    selectedExercisesId = exercise.id
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    ExerciseIconView(exercise: exercise, size: 24)
                                        .foregroundStyle(isSelected ? Color.appAccent : .white.opacity(0.4))
                                    Text(exercise.name)
                                        .font(.inter(size: 11))
                                        .foregroundStyle(isSelected ? .white : .white.opacity(0.4))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .frame(height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isSelected ? Color.appAccent.opacity(0.2) : Color(white: 0.10))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isSelected ? Color.appAccent : Color.clear, lineWidth: 1.5)
                                )
                                .animation(.easeInOut(duration: 0.15), value: selectedExercisesId)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5)
                                    .onEnded { _ in
                                        hapticFeedback.impactOccurred()
                                        selectedExercisesId = exercise.id
                                        hubSection = .exercises; hubDeepLinkExerciseId = exercise.id; showHub = true
                                    }
                            )
                            .id(exercise.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                }
                .scrollTargetBehavior(.viewAligned)
                .id(activeDayId)
                .onChange(of: selectedExercisesId) { _, newId in
                    guard let newId else { return }
                    withAnimation {
                        proxy.scrollTo(newId, anchor: .center)
                    }
                }
                .onAppear {
                    if let id = selectedExercisesId {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            }
            .frame(height: 44)
        }
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        .onChange(of: activeSplitId) { _, _ in
            WorkoutSplitStore.setActiveSplitId(activeSplitId)
            if let firstDay = daysForActiveSplit.first {
                // When split changes, auto-select first day
                activeDayId = firstDay.id
                WorkoutSplitStore.setActiveDayId(firstDay.id)
            } else {
                // No split selected — clear day selection, show all exercises
                activeDayId = nil
                WorkoutSplitStore.setActiveDayId(nil)
                selectedExercisesId = nil
            }
        }
    }

    private var selectedExerciseRow: some View {
        ZStack {
            // Center — Exercise name (always centered in widget)
            Button {
                hapticFeedback.impactOccurred()
                if let ex = selectedExercises {
                    hubSection = .exercises; hubDeepLinkExerciseId = ex.id; showHub = true
                } else {
                    hubSection = .exercises; hubDeepLinkExerciseId = nil; showHub = true
                }
            } label: {
                if let ex = selectedExercises {
                    Text(ex.name)
                        .font(.bebasNeue(size: 24))
                        .kerning(1)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("Select Exercise")
                        .font(.bebasNeue(size: 24))
                        .kerning(1)
                        .foregroundStyle(Color.appAccent)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 50)

            HStack(spacing: 0) {
                // Left — Detail button
                if let ex = selectedExercises {
                    Button {
                        hapticFeedback.impactOccurred()
                        hubSection = .exercises; hubDeepLinkExerciseId = ex.id; showHub = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.appAccent)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.appAccent.opacity(0.15))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.appAccent.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 12)
                }

                Spacer()

                // Right — e1RM (hidden when zero)
                if selectedExercises != nil && current1RM > 0 {
                    Button {
                        hapticFeedback.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showE1RMPopup = true
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text("e1RM")
                                .font(.inter(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                            HStack(spacing: 4) {
                                Text(current1RM.rounded1().formatted(.number.precision(.fractionLength(2))))
                                    .font(.interSemiBold(size: 16))
                                    .foregroundStyle(Color.appAccent)
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.appAccent.opacity(0.7))
                            }
                        }
                        .padding(.trailing, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 52)
    }

    private var mainExerciseWidget: some View {
        VStack(spacing: 0) {
            selectedExerciseRow

            // Session zone (set plan + sets)
            VStack(spacing: 0) {
                setComparisonView
            }
            .padding(.horizontal, 12)
            .padding(.vertical, selectedExercises == nil ? 4 : 8)
            .frame(height: selectedExercises == nil ? 60 : nil)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.11))
            }
            .padding(.horizontal, 4)
            .padding(.top, 10)

            // Options container (flex to fill remaining space)
            VStack(spacing: 0) {
                // Effort chips + expand button inline
                HStack(spacing: 8) {
                    effortChipSelector

                    Button {
                        hapticFeedback.impactOccurred()
                        let mode = effortMode ?? .easy
                        if mode == .progress {
                            showExpandedProgressOptions = true
                        } else {
                            if effortMode == nil {
                                withAnimation { effortMode = .easy }
                            }
                            showExpandedEffortOptions = true
                        }
                    } label: {
                        Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 30, height: 30)
                            .background(Color(white: 0.16))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .opacity(selectedExercises != nil && !setsForSelected.isEmpty ? 1 : 0)
                .allowsHitTesting(selectedExercises != nil && !setsForSelected.isEmpty)

                // Options section
                optionsSection

                // Legend
                HStack(spacing: 10) {
                    LegendItem(color: .setEasy, label: "Easy")
                    LegendItem(color: .setModerate, label: "Moderate")
                    LegendItem(color: .setHard, label: "Hard")
                    LegendItem(color: .setNearMax, label: "Redline")
                    LegendItem(color: .setPR, label: "e1RM ↑")
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 12)
                .opacity(!setsForSelected.isEmpty ? 1 : 0)
                .layoutPriority(1)
            }
            .frame(maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.11))
            }
            .padding(.horizontal, 4)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .frame(height: 420)
        .background(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
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
                    selectOption(suggestion)
                },
                onSwitchMode: { newMode in
                    showExpandedProgressOptions = false
                    withAnimation { effortMode = newMode }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showExpandedEffortOptions = true
                    }
                }
            )
            .presentationDetents([.large])
            .presentationContentInteraction(.scrolls)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExpandedEffortOptions) {
            ExpandedEffortOptionsSheet(
                effortMode: effortMode ?? .easy,
                suggestions: effortSuggestions,
                repRangeMin: Binding(
                    get: {
                        switch effortMode ?? .easy {
                        case .easy: return userProperties.easyMinReps
                        case .moderate: return userProperties.moderateMinReps
                        case .hard: return userProperties.hardMinReps
                        case .progress: return userProperties.minReps
                        }
                    },
                    set: {
                        switch effortMode ?? .easy {
                        case .easy: userProperties.easyMinReps = $0
                        case .moderate: userProperties.moderateMinReps = $0
                        case .hard: userProperties.hardMinReps = $0
                        case .progress: userProperties.minReps = $0
                        }
                    }
                ),
                repRangeMax: Binding(
                    get: {
                        switch effortMode ?? .easy {
                        case .easy: return userProperties.easyMaxReps
                        case .moderate: return userProperties.moderateMaxReps
                        case .hard: return userProperties.hardMaxReps
                        case .progress: return userProperties.maxReps
                        }
                    },
                    set: {
                        switch effortMode ?? .easy {
                        case .easy: userProperties.easyMaxReps = $0
                        case .moderate: userProperties.moderateMaxReps = $0
                        case .hard: userProperties.hardMaxReps = $0
                        case .progress: userProperties.maxReps = $0
                        }
                    }
                ),
                onRepRangeChanged: { scheduleRepRangeSync() },
                lastSetMatch: lastSetMatchForEffort,
                onSelect: { suggestion in
                    selectEffortOption(suggestion)
                },
                onSwitchMode: { newMode in
                    showExpandedEffortOptions = false
                    withAnimation { effortMode = newMode }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if newMode == .progress {
                            showExpandedProgressOptions = true
                        } else {
                            showExpandedEffortOptions = true
                        }
                    }
                }
            )
            .presentationDetents([.large])
            .presentationContentInteraction(.scrolls)
            .presentationDragIndicator(.visible)
        }
    }

    struct EmptyGraphView: View {
        var body: some View {
            ZStack {
                // Sample chart with colorful bars
                Chart {
                    let sampleData: [(height: Double, color: [Color])] = [
                        (60, [.setEasy, .setEasy.opacity(0.8)]), // Easy
                        (75, [.setModerate, .setModerate.opacity(0.8)]), // Moderate
                        (85, [.setHard, .setHard.opacity(0.8)]), // Hard
                        (95, [.setNearMax, .setNearMax.opacity(0.8)]), // Near Max
                        (110, [.setPR, .setPR.opacity(0.8)]), // PR
                        (100, [.setNearMax, .setNearMax.opacity(0.8)]), // Near Max
                        (90, [.setHard, .setHard.opacity(0.8)]), // Hard
                        (105, [.setNearMax, .setNearMax.opacity(0.8)]), // Near Max
                    ]

                    ForEach(0..<sampleData.count, id: \.self) { index in
                        let data = sampleData[index]
                        RectangleMark(
                            xStart: .value("Start", Double(index)),
                            xEnd: .value("End", Double(index) + 1.0),
                            yStart: .value("Base", 0),
                            yEnd: .value("Height", data.height)
                        )
                        .foregroundStyle(
                            LinearGradient(colors: data.color, startPoint: .top, endPoint: .bottom)
                        )
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartXScale(domain: 0...Double(8))
                .frame(height: 85)
                .opacity(0.4)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Overlay text (commented out to simplify)
                // VStack(spacing: 8) {
                //     Text("No Estimates Yet")
                //         .font(.subheadline.weight(.semibold))
                //         .foregroundStyle(.white)
                //
                //     Text("Your 1RM estimates will appear here")
                //         .font(.caption)
                //         .foregroundStyle(.white.opacity(0.7))
                // }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    struct SetHistoryChart: View {
        let setsWithPRInfo: [SetWithPR]
        let showYAxis: Bool
        @Binding var selectedBarIndex: Int?

        var body: some View {
            chartView
        }

        private var chartView: some View {
            // Fixed bar width in pixels
            let barWidth: CGFloat = 8
            // Total number of bars
            let barCount = setsWithPRInfo.count
            // Calculate exact width needed for all bars
            let totalChartWidth = CGFloat(barCount) * barWidth

            return Chart {
                ForEach(0..<barCount, id: \.self) { index in
                    barMark(index: index, setInfo: setsWithPRInfo[index], isSelected: selectedBarIndex == index)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(showYAxis ? .automatic : .hidden)
            .chartXScale(domain: 0...Double(barCount))
            .frame(width: totalChartWidth, height: 100)
        }

        private func colorForSet(_ setInfo: SetWithPR) -> [Color] {
            // Baseline sets — color by reported effort (percent1RM is now set from calibration)
            if setInfo.set.isBaselineSet {
                let bucket = TrendsCalculator.IntensityBucket.from(percent1RM: setInfo.percent1RM / 100.0)
                let c: Color
                switch bucket {
                case .pr, .redline: c = .setNearMax
                case .hard: c = .setHard
                case .moderate: c = .setModerate
                case .easy: c = .setEasy
                }
                return [c, c.opacity(0.8)]
            }

            // If it increases 1RM, use special PR color
            if setInfo.increases1RM {
                return [.setPR, .setPR.opacity(0.8)]
            }

            // For 0-weight sets, color by reps (more reps = harder)
            if setInfo.set.weight == 0 {
                switch setInfo.set.reps {
                case 12...:
                    return [.setNearMax, .setNearMax.opacity(0.8)]
                case 9..<12:
                    return [.setHard, .setHard.opacity(0.8)]
                case 6..<9:
                    return [.setModerate, .setModerate.opacity(0.8)]
                default:
                    return [.setEasy, .setEasy.opacity(0.8)]
                }
            }

            // Otherwise, color by percent1RM-based effort
            let bucket = TrendsCalculator.IntensityBucket.from(percent1RM: setInfo.percent1RM)
            let color: Color
            switch bucket {
            case .pr: color = .setPR
            case .redline: color = .setNearMax
            case .hard: color = .setHard
            case .moderate: color = .setModerate
            case .easy: color = .setEasy
            }
            return [color, color.opacity(0.8)]
        }

        private func barMark(index: Int, setInfo: SetWithPR, isSelected: Bool) -> some ChartContent {
            let colors: [Color]

            if isSelected {
                // Bright white gradient for selected bar
                colors = [.white, Color(white: 0.9)]
            } else {
                colors = colorForSet(setInfo)
            }

            return RectangleMark(
                xStart: .value("Start", Double(index)),
                xEnd: .value("End", Double(index) + 1.0),
                yStart: .value("Base", 0),
                yEnd: .value("1RM", setInfo.estimated1RM)
            )
            .foregroundStyle(
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            )
        }
    }

    struct SetHistoryChartYAxis: View {
        let setsWithPRInfo: [SetWithPR]

        var body: some View {
            // Create a minimal chart just for the Y-axis
            let maxValue = setsWithPRInfo.map { $0.estimated1RM }.max() ?? 100

            Chart {
                // Invisible placeholder to establish Y-scale
                RectangleMark(
                    x: .value("X", 0),
                    y: .value("Y", 0)
                )
                .opacity(0)
                RectangleMark(
                    x: .value("X", 0),
                    y: .value("Y", maxValue)
                )
                .opacity(0)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.1))
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.3))
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.caption2)
                }
            }
            .frame(width: 50, height: 95)
        }
    }

    private var todaysSets: [LiftSet] {
        guard selectedExercises != nil else { return [] }
        let calendar = Calendar.current
        let today = self.today
        return setsForExercise.filter { set in
            calendar.isDate(set.createdAt, inSameDayAs: today)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    private var setComparisonView: some View {
        let standardSequence = SetPlan.builtInTemplates.first(where: { $0.id == SetPlan.standardId })?.sequence ?? ["easy", "easy", "moderate", "moderate", "hard", "pr"]

        return Group {
            if selectedExercises == nil {
                // Empty state — colorful placeholder tiles
                let placeholderSequence = ["easy", "easy", "moderate", "moderate", "hard", "hard", "pr"]
                VStack {
                    Spacer()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(placeholderSequence.enumerated()), id: \.offset) { _, effort in
                                let color = SequenceSquareView.color(for: effort)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(color.opacity(0.35))
                                    .frame(width: 42, height: 42)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(color.opacity(0.6), lineWidth: 1.5)
                                    )
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 2)
                    }
                    .frame(height: 46)
                    .scrollIndicators(.hidden)
                    .allowsHitTesting(false)
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    // Set Plan — compact Menu + mini sequence preview + edit button
                    HStack(spacing: 8) {
                        // Active template label with Menu to switch (includes "None" option)
                        Menu {
                            let sorted = allTemplates.sorted {
                                if $0.isCustom != $1.isCustom { return !$0.isCustom }
                                return $0.createdAt < $1.createdAt
                            }
                            ForEach(sorted) { t in
                                Button {
                                    hapticFeedback.impactOccurred()
                                    userProperties.activeSetPlanId = t.id
                                    try? modelContext.save()
                                    Task { await SyncService.shared.updateActiveSetPlan(t.id) }
                                } label: {
                                    Label(t.name, systemImage: userProperties.activeSetPlanId == t.id ? "checkmark" : "")
                                }
                            }
                            Divider()
                            Button {
                                hapticFeedback.impactOccurred()
                                userProperties.activeSetPlanId = nil
                                try? modelContext.save()
                                Task { await SyncService.shared.updateActiveSetPlan(nil) }
                            } label: {
                                Label("None", systemImage: activeSetPlan == nil ? "checkmark" : "")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(activeSetPlan != nil ? "\(activeSetPlan!.name) Session" : "– –")
                                    .font(.inter(size: 11))
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.12)))
                        }

                        Spacer()

                        // Edit button → opens Hub Set Plans tab
                        Button {
                            hapticFeedback.impactOccurred()
                            hubSection = .setPlans
                            hubDeepLinkExerciseId = nil
                            showHub = true
                        } label: {
                            Image(systemName: "square.stack")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }

                    // Session
                    VStack(alignment: .leading, spacing: 6) {
                        ScrollViewReader { sessionProxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(Array(todaysSets.enumerated()), id: \.element.id) { index, set in
                                        SetSquareView(
                                            set: set,
                                            allSets: setsForExercise,
                                            currentWeight: weight,
                                            currentReps: reps,
                                            hasSetValues: hasSetInitialValues,
                                            selectedSquareId: selectedSquareId,
                                            allEstimated1RM: estimated1RMsForExercise,
                                            onDelete: {
                                                if let id = selectedExercisesId {
                                                    fetchDataForExercise(id)
                                                }
                                                refreshTodaySetCounts()
                                            }
                                        )
                                        .id(set.id)
                                        .onTapGesture {
                                            weight = set.weight
                                            reps = set.reps
                                            hasSetInitialValues = true
                                            hasSetWeight = true
                                            hasSetReps = true
                                            hasSelectedOption = true
                                            selectedSquareId = set.id

                                            // Update effort mode from plan if this set's index maps to a plan entry
                                            if index < displaySetPlan.count {
                                                let effortKey = displaySetPlan[index]
                                                withAnimation { effortMode = EffortMode.from(effort: effortKey) }
                                            }

                                            hapticFeedback.impactOccurred()
                                            flashLogSetHighlight()
                                            Task {
                                                try? await Task.sleep(nanoseconds: 300_000_000)
                                                await MainActor.run {
                                                    selectedSquareId = nil
                                                }
                                            }
                                        }
                                    }

                                    // Plan-aware placeholder tiles
                                    let completedCount = todaysSets.count
                                    let planCount = displaySetPlan.count
                                    let remaining = planCount - completedCount

                                    if remaining > 0 {
                                        ForEach(0..<remaining, id: \.self) { i in
                                            let planIndex = completedCount + i
                                            let effortKey = planIndex < displaySetPlan.count ? displaySetPlan[planIndex] : "easy"
                                            let color = SequenceSquareView.color(for: effortKey)
                                            let isNext = (i == 0)
                                            let isHighlighted = highlightedPlanTileIndex == planIndex
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.clear)
                                                .frame(width: 42, height: 42)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(isHighlighted ? color : color, lineWidth: isHighlighted ? 2.5 : (isNext ? 2 : 1.5))
                                                )
                                                .shadow(color: isHighlighted ? color.opacity(0.5) : .clear, radius: 4)
                                                .onTapGesture {
                                                    guard !setsForSelected.isEmpty else { return }
                                                    hapticFeedback.impactOccurred()
                                                    selectedPlanTileIndex = planIndex
                                                    highlightPlanTile(planIndex)
                                                    withAnimation {
                                                        effortMode = EffortMode.from(effort: effortKey)
                                                    }
                                                }
                                        }
                                        .allowsHitTesting(!setsForSelected.isEmpty)
                                    } else {
                                        // Plan exhausted — static outline for overflow sets
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.clear)
                                            .frame(width: 42, height: 42)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                                            )
                                    }
                                }
                                .padding(.vertical, 2)
                                .padding(.horizontal, 2)
                            }
                            .frame(height: 46)
                            .scrollIndicators(.hidden)
                            .onChange(of: sessionScrollTarget) { _, target in
                                if let target {
                                    withAnimation {
                                        sessionProxy.scrollTo(target, anchor: .trailing)
                                    }
                                    sessionScrollTarget = nil
                                }
                            }
                        }
                    }
                }

                Spacer()
                    .frame(height: 8)
            }
        }
    }

    private var effortChipSelector: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EffortMode.allCases, id: \.rawValue) { mode in
                    let isSelected = effortMode == mode
                    Button {
                        hapticFeedback.impactOccurred()
                        if isSelected {
                            withAnimation { effortMode = nil }
                            selectedPlanTileIndex = nil
                        } else {
                            if let matchIndex = displaySetPlan.firstIndex(where: { $0 == mode.effortKey }) {
                                selectedPlanTileIndex = matchIndex
                            } else {
                                selectedPlanTileIndex = nil
                            }
                            withAnimation { effortMode = mode }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(mode.tileColor.opacity(0.4))
                                .frame(width: 10, height: 10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(mode.tileColor, lineWidth: 1)
                                )
                            Text(mode.chipLabel)
                                .font(.inter(size: 11))
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.4))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? mode.tileColor.opacity(0.2) : Color(white: 0.16))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? mode.tileColor : Color.clear, lineWidth: 1.5)
                        )
                        .animation(.easeInOut(duration: 0.15), value: effortMode)
                    }
                    .buttonStyle(.plain)
                    .id(mode.rawValue)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .onChange(of: effortMode) { _, newMode in
            if let mode = newMode {
                withAnimation {
                    proxy.scrollTo(mode.rawValue, anchor: .center)
                }
            }
        }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let mode = effortMode {
                if mode == .progress {
                    progressOptionsContent
                } else {
                    effortOptionsContent
                }
            } else if selectedExercises == nil {
                Button {
                    hubSection = .exercises; hubDeepLinkExerciseId = nil; showHub = true
                } label: {
                    ProgressOptionsEmptyState(message: "Select an Exercise")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if setsForSelected.isEmpty {
                ProgressOptionsEmptyState(message: "Log your first set")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressOptionsEmptyState(message: nil, showPRIndicator: todayHasWeightedE1RMPR)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.top, 6)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var progressOptionsContent: some View {
        VStack(spacing: 8) {
            if filteredSuggestions.isEmpty {
                ZStack {
                    RadialGradient(
                        colors: [
                            Color.setPR.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )

                    VStack(spacing: 14) {
                        Image("LiftTheBullIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .foregroundStyle(Color.setPR)
                            .shadow(color: Color.setPR.opacity(0.3), radius: 14, x: 0, y: 0)

                        Text(setsForSelected.isEmpty
                            ? "Log a Set to Unlock Progress Options"
                            : "Lift with Load to Unlock Progress Options")
                            .font(.bebasNeue(size: 20))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                    }
                    .offset(y: 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            // Fixed header row with labels
            HStack(spacing: 12) {
                Button {
                    handleColumnTap(.weight)
                } label: {
                    VStack(spacing: 0) {
                        Text("WEIGHT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(columnHighlighted && sortColumn == .weight ? Color.appAccent : Color.appLabel)
                            .animation(.easeInOut(duration: 0.15), value: columnHighlighted)
                        if sortColumn == .weight {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.appLabel)
                        } else {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.clear)
                        }
                    }
                    .frame(width: 65, height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()
                    .frame(width: 1)

                Button {
                    handleColumnTap(.reps)
                } label: {
                    VStack(spacing: 0) {
                        Text("REPS")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(columnHighlighted && sortColumn == .reps ? Color.appAccent : Color.appLabel)
                            .animation(.easeInOut(duration: 0.15), value: columnHighlighted)
                        if sortColumn == .reps {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.appLabel)
                        } else {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.clear)
                        }
                    }
                    .frame(width: 50, height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()
                    .frame(width: 1)

                Button {
                    handleColumnTap(.est1RM)
                } label: {
                    VStack(spacing: 0) {
                        Text("e1RM")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(columnHighlighted && sortColumn == .est1RM ? Color.appAccent : Color.appLabel)
                            .animation(.easeInOut(duration: 0.15), value: columnHighlighted)
                        if sortColumn == .est1RM || sortColumn == .gain {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.appLabel)
                        } else {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.clear)
                        }
                    }
                    .frame(width: 60, height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()
                    .frame(width: 1)

                Button {
                    handleColumnTap(.gain)
                } label: {
                    VStack(spacing: 0) {
                        Text("GAIN")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(columnHighlighted && sortColumn == .gain ? Color.appAccent : Color.appLabel)
                            .animation(.easeInOut(duration: 0.15), value: columnHighlighted)
                        if sortColumn == .gain || sortColumn == .est1RM {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.appLabel)
                        } else {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.clear)
                        }
                    }
                    .frame(width: 65, height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)

            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(Array(topThreeSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                                ProgressOptionCard(
                                    suggestion: suggestion,
                                    isSelected: isOptionSelected(suggestion),
                                    sortColumn: sortColumn,
                                    columnHighlighted: columnHighlighted,
                                    weightColumnHighlighted: weightColumnHighlighted
                                )
                                .onTapGesture {
                                    hapticFeedback.impactOccurred()
                                    selectOption(suggestion)
                                }
                                .id(index == 0 ? "top" : nil)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .frame(maxHeight: .infinity)
                    .onChange(of: sortColumn) { _, _ in
                        withAnimation {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                    .onChange(of: sortAscending) { _, _ in
                        withAnimation {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }

                LinearGradient(
                    colors: [
                        Color(white: 0.14).opacity(0),
                        Color(white: 0.14).opacity(0.8),
                        Color(white: 0.14)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 8)
                .allowsHitTesting(false)
            }
            }
        }
    }

    private var effortOptionsContent: some View {
        VStack(spacing: 8) {
            if effortSuggestions.isEmpty {
                // Starter suggestion when e1RM is too low
                starterSuggestionCard
            } else {
                // Sortable header
                HStack(spacing: 0) {
                    effortColumnButton(title: "WEIGHT", column: .weight)
                    effortColumnButton(title: "REPS", column: .reps)
                    effortColumnButton(title: "e1RM %", column: .percent1RM)
                }
                .frame(height: 24)
                .padding(.horizontal, 12)

                ZStack(alignment: .bottom) {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 8) {
                                ForEach(Array(effortSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                                    EffortOptionCard(
                                        suggestion: suggestion,
                                        isSelected: isEffortOptionSelected(suggestion),
                                        sortColumn: effortSortColumn,
                                        columnHighlighted: effortColumnHighlighted,
                                        accentColor: (effortMode ?? .easy).tileColor,
                                        isLastSet: lastSetMatchForEffort.map { $0.weight == suggestion.weight && $0.reps == suggestion.reps } ?? false
                                    )
                                    .onTapGesture {
                                        hapticFeedback.impactOccurred()
                                        selectEffortOption(suggestion)
                                    }
                                    .id(index == 0 ? "effortTop" : nil)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                        .frame(maxHeight: .infinity)
                        .onChange(of: effortSortColumn) { _, _ in
                            withAnimation { proxy.scrollTo("effortTop", anchor: .top) }
                        }
                        .onChange(of: effortSortAscending) { _, _ in
                            withAnimation { proxy.scrollTo("effortTop", anchor: .top) }
                        }
                    }

                    LinearGradient(
                        colors: [
                            Color(white: 0.14).opacity(0),
                            Color(white: 0.14).opacity(0.8),
                            Color(white: 0.14)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 8)
                    .allowsHitTesting(false)
                }

                if lastSetMatchForEffort != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Last set with this effort")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 2)
                }
            }
        }
    }

    private var starterSuggestionCard: some View {
        let accentColor = (effortMode ?? .easy).tileColor
        let modeName: String = {
            switch effortMode ?? .easy {
            case .easy: return "Easy"
            case .moderate: return "Moderate"
            case .hard: return "Hard"
            case .progress: return "Progress"
            }
        }()
        return ZStack {
            RadialGradient(
                colors: [
                    accentColor.opacity(0.08),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 80
            )

            VStack(spacing: 14) {
                Image("LiftTheBullIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .foregroundStyle(accentColor)
                    .shadow(color: accentColor.opacity(0.3), radius: 14, x: 0, y: 0)

                Text(setsForSelected.isEmpty
                    ? "Log a Set to Unlock \(modeName) Options"
                    : "Lift with Load to Unlock \(modeName) Options")
                    .font(.bebasNeue(size: 20))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .offset(y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logSetSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                // Weight with increment/decrement
                HStack(spacing: 8) {
                    Button {
                        guard selectedExercises != nil else {
                            hubSection = .exercises; hubDeepLinkExerciseId = nil; showHub = true
                            return
                        }
                        if !hasSetWeight {
                            weight = selectedExercises?.exerciseLoadType == .barbell ? 45.0 : 0.0
                        } else {
                            weight = max(0, weight - smallestPlateIncrement)
                        }
                        hasSetInitialValues = true
                        hasSetWeight = true
                        hapticFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.appAccent)
                    }

                    Button {
                        guard selectedExercises != nil else {
                            hubSection = .exercises; hubDeepLinkExerciseId = nil; showHub = true
                            return
                        }
                        showWeightPicker = true
                    } label: {
                        VStack(spacing: 1) {
                            Text(hasSetWeight ? weight.rounded1().formatted(.number.precision(.fractionLength(2))) : "---")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text("lbs")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(width: 75)
                    }
                    .buttonStyle(.plain)

                    Button {
                        guard selectedExercises != nil else {
                            hubSection = .exercises; hubDeepLinkExerciseId = nil; showHub = true
                            return
                        }
                        if !hasSetWeight {
                            weight = selectedExercises?.exerciseLoadType == .barbell ? 45.0 : 0.0
                        } else {
                            weight = min(1000, weight + smallestPlateIncrement)
                        }
                        hasSetInitialValues = true
                        hasSetWeight = true
                        hapticFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.appAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(white: 0.12))
                .cornerRadius(10)

                // Reps
                HStack(spacing: 8) {
                    Button {
                        guard selectedExercises != nil else {
                            hubSection = .exercises; hubDeepLinkExerciseId = nil; showHub = true
                            return
                        }
                        hasSetInitialValues = true
                        hasSetReps = true
                        reps = max(1, reps - 1)
                        hapticFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.appAccent)
                    }

                    Button {
                        guard selectedExercises != nil else {
                            hubSection = .exercises; hubDeepLinkExerciseId = nil; showHub = true
                            return
                        }
                        showRepsPicker = true
                    } label: {
                        VStack(spacing: 2) {
                            Text(hasSetReps ? "\(reps)" : "---")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text("reps")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(width: 60)
                    }
                    .buttonStyle(.plain)

                    Button {
                        guard selectedExercises != nil else {
                            hubSection = .exercises; hubDeepLinkExerciseId = nil; showHub = true
                            return
                        }
                        hasSetInitialValues = true
                        hasSetReps = true
                        reps = min(99, reps + 1)
                        hapticFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.appAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(white: 0.12))
                .cornerRadius(10)
            }

            // Log Set button spanning full width
            Button {
                hapticFeedback.impactOccurred()
                guard selectedExercises != nil else {
                    hubSection = .exercises; hubDeepLinkExerciseId = nil; showHub = true
                    return
                }
                if !hasSetWeight {
                    // Weight not set - open weight picker
                    showWeightPicker = true
                } else if !hasSetReps {
                    // Weight set but reps not set - open reps picker
                    showRepsPicker = true
                } else {
                    // Both set - show confirmation
                    showLogConfirmation = true
                }
            } label: {
                Text("Log Set")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Color.appAccent)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke((effortMode ?? .progress).tileColor, lineWidth: logSetMatchesOption ? 3 : 0)
                .animation(.easeInOut(duration: 0.3), value: logSetMatchesOption)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke((effortMode ?? .progress).tileColor, lineWidth: 6)
                .opacity(logSetFlash ? 0.7 : 0)
                .animation(.easeInOut(duration: 0.3), value: logSetFlash)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }

    private struct SubmitOverlayView: View {
        let didIncrease: Bool
        let delta: Double
        let new1RM: Double
        let intensityLabel: String
        let intensityColor: Color

        @State private var pulse = false
        @State private var iconScale: CGFloat = 0.5
        @State private var iconOpacity: Double = 0

        private let squareSize: CGFloat = 180

        var body: some View {
            ZStack {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    if didIncrease {
                        Image("LiftTheBullIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundStyle(Color.appLogoColor)
                            .scaleEffect(iconScale)
                            .opacity(iconOpacity)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(intensityColor.opacity(0.3))
                            .frame(width: 48, height: 48)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(intensityColor, lineWidth: 2)
                            )
                            .scaleEffect(iconScale)
                            .opacity(iconOpacity)
                    }

                    if didIncrease {
                        VStack(spacing: 4) {
                            Text("Increased 1RM by")
                                .font(.subheadline)
                            Text("+\(delta.rounded1().formatted(.number.precision(.fractionLength(delta >= 100 ? 0 : 2)))) lbs")
                                .font(.title.weight(.semibold))
                                .foregroundStyle(Color.appLogoColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    } else {
                        VStack(spacing: 2) {
                            Text(intensityLabel)
                                .font(.bebasNeue(size: 32))
                                .foregroundStyle(.white)
                            Text("Set Logged")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .frame(width: squareSize, height: squareSize)
                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    VStack {
                        LinearGradient(
                            colors: [.clear, Color.appLogoColor.opacity(0.6), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 2)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.appLogoColor.opacity(0.5), lineWidth: 1.5)
                )
                .scaleEffect(pulse ? 1.02 : 1.0)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        iconScale = 1.0
                        iconOpacity = 1.0
                    }
                    withAnimation(.easeInOut(duration: 0.3).repeatCount(3, autoreverses: true).delay(0.4)) {
                        pulse = true
                    }
                }
            }
        }
    }

    private struct ConfirmationOverlayView: View {
        let exercise: Exercise?
        let reps: Int
        let weight: Double
        let onConfirm: () -> Void
        let onCancel: () -> Void

        var body: some View {
            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onCancel()
                    }

                VStack(spacing: 20) {
                    // Exercise icon and name
                    VStack(spacing: 8) {
                        if let exercise = exercise {
                            ExerciseIconView(exercise: exercise, size: 90)
                                .foregroundStyle(Color.appAccent)
                        }

                        Text(exercise?.name ?? "Exercise")
                            .font(.bebasNeue(size: 24))
                            .foregroundStyle(Color.appAccent)
                    }

                    // Set details in a compact pill
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Text("\(weight.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs")
                                .font(.bebasNeue(size: 22))
                                .foregroundStyle(.white)
                        }

                        Rectangle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 1, height: 24)

                        HStack(spacing: 6) {
                            Text("\(reps)")
                                .font(.bebasNeue(size: 22))
                                .foregroundStyle(.white)
                            Text("reps")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.08))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )

                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 1)
                        .padding(.horizontal, 4)

                    HStack(spacing: 10) {
                        Button {
                            onCancel()
                        } label: {
                            Text("Cancel")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(white: 0.2))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onConfirm()
                        } label: {
                            Text("Confirm")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.appAccent)
                                .cornerRadius(10)
                                .shadow(color: Color.appAccent.opacity(0.3), radius: 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
                .background(
                    Color(white: 0.14)
                )
                .cornerRadius(20)
                .overlay(
                    VStack {
                        LinearGradient(
                            colors: [.clear, Color.appLogoColor.opacity(0.6), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 2)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.appLogoColor.opacity(0.5), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
                .padding(.horizontal, 32)
            }
        }
    }

    private func createExercise(name: String, loadType: ExerciseLoadType, movementType: ExerciseMovementType, icon: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let ex = Exercise(name: trimmed, isCustom: true, loadType: loadType, movementType: movementType, icon: icon)
        modelContext.insert(ex)
        selectedExercisesId = ex.id

        // Sync new custom exercise to backend
        Task { await SyncService.shared.syncExercise(ex) }
    }

    private func saveExercise(_ exercise: Exercise, name: String, movementType: ExerciseMovementType, icon: String, notes: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        exercise.name = trimmed
        exercise.icon = icon
        exercise.exerciseMovementType = movementType
        exercise.notes = notes
        try? modelContext.save()

        // Sync edited exercise to backend
        Task { await SyncService.shared.syncExercise(exercise) }
    }

    private func deleteExercise(_ exercise: Exercise) {
        let exerciseId = exercise.id

        // Delete associated sets
        let setsDescriptor = FetchDescriptor<LiftSet>(
            predicate: #Predicate { $0.exercise?.id == exerciseId }
        )
        let setsToDelete = (try? modelContext.fetch(setsDescriptor)) ?? []
        for set in setsToDelete {
            modelContext.delete(set)
        }

        // Delete associated 1RM records
        let e1rmDescriptor = FetchDescriptor<Estimated1RM>(
            predicate: #Predicate { $0.exercise?.id == exerciseId }
        )
        let estimatesToDelete = (try? modelContext.fetch(e1rmDescriptor)) ?? []
        for estimate in estimatesToDelete {
            modelContext.delete(estimate)
        }

        // Delete the exercise
        modelContext.delete(exercise)
        try? modelContext.save()

        // Close the hub sheet if open
        showHub = false

        // Select a different exercise
        selectedExercisesId = exercises.first(where: { $0.id != exercise.id })?.id

        // Sync deletion to backend immediately
        Task { await SyncService.shared.deleteExercise(exerciseId) }
    }

    private func resetToDefaults() {
        reps = 8
        if setsForSelected.isEmpty {
            weight = 20.0
        } else {
            weight = (current1RM * 0.8).rounded()
        }
        hasSetInitialValues = false
        hasSetWeight = false
        hasSetReps = false
        hasSelectedOption = false
    }

    private func validateWeightDelta() {
        // Ensure weightDelta is valid for current exercise's available deltas
        if !availableWeightDeltas.contains(where: { abs($0 - weightDelta) < 0.01 }) {
            // Current delta not valid, pick new one
            if availableWeightDeltas.contains(where: { abs($0 - 2.5) < 0.01 }) {
                weightDelta = 2.5
            } else {
                weightDelta = availableWeightDeltas.min(by: { abs($0 - 2.5) < abs($1 - 2.5) }) ?? 5.0
            }
        }
    }

    private func populateFromSelectedSet() {
        if let exerciseId = selectedSetData.exerciseId {
            selectedExercisesId = exerciseId
        }
        if let repsValue = selectedSetData.reps {
            reps = repsValue
            hasSetInitialValues = true
            hasSetReps = true
        }
        if let weightValue = selectedSetData.weight {
            weight = weightValue
            hasSetInitialValues = true
            hasSetWeight = true
        }

    }

    private func isOptionSelected(_ suggestion: OneRMCalculator.Suggestion) -> Bool {
        return weight == suggestion.weight && reps == suggestion.reps
    }

    private var logSetMatchesOption: Bool {
        guard hasSelectedOption else { return false }
        if effortMode == .progress || effortMode == nil {
            return filteredSuggestions.contains { $0.weight == weight && $0.reps == reps }
        } else {
            return effortSuggestions.contains { $0.weight == weight && $0.reps == reps }
        }
    }

    private func handleColumnTap(_ column: SortColumn) {
        hapticFeedback.impactOccurred()

        // If tapping the same column (or correlated columns), toggle direction
        if (sortColumn == column) ||
           (sortColumn == .est1RM && column == .gain) ||
           (sortColumn == .gain && column == .est1RM) {
            sortAscending.toggle()
        } else {
            // New column, start with ascending (up arrow)
            sortColumn = column
            sortAscending = true
        }

        // Trigger blink animation
        columnHighlighted = true
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                columnHighlighted = false
            }
        }
    }

    private func handleEffortColumnTap(_ column: EffortSortColumn) {
        hapticFeedback.impactOccurred()
        effortSortUserModified = true

        if effortSortColumn == column {
            effortSortAscending.toggle()
        } else {
            effortSortColumn = column
            effortSortAscending = true
        }

        effortColumnHighlighted = true
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                effortColumnHighlighted = false
            }
        }
    }

    private func effortColumnButton(title: String, column: EffortSortColumn) -> some View {
        Button {
            handleEffortColumnTap(column)
        } label: {
            VStack(spacing: 0) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(effortColumnHighlighted && effortSortColumn == column ? Color.appAccent : Color.appLabel)
                    .animation(.easeInOut(duration: 0.15), value: effortColumnHighlighted)
                if effortSortColumn == column {
                    Image(systemName: effortSortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.appLabel)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.clear)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func highlightWeightColumn() {
        weightColumnHighlighted = true
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                weightColumnHighlighted = false
            }
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

    private func selectOption(_ suggestion: OneRMCalculator.Suggestion) {
        reps = suggestion.reps
        weight = suggestion.weight
        hasSetInitialValues = true
        hasSetWeight = true
        hasSetReps = true
        hasSelectedOption = true
        flashLogSetHighlight()
    }

    private func selectEffortOption(_ suggestion: OneRMCalculator.EffortSuggestion) {
        reps = suggestion.reps
        weight = suggestion.weight
        hasSetInitialValues = true
        hasSetWeight = true
        hasSetReps = true
        hasSelectedOption = true
        flashLogSetHighlight()
    }

    private func flashLogSetHighlight() {
        DispatchQueue.main.async {
            logSetFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                logSetFlash = false
            }
        }
    }

    private func isEffortOptionSelected(_ suggestion: OneRMCalculator.EffortSuggestion) -> Bool {
        return weight == suggestion.weight && reps == suggestion.reps
    }

    private func formatShortDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let dateYear = calendar.component(.year, from: date)
        let currentYear = calendar.component(.year, from: Date())

        let formatter = DateFormatter()
        if dateYear == currentYear {
            formatter.dateFormat = "MMM d"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date)
    }

    private func logSet() {
        guard let ex = selectedExercises else { return }

        let isFirstWeightedSet = setsForExercise.isEmpty && weight > 0

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

        // Create a new Estimated1RM record for every set, storing the running max
        let estimated = Estimated1RM(exercise: ex, value: after, setId: set.id)
        modelContext.insert(estimated)

        // Sync lift set and estimated 1RM to backend
        Task {
            await SyncService.shared.syncLiftSet(set)
            await SyncService.shared.syncEstimated1RM(estimated)
        }

        // First weighted set: defer data refresh until calibration is applied
        if isFirstWeightedSet {
            pendingCalibrationSet = set
            pendingCalibrationEstimated = estimated
            showCalibrationAlert = true
            return
        }

        // Refresh local data after logging
        fetchDataForExercise(ex.id)
        refreshTodaySetCounts()

        // Scroll session view to the newly logged set
        sessionScrollTarget = set.id

        overlayDidIncrease = increased
        overlayDelta = d
        overlayNew1RM = after

        // Calculate intensity color and label for the overlay
        if increased {
            overlayIntensityColor = .setPR
            overlayIntensityLabel = "PR"
        } else if weight == 0 {
            // Check for rep-based PR on zero-weight sets
            let previousMaxReps = setsForExercise
                .filter { $0.id != set.id && $0.weight == 0 }
                .map(\.reps)
                .max() ?? 0
            if reps > previousMaxReps {
                overlayIntensityColor = .setPR
                overlayIntensityLabel = "PR"
            } else {
                // Not a rep PR — color by reps
                switch reps {
                case 12...:
                    overlayIntensityColor = .setNearMax
                    overlayIntensityLabel = "Redline"
                case 9..<12:
                    overlayIntensityColor = .setHard
                    overlayIntensityLabel = "Hard"
                case 6..<9:
                    overlayIntensityColor = .setModerate
                    overlayIntensityLabel = "Moderate"
                default:
                    overlayIntensityColor = .setEasy
                    overlayIntensityLabel = "Easy"
                }
            }
        } else {
            // Weighted exercise - color by percent1RM
            let percent1RM = before > 0 ? OneRMCalculator.estimate1RM(weight: weight, reps: reps) / before : 0
            let bucket = TrendsCalculator.IntensityBucket.from(percent1RM: percent1RM)
            overlayIntensityLabel = (bucket == .pr) ? "Redline" : bucket.rawValue
            switch bucket {
            case .pr: overlayIntensityColor = .setNearMax // not a true PR — downgrade to redline
            case .redline: overlayIntensityColor = .setNearMax
            case .hard: overlayIntensityColor = .setHard
            case .moderate: overlayIntensityColor = .setModerate
            case .easy: overlayIntensityColor = .setEasy
            }
        }

        // Show overlay immediately, then clear/advance effort mode afterward
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            showSubmitOverlay = true
        }

        DispatchQueue.main.async {
            selectedPlanTileIndex = nil
            highlightPlanTile(nil)
            hasSelectedOption = false
            withAnimation { effortMode = nil }

            DispatchQueue.main.async {
                if let next = nextPlannedEffortMode {
                    withAnimation { effortMode = next }
                }
            }
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    showSubmitOverlay = false
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
        estimated.value = calibratedValue

        // Re-sync the updated e1RM to backend
        Task {
            await SyncService.shared.syncEstimated1RM(estimated)
        }

        // Now refresh data (deferred from logSet to avoid stale color flash)
        if let exId = set.exercise?.id {
            fetchDataForExercise(exId)
        }
        refreshTodaySetCounts()
        sessionScrollTarget = set.id

        // Show overlay with calibration result
        overlayDidIncrease = false
        overlayDelta = 0
        overlayNew1RM = calibratedValue
        overlayIntensityColor = effort.tileColor
        overlayIntensityLabel = "Calibrated"

        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            showSubmitOverlay = true
        }

        DispatchQueue.main.async {
            selectedPlanTileIndex = nil
            highlightPlanTile(nil)
            hasSelectedOption = false
            withAnimation { effortMode = nil }

            DispatchQueue.main.async {
                if let next = nextPlannedEffortMode {
                    withAnimation { effortMode = next }
                }
            }
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    showSubmitOverlay = false
                }
            }
        }

        pendingCalibrationSet = nil
        pendingCalibrationEstimated = nil
    }

    private func highlightPlanTile(_ index: Int?) {
        highlightDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            highlightedPlanTileIndex = index
        }
        guard index != nil else { return }
        highlightDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.4)) {
                    highlightedPlanTileIndex = nil
                }
            }
        }
    }

    private func retryFetchExercises() {
        isRetryingSync = true
        Task {
            let success = await SyncService.shared.retryFetchExercises()
            isRetryingSync = false
            if !success && exercises.isEmpty {
                showNoExercisesAlert = true
            }
        }
    }

    private func useDefaultExercises() {
        Task {
            await SyncService.shared.createDefaultExercisesAndSync()
            // Seed default plate weights if needed
            if userProperties.availableChangePlates.isEmpty {
                userProperties.availableChangePlates = UserProperties.defaultAvailableChangePlates
                try? modelContext.save()
            }
            // Assign default exercises to days now that exercises exist
            WorkoutSplitStore.assignDefaultExercisesToDays(context: modelContext)
        }
    }
}

enum ExerciseNavDestination: Hashable {
    case newExercise(prefillName: String)
    case editExercise(exerciseId: UUID)
}

struct NewExerciseFormView: View {
    let initialName: String
    let onCreate: (_ name: String, _ loadType: ExerciseLoadType, _ movementType: ExerciseMovementType, _ icon: String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var loadType: ExerciseLoadType = .barbell
    @State private var movementType: ExerciseMovementType = .other
    @State private var icon: String = "LiftTheBullIcon"

    private let maxNameLength = 25

    init(initialName: String, onCreate: @escaping (_ name: String, _ loadType: ExerciseLoadType, _ movementType: ExerciseMovementType, _ icon: String) -> Void) {
        self.initialName = initialName
        self.onCreate = onCreate
        self._name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                }

                Spacer()

                Text("New Exercise")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    onCreate(name.trimmingCharacters(in: .whitespacesAndNewlines), loadType, movementType, icon)
                    dismiss()
                } label: {
                    Text("Add")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.appAccent)
                        .cornerRadius(20)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)

            ScrollView {
                VStack(spacing: 16) {
                    // Exercise Name Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exercise Name")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        TextField("e.g. Romanian Deadlift", text: $name)
                            .textInputAutocapitalization(.words)
                            .font(.body)
                            .padding(14)
                            .background(Color(white: 0.12))
                            .cornerRadius(10)
                            .foregroundStyle(.white)
                            .onChange(of: name) { _, newValue in
                                if newValue.count > maxNameLength {
                                    name = String(newValue.prefix(maxNameLength))
                                }
                            }
                    }

                    // Load Type Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Load Type")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        Menu {
                            ForEach(ExerciseLoadType.allCases, id: \.self) { type in
                                Button {
                                    loadType = type
                                } label: {
                                    HStack {
                                        Text(type.rawValue)
                                        if loadType == type {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(loadType.rawValue)
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .padding(14)
                            .background(Color(white: 0.12))
                            .cornerRadius(10)
                        }
                    }

                    // Movement Type Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Movement Type")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        Menu {
                            ForEach(ExerciseMovementType.allCases, id: \.self) { type in
                                Button {
                                    movementType = type
                                } label: {
                                    HStack {
                                        Text(type.rawValue)
                                        if movementType == type {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(movementType.rawValue)
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .padding(14)
                            .background(Color(white: 0.12))
                            .cornerRadius(10)
                        }
                    }

                    // Icon Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        IconCarouselPicker(selectedIcon: $icon)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

struct EditExerciseFormView: View {
    let exercise: Exercise
    let onSave: (_ exercise: Exercise, _ name: String, _ movementType: ExerciseMovementType, _ icon: String, _ notes: String?) -> Void
    let onDelete: ((_ exercise: Exercise) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var movementType: ExerciseMovementType
    @State private var icon: String
    @State private var notesInput: String
    @State private var showDeleteSection = false
    @State private var showDeleteConfirmation = false
    @State private var deleteConfirmationChecked = false
    @State private var showNotesCopied = false

    private let maxNameLength = 25
    private let maxNotesLength = 500
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    /// Whether this view is shown inside a NavigationStack (push) or standalone sheet
    let showBackChevron: Bool

    init(exercise: Exercise,
         showBackChevron: Bool = true,
         onSave: @escaping (_ exercise: Exercise, _ name: String, _ movementType: ExerciseMovementType, _ icon: String, _ notes: String?) -> Void,
         onDelete: ((_ exercise: Exercise) -> Void)? = nil) {
        self.exercise = exercise
        self.showBackChevron = showBackChevron
        self.onSave = onSave
        self.onDelete = onDelete
        self._name = State(initialValue: exercise.name)
        self._movementType = State(initialValue: exercise.exerciseMovementType)
        self._icon = State(initialValue: exercise.icon)
        self._notesInput = State(initialValue: exercise.notes ?? "")
    }

    private var hasUnsavedChanges: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameChanged = trimmedName != exercise.name
        let iconChanged = icon != exercise.icon
        let notesChanged = notesInput != (exercise.notes ?? "")
        let movementTypeChanged = movementType != exercise.exerciseMovementType
        guard !trimmedName.isEmpty else { return false }
        return nameChanged || iconChanged || notesChanged || movementTypeChanged
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if showBackChevron {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.appAccent)
                    }
                } else {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.appAccent)
                }

                Spacer()

                Text("Exercise Details")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let currentMovement = movementType
                    let currentIcon = icon
                    let currentNotes = notesInput.isEmpty ? nil : notesInput
                    dismiss()
                    DispatchQueue.main.async {
                        onSave(exercise, trimmed, currentMovement, currentIcon, currentNotes)
                    }
                } label: {
                    Text("Save")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.appAccent)
                        .cornerRadius(20)
                }
                .disabled(!hasUnsavedChanges)
                .opacity(hasUnsavedChanges ? 1.0 : 0.5)
            }
            .padding(.horizontal, 20)
            .padding(.top, showBackChevron ? 20 : 24)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 20) {
                    // Name text field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        TextField("Exercise name", text: $name)
                            .textInputAutocapitalization(.words)
                            .font(.body)
                            .padding(14)
                            .background(Color(white: 0.08))
                            .cornerRadius(10)
                            .foregroundStyle(.white)
                            .onChange(of: name) { _, newValue in
                                if newValue.count > maxNameLength {
                                    name = String(newValue.prefix(maxNameLength))
                                }
                            }

                        HStack {
                            Text("\(name.count) / \(maxNameLength)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                        }
                    }

                    // Load type (read-only)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Load Type")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        Text(exercise.exerciseLoadType.rawValue)
                            .font(.body)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(white: 0.08))
                            .cornerRadius(10)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    // Movement Type
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Movement Type")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        if exercise.isCustom {
                            Menu {
                                ForEach(ExerciseMovementType.allCases, id: \.self) { type in
                                    Button {
                                        movementType = type
                                    } label: {
                                        HStack {
                                            Text(type.rawValue)
                                            if movementType == type {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(movementType.rawValue)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .padding(14)
                                .background(Color(white: 0.08))
                                .cornerRadius(10)
                            }
                        } else {
                            Text(movementType.rawValue)
                                .font(.body)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(white: 0.08))
                                .cornerRadius(10)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    if !exercise.isCustom {
                        Text("Load type and movement type are set by default and can't be changed.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    // Icon Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        IconCarouselPicker(selectedIcon: $icon)
                    }

                    // Notes text field
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Notes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            if !notesInput.isEmpty || !(exercise.notes?.isEmpty ?? true) {
                                Button {
                                    let textToCopy = notesInput.isEmpty ? (exercise.notes ?? "") : notesInput
                                    UIPasteboard.general.string = textToCopy
                                    hapticFeedback.impactOccurred()
                                    withAnimation {
                                        showNotesCopied = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        withAnimation {
                                            showNotesCopied = false
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        if showNotesCopied {
                                            Image(systemName: "checkmark")
                                                .font(.caption2)
                                                .foregroundStyle(Color.appAccent)
                                            Text("Copied")
                                                .font(.caption2)
                                                .foregroundStyle(Color.appAccent)
                                        } else {
                                            Image(systemName: "doc.on.doc")
                                                .font(.subheadline)
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        TextEditor(text: $notesInput)
                            .padding(8)
                            .frame(minHeight: 100)
                            .background(Color(white: 0.08))
                            .cornerRadius(10)
                            .foregroundStyle(.white)
                            .scrollContentBackground(.hidden)
                            .onChange(of: notesInput) { _, newValue in
                                if newValue.count > maxNotesLength {
                                    notesInput = String(newValue.prefix(maxNotesLength))
                                }
                            }

                        HStack {
                            Text("\(notesInput.count) / \(maxNotesLength)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                        }
                    }

                    // Delete section (collapsed by default)
                    if onDelete != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showDeleteSection.toggle()
                                    if !showDeleteSection {
                                        deleteConfirmationChecked = false
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("Delete")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.5))
                                    Spacer()
                                    Image(systemName: showDeleteSection ? "chevron.down" : "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                            }
                            .buttonStyle(.plain)

                            if showDeleteSection {
                                VStack(spacing: 16) {
                                    Text("Deleting an exercise will permanently remove it and all associated workout data. This action cannot be undone.")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    // Confirmation checkbox (centered)
                                    Button {
                                        deleteConfirmationChecked.toggle()
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: deleteConfirmationChecked ? "checkmark.square.fill" : "square")
                                                .foregroundStyle(deleteConfirmationChecked ? .red : .white.opacity(0.5))
                                                .font(.system(size: 20))
                                            Text("I understand this is permanent")
                                                .font(.subheadline)
                                                .foregroundStyle(.white.opacity(0.7))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity)

                                    // Delete button
                                    Button {
                                        showDeleteConfirmation = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "trash")
                                            Text("Delete Exercise")
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(deleteConfirmationChecked ? .white : .white.opacity(0.3))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(deleteConfirmationChecked ? Color.red : Color.red.opacity(0.2))
                                        .cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!deleteConfirmationChecked)
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                            }
                        }
                        .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationBarHidden(true)
        .alert("Delete Exercise?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?(exercise)
            }
        } message: {
            Text("This will permanently delete \"\(exercise.name)\" and all its workout history.")
        }
    }
}

struct ExercisesSelectionView: View {
    let exercises: [Exercise]
    @Binding var selectedExercisesId: UUID?
    var initialDeepLinkExerciseId: UUID? = nil
    let onExerciseCreated: (_ name: String, _ loadType: ExerciseLoadType, _ movementType: ExerciseMovementType, _ icon: String) -> Void
    let onExerciseSaved: (_ exercise: Exercise, _ name: String, _ movementType: ExerciseMovementType, _ icon: String, _ notes: String?) -> Void
    let onExerciseDeleted: (_ exercise: Exercise) -> Void

    @State private var navigationPath = NavigationPath()
    @State private var hasAppliedDeepLink = false
    @State private var searchText = ""
    @State private var collapsedSections: Set<ExerciseMovementType> = []
    @FocusState private var isSearchFocused: Bool

    private var filteredExercises: [Exercise] {
        if searchText.isEmpty {
            return exercises.sorted { $0.name < $1.name }
        }
        return exercises
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name < $1.name }
    }

    private var groupedExercises: [(ExerciseMovementType, [Exercise])] {
        let grouped = Dictionary(grouping: filteredExercises) { $0.exerciseMovementType }
        return ExerciseMovementType.allCases.compactMap { type in
            guard let exercises = grouped[type], !exercises.isEmpty else { return nil }
            return (type, exercises)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.14), Color(white: 0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header with title and add button
                    HStack {
                        Text("Exercise Catalog")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        Spacer()

                        Button {
                            navigationPath.append(ExerciseNavDestination.newExercise(prefillName: searchText.trimmingCharacters(in: .whitespacesAndNewlines)))
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                Text("New")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(Color.appAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.appAccent.opacity(0.15))
                            .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.5))
                            .font(.system(size: 16))

                        TextField("Search exercises", text: $searchText)
                            .foregroundStyle(.white)
                            .tint(Color.appAccent)
                            .focused($isSearchFocused)

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.5))
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.12))
                    .cornerRadius(10)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    if filteredExercises.isEmpty && !searchText.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.3))
                            Text("No exercises found")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.5))
                            Button {
                                navigationPath.append(ExerciseNavDestination.newExercise(prefillName: searchText))
                            } label: {
                                Text("Add \"\(searchText)\" as new exercise")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appAccent)
                            }
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                ForEach(groupedExercises, id: \.0) { movementType, sectionExercises in
                                    VStack(alignment: .leading, spacing: 12) {
                                        // Section header
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                if collapsedSections.contains(movementType) {
                                                    collapsedSections.remove(movementType)
                                                } else {
                                                    collapsedSections.insert(movementType)
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 10) {
                                                Text(movementType.rawValue.uppercased())
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(.white.opacity(0.5))
                                                    .tracking(1.2)

                                                Text("\(sectionExercises.count)")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.white.opacity(0.4))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.white.opacity(0.1))
                                                    .cornerRadius(4)

                                                Rectangle()
                                                    .fill(Color.white.opacity(0.1))
                                                    .frame(height: 1)

                                                Image(systemName: collapsedSections.contains(movementType) ? "chevron.right" : "chevron.down")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(.white.opacity(0.4))
                                            }
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 6)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)

                                        // Exercise rows
                                        if !collapsedSections.contains(movementType) {
                                            VStack(spacing: 8) {
                                                ForEach(sectionExercises) { exercise in
                                                    ExerciseRowView(
                                                        exercise: exercise,
                                                        isSelected: selectedExercisesId == exercise.id,
                                                        onSelect: {
                                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                            if selectedExercisesId == exercise.id {
                                                                selectedExercisesId = nil
                                                            } else {
                                                                selectedExercisesId = exercise.id
                                                            }
                                                        },
                                                        onEdit: {
                                                            navigationPath.append(ExerciseNavDestination.editExercise(exerciseId: exercise.id))
                                                        }
                                                    )
                                                }
                                            }
                                            .padding(.horizontal, 20)
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarHidden(true)
            .navigationDestination(for: ExerciseNavDestination.self) { destination in
                switch destination {
                case .newExercise(let prefillName):
                    NewExerciseFormView(initialName: prefillName) { name, loadType, movementType, icon in
                        onExerciseCreated(name, loadType, movementType, icon)
                    }
                case .editExercise(let exerciseId):
                    if let exercise = exercises.first(where: { $0.id == exerciseId }) {
                        EditExerciseFormView(
                            exercise: exercise,
                            onSave: { exercise, name, movementType, icon, notes in
                                onExerciseSaved(exercise, name, movementType, icon, notes)
                            },
                            onDelete: { exercise in
                                onExerciseDeleted(exercise)
                            }
                        )
                    }
                }
            }
            .onAppear {
                if !hasAppliedDeepLink, let deepLinkId = initialDeepLinkExerciseId {
                    hasAppliedDeepLink = true
                    navigationPath.append(ExerciseNavDestination.editExercise(exerciseId: deepLinkId))
                }
            }
        }
    }
}

struct ExerciseRowView: View {
    let exercise: Exercise
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Left: selection toggle
            Button {
                onSelect()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.appAccent : .white.opacity(0.3))
            }
            .buttonStyle(.plain)

            // Center: icon + name + subtitle → taps into detail
            Button { onEdit() } label: {
                HStack(spacing: 12) {
                    ExerciseIconView(exercise: exercise, size: 32)
                        .foregroundStyle(Color.appAccent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(exercise.exerciseLoadType.rawValue) · \(exercise.exerciseMovementType.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.14)], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.appAccent : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        )
    }
}

struct SetSquareView: View {
    @Environment(\.modelContext) private var modelContext
    let set: LiftSet
    let allSets: [LiftSet]
    let currentWeight: Double
    let currentReps: Int
    let hasSetValues: Bool
    let selectedSquareId: UUID?
    let allEstimated1RM: [Estimated1RM]
    var onDelete: (() -> Void)? = nil

    private var isMatching: Bool {
        guard hasSetValues else { return false }
        return abs(set.weight - currentWeight) < 0.01 && set.reps == currentReps
    }

    private var isSelected: Bool {
        selectedSquareId == set.id
    }

    private var colorAndPR: (color: Color, isPR: Bool) {
        // Baseline sets — color by reported effort, never PR
        if set.isBaselineSet {
            let baselineE1RM = allEstimated1RM.first(where: { $0.setId == set.id })?.value ?? 0
            let rawEstimate = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)
            let pct = baselineE1RM > 0 ? rawEstimate / baselineE1RM : 0
            let bucket = TrendsCalculator.IntensityBucket.from(percent1RM: pct)
            let c: Color
            switch bucket {
            case .pr, .redline: c = .setNearMax
            case .hard: c = .setHard
            case .moderate: c = .setModerate
            case .easy: c = .setEasy
            }
            return (color: c, isPR: false)
        }

        // Use the latest Estimated1RM record before this set as the reference max
        let priorE1RM = allEstimated1RM
            .filter { $0.createdAt < set.createdAt }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        let currentMax = priorE1RM?.value ?? 0

        let setEstimated1RM = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)

        // For 0-weight sets, use rep-based comparison for PR
        let isPR: Bool
        if set.weight == 0 {
            let previousSets = allSets
                .filter { $0.exercise?.id == set.exercise?.id && $0.createdAt < set.createdAt }
            let maxReps = previousSets.map(\.reps).max() ?? 0
            isPR = set.reps > maxReps
        } else {
            isPR = (setEstimated1RM - currentMax) > 0.0001
        }

        let color: Color
        if isPR {
            color = .setPR
        } else if set.weight == 0 {
            switch set.reps {
            case 12...:
                color = .setNearMax
            case 9..<12:
                color = .setHard
            case 6..<9:
                color = .setModerate
            default:
                color = .setEasy
            }
        } else {
            // percent1RM-based effort coloring
            let percent1RM = currentMax > 0 ? setEstimated1RM / currentMax : 0
            let bucket = TrendsCalculator.IntensityBucket.from(percent1RM: percent1RM)
            switch bucket {
            case .pr: color = .setNearMax // not a true PR — downgrade to redline
            case .redline: color = .setNearMax
            case .hard: color = .setHard
            case .moderate: color = .setModerate
            case .easy: color = .setEasy
            }
        }

        return (color: color, isPR: isPR)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(set.weight))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Text("\(set.reps)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: 42, height: 42)
        .background(colorAndPR.color.opacity(0.3))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(colorAndPR.color, lineWidth: 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.appAccent, lineWidth: isSelected ? 3 : 0)
                .animation(.easeInOut(duration: 0.15), value: isSelected)
        )
        .contextMenu {
            Button(role: .destructive) {
                deleteSet()
            } label: {
                Label("Delete Set", systemImage: "trash")
            }
        }
    }

    private func deleteSet() {
        let setId = set.id

        // Soft delete the set
        set.deleted = true

        // Find and soft delete associated Estimated1RM if it exists
        var estimated1RMId: UUID? = nil
        if let associated1RM = allEstimated1RM.first(where: { $0.setId == setId }) {
            associated1RM.deleted = true
            estimated1RMId = associated1RM.id
        }

        try? modelContext.save()

        // Sync deletes to backend
        Task {
            await SyncService.shared.deleteLiftSet(setId)
            if estimated1RMId != nil {
                await SyncService.shared.deleteEstimated1RM(estimated1RMId: estimated1RMId!, liftSetId: setId)
            }
        }

        onDelete?()
    }
}

struct DemoSetSquare: View {
    let color: Color

    private var actualColor: Color {
        switch color {
        case .green:
            return .setEasy
        case .yellow:
            return .setModerate
        case .orange:
            return .setHard
        case .red:
            return .setNearMax
        default:
            return color
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(actualColor.opacity(0.3))
            .frame(width: 42, height: 42)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(actualColor, lineWidth: 1.5)
            )
    }
}

struct SequenceSquareView: View {
    let effort: String
    var isHighlighted: Bool = false

    static func color(for effort: String) -> Color {
        switch effort {
        case "easy": return .setEasy
        case "moderate": return .setModerate
        case "hard": return .setHard
        case "redline": return .setNearMax
        case "pr": return .setPR
        default: return .setEasy
        }
    }

    private var effortColor: Color { Self.color(for: effort) }

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(effortColor.opacity(isHighlighted ? 0.5 : 0.3))
            .frame(width: 42, height: 42)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHighlighted ? Color.yellow : effortColor, lineWidth: isHighlighted ? 2.5 : 1.5)
            )
            .animation(.easeInOut(duration: 0.15), value: isHighlighted)
    }
}

struct ProgressOptionsEmptyState: View {
    var message: String? = "Log your first set below"
    var showPRIndicator: Bool = false

    @State private var appeared = false
    @State private var pulsing = false

    private var isPR: Bool {
        showPRIndicator && message == nil
    }

    private var accentColor: Color {
        isPR ? .setPR : .appLogoColor
    }

    var body: some View {
        ZStack {
            // Subtle radial gradient background
            RadialGradient(
                colors: [
                    accentColor.opacity(isPR ? 0.12 : 0.08),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 80
            )

            // Content — offset down to visually center below chips row
            VStack(spacing: 14) {
                // Lift the Bull logo with subtle glow
                Image("LiftTheBullIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .foregroundStyle(accentColor)
                    .shadow(color: accentColor.opacity(isPR ? 0.5 : 0.3), radius: isPR ? 20 : 14, x: 0, y: 0)
                    .scaleEffect(isPR ? (appeared ? 1.0 : 0.6) : 1.0)
                    .scaleEffect(pulsing ? 1.05 : 1.0)
                    .animation(isPR ? .spring(response: 0.4, dampingFraction: 0.6) : nil, value: appeared)
                    .animation(isPR ? .easeInOut(duration: 0.3).repeatCount(5, autoreverses: true) : nil, value: pulsing)

                if let message {
                    Text(message)
                        .font(.bebasNeue(size: 20))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                } else if showPRIndicator {
                    VStack(spacing: 4) {
                        Text("e1RM PR")
                            .font(.bebasNeue(size: 22))
                            .foregroundStyle(Color.setPR)
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)
                        Text("New Estimated 1RM Today")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.4).delay(0.5), value: appeared)
                    }
                    .padding(.top, 6)
                }
            }
            .offset(y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if isPR {
                appeared = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    pulsing = true
                }
            }
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Weight Plate Icon

struct WeightPlateIcon: View {
    var size: CGFloat = 16
    var color: Color = .white.opacity(0.5)

    var body: some View {
        ZStack {
            // Outer plate
            Circle()
                .stroke(color, lineWidth: size * 0.15)
                .frame(width: size, height: size)
            // Inner ring
            Circle()
                .stroke(color, lineWidth: size * 0.1)
                .frame(width: size * 0.55, height: size * 0.55)
            // Center hole
            Circle()
                .fill(color)
                .frame(width: size * 0.18, height: size * 0.18)
        }
    }
}

// MARK: - Expanded Progress Options Sheet

struct ExpandedProgressOptionsSheet: View {
    let suggestions: [OneRMCalculator.Suggestion]
    @Binding var sortColumn: CheckInView.SortColumn
    @Binding var sortAscending: Bool
    @Binding var weightDelta: Double
    let availableWeightDeltas: [Double]
    let minWeightDelta: Double
    let maxWeightDelta: Double
    @Binding var minReps: Int
    @Binding var maxReps: Int
    let onRepRangeChanged: () -> Void
    let onSelect: (OneRMCalculator.Suggestion) -> Void
    var onSwitchMode: ((CheckInView.EffortMode) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var columnHighlighted = false
    @State private var selectedSuggestion: OneRMCalculator.Suggestion?
    @State private var showChangePlates = false
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    private var sortedSuggestions: [OneRMCalculator.Suggestion] {
        switch sortColumn {
        case .weight:
            return suggestions.sorted { sortAscending ? $0.weight < $1.weight : $0.weight > $1.weight }
        case .reps:
            return suggestions.sorted { sortAscending ? $0.reps < $1.reps : $0.reps > $1.reps }
        case .est1RM, .gain:
            return suggestions.sorted { sortAscending ? $0.projected1RM < $1.projected1RM : $0.projected1RM > $1.projected1RM }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title header with mode navigation
            VStack(spacing: 8) {
                HStack {
                    // Left chevron (Hard is previous mode)
                    Button {
                        hapticFeedback.impactOccurred()
                        onSwitchMode?(.hard)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(spacing: 4) {
                        Text("Progress Options")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        HStack(spacing: 3) {
                            Text("Sets to")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("Estimated 1RM")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }

                    Spacer()

                    // No right chevron (Progress is last)
                    Spacer().frame(width: 44)
                }

                // Δ LB increment controls
                HStack(spacing: 10) {
                    Button {
                        if let currentIndex = availableWeightDeltas.firstIndex(where: { abs($0 - weightDelta) < 0.01 }),
                           currentIndex > 0 {
                            weightDelta = availableWeightDeltas[currentIndex - 1]
                            hapticFeedback.impactOccurred()
                            highlightWeightColumn()
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(weightDelta > minWeightDelta ? Color.appAccent : .gray)
                    }

                    VStack(spacing: 0) {
                        Text(weightDelta.formatted(.number.precision(.fractionLength(1))))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Δ LB")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.appLabel)
                    }
                    .frame(width: 45)

                    Button {
                        if let currentIndex = availableWeightDeltas.firstIndex(where: { abs($0 - weightDelta) < 0.01 }),
                           currentIndex < availableWeightDeltas.count - 1 {
                            weightDelta = availableWeightDeltas[currentIndex + 1]
                            hapticFeedback.impactOccurred()
                            highlightWeightColumn()
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(weightDelta < maxWeightDelta ? Color.appAccent : .gray)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(white: 0.12))
                .cornerRadius(10)

                Button {
                    showChangePlates = true
                } label: {
                    Text("Edit Change Plates ›")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }

                // Rep range slider
                HStack {
                    Text("e1RM ↑")
                        .foregroundStyle(Color.setPR)
                        .font(.caption)
                    Spacer()
                    Text("\(minReps)–\(maxReps) reps")
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                RangeSliderView(
                    minValue: Binding(
                        get: { Double(minReps) },
                        set: { minReps = Int($0); onRepRangeChanged() }
                    ),
                    maxValue: Binding(
                        get: { Double(maxReps) },
                        set: { maxReps = Int($0); onRepRangeChanged() }
                    ),
                    bounds: 1...12,
                    minSpan: Double(UserProperties.minRepRangeSpan)
                )
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.top, 8)

            // Header row with column labels
            HStack(spacing: 12) {
                columnButton(title: "WEIGHT", column: .weight, width: 65)
                Spacer().frame(width: 1)
                columnButton(title: "REPS", column: .reps, width: 50)
                Spacer().frame(width: 1)
                columnButton(title: "e1RM", column: .est1RM, width: 60)
                Spacer().frame(width: 1)
                columnButton(title: "GAIN", column: .gain, width: 65)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.12))
            .cornerRadius(10)
            .padding(.horizontal, 8)

            // Scrollable options list
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(sortedSuggestions) { suggestion in
                        ProgressOptionCard(
                            suggestion: suggestion,
                            isSelected: selectedSuggestion?.id == suggestion.id,
                            sortColumn: sortColumn,
                            columnHighlighted: columnHighlighted
                        )
                        .onTapGesture {
                            hapticFeedback.impactOccurred()
                            selectedSuggestion = suggestion
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Done button
            Button {
                if let selected = selectedSuggestion {
                    onSelect(selected)
                }
                dismiss()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appAccent)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .sheet(isPresented: $showChangePlates) {
            AvailableChangePlatesView()
                .presentationDetents([.height(480), .large])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
        }
    }

    private func columnButton(title: String, column: CheckInView.SortColumn, width: CGFloat) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = true
            }
            hapticFeedback.impactOccurred()

            // Fleeting highlight
            columnHighlighted = true
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    columnHighlighted = false
                }
            }
        } label: {
            VStack(spacing: 0) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(sortColumn == column ? Color.appAccent : Color.appLabel)
                if sortColumn == column || (column == .est1RM && sortColumn == .gain) || (column == .gain && sortColumn == .est1RM) {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.appLabel)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.clear)
                }
            }
            .frame(width: width, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func highlightWeightColumn() {
        columnHighlighted = true
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                columnHighlighted = false
            }
        }
    }
}

// MARK: - Expanded Effort Options Sheet

struct ExpandedEffortOptionsSheet: View {
    let effortMode: CheckInView.EffortMode
    let suggestions: [OneRMCalculator.EffortSuggestion]
    @Binding var repRangeMin: Int
    @Binding var repRangeMax: Int
    let onRepRangeChanged: () -> Void
    var lastSetMatch: (weight: Double, reps: Int)? = nil
    let onSelect: (OneRMCalculator.EffortSuggestion) -> Void
    var onSwitchMode: ((CheckInView.EffortMode) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSuggestion: OneRMCalculator.EffortSuggestion?
    @State private var sortColumn: CheckInView.EffortSortColumn = .weight
    @State private var sortAscending: Bool = true
    @State private var columnHighlighted = false
    @State private var sheetSortUserModified: Bool = false
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    private var sortedSuggestions: [OneRMCalculator.EffortSuggestion] {
        var sorted: [OneRMCalculator.EffortSuggestion]
        switch sortColumn {
        case .weight:
            sorted = suggestions.sorted { sortAscending ? $0.weight < $1.weight : $0.weight > $1.weight }
        case .reps:
            sorted = suggestions.sorted { sortAscending ? $0.reps < $1.reps : $0.reps > $1.reps }
        case .percent1RM:
            sorted = suggestions.sorted { sortAscending ? $0.percent1RM < $1.percent1RM : $0.percent1RM > $1.percent1RM }
        }
        if !sheetSortUserModified, let match = lastSetMatch {
            if let idx = sorted.firstIndex(where: { $0.weight == match.weight && $0.reps == match.reps }), idx > 0 {
                let item = sorted.remove(at: idx)
                sorted.insert(item, at: 0)
            }
        }
        return sorted
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title header with mode navigation
            VStack(spacing: 8) {
                HStack {
                    // Left chevron
                    if let prev = previousMode {
                        Button {
                            hapticFeedback.impactOccurred()
                            onSwitchMode?(prev)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Spacer().frame(width: 44)
                    }

                    Spacer()

                    // Title
                    VStack(spacing: 4) {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(effortMode.tileColor.opacity(0.3))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(effortMode.tileColor, lineWidth: 1.5)
                                )
                            Text(effortMode.title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        Text(effortMode.subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    // Right chevron
                    if let next = nextMode {
                        Button {
                            hapticFeedback.impactOccurred()
                            onSwitchMode?(next)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Spacer().frame(width: 44)
                    }
                }

                // Rep range slider
                HStack {
                    Text(effortMode.title)
                        .foregroundStyle(effortMode.tileColor)
                        .font(.caption)
                    Spacer()
                    Text("\(repRangeMin)–\(repRangeMax) reps")
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                RangeSliderView(
                    minValue: Binding(
                        get: { Double(repRangeMin) },
                        set: { repRangeMin = Int($0); onRepRangeChanged() }
                    ),
                    maxValue: Binding(
                        get: { Double(repRangeMax) },
                        set: { repRangeMax = Int($0); onRepRangeChanged() }
                    ),
                    bounds: 1...12,
                    minSpan: Double(UserProperties.minRepRangeSpan)
                )
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.top, 8)

            // Sortable header row
            HStack(spacing: 0) {
                sheetColumnButton(title: "WEIGHT", column: .weight)
                sheetColumnButton(title: "REPS", column: .reps)
                sheetColumnButton(title: "e1RM %", column: .percent1RM)
            }
            .frame(height: 24)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.12))
            .cornerRadius(10)
            .padding(.horizontal, 8)

            // Scrollable list
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(sortedSuggestions) { suggestion in
                        EffortOptionCard(
                            suggestion: suggestion,
                            isSelected: selectedSuggestion?.id == suggestion.id,
                            sortColumn: sortColumn,
                            columnHighlighted: columnHighlighted,
                            accentColor: effortMode.tileColor,
                            isLastSet: lastSetMatch.map { $0.weight == suggestion.weight && $0.reps == suggestion.reps } ?? false
                        )
                        .onTapGesture {
                            hapticFeedback.impactOccurred()
                            selectedSuggestion = suggestion
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Done button
            Button {
                if let selected = selectedSuggestion {
                    onSelect(selected)
                }
                dismiss()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appAccent)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 40)
            .padding(.top, lastSetMatch != nil ? 12 : 24)
            .padding(.bottom, 16)

            if lastSetMatch != nil {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Last set with this effort")
                        .font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 8)
            }
        }
        .background(
            LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var previousMode: CheckInView.EffortMode? {
        let cases = CheckInView.EffortMode.allCases
        guard let idx = cases.firstIndex(of: effortMode), idx > 0 else { return nil }
        return cases[idx - 1]
    }

    private var nextMode: CheckInView.EffortMode? {
        let cases = CheckInView.EffortMode.allCases
        guard let idx = cases.firstIndex(of: effortMode), idx < cases.count - 1 else { return nil }
        return cases[idx + 1]
    }

    private func sheetColumnButton(title: String, column: CheckInView.EffortSortColumn) -> some View {
        Button {
            hapticFeedback.impactOccurred()
            sheetSortUserModified = true
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = true
            }
            columnHighlighted = true
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { columnHighlighted = false }
            }
        } label: {
            VStack(spacing: 0) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(columnHighlighted && sortColumn == column ? Color.appAccent : Color.appLabel)
                    .animation(.easeInOut(duration: 0.15), value: columnHighlighted)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.appLabel)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.clear)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Available Change Plates View (Settings)

struct AvailableChangePlatesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var userPropertiesItems: [UserProperties]

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var plateWeights: [Double] {
        userProperties.availableChangePlates.filter { $0 < 5 }.sorted()
    }

    private let allPlateOptions: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 2.0]

    private func isPlateActive(_ plate: Double) -> Bool {
        return plateWeights.contains { abs($0 - plate) < 0.01 }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Available Change Plates")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Plates smaller than 2.5 lbs for fine-tuning increments")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    BarbellPlateIcon(size: 48)
                        .foregroundStyle(Color.appAccent.opacity(0.8))
                        .padding(.top, 8)
                }
                .padding(.top, 40)
                .padding(.bottom, 32)

                FlowLayout(spacing: 12, centered: true) {
                    ForEach(allPlateOptions, id: \.self) { plate in
                        ChangePlateBubble(
                            plate: plate,
                            isActive: isPlateActive(plate),
                            onToggle: {
                                hapticFeedback.impactOccurred()
                                togglePlate(plate)
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.appAccent)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .padding(.bottom, 16)

                Text("In addition to 5 LB, barbell exercises will have increment options that are 2X the available change plates.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
    }

    private func togglePlate(_ plate: Double) {
        if isPlateActive(plate) {
            userProperties.availableChangePlates.removeAll { abs($0 - plate) < 0.01 }
        } else {
            userProperties.availableChangePlates.append(plate)
        }
        try? modelContext.save()

        Task {
            await SyncService.shared.updateChangePlates(userProperties.availableChangePlates)
        }
    }
}

// MARK: - Change Plates View (CheckIn)

struct ChangePlatesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var userPropertiesItems: [UserProperties]
    @Binding var selectedIncrement: Double?
    let availableWeightDeltas: [Double]
    let minWeightDelta: Double
    let maxWeightDelta: Double

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    init(
        selectedIncrement: Binding<Double?> = .constant(nil),
        availableWeightDeltas: [Double] = [5.0],
        minWeightDelta: Double = 5.0,
        maxWeightDelta: Double = 5.0
    ) {
        self._selectedIncrement = selectedIncrement
        self.availableWeightDeltas = availableWeightDeltas
        self.minWeightDelta = minWeightDelta
        self.maxWeightDelta = maxWeightDelta
    }

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    // Available plate weights that produce increments (increment = 2 * plate)
    private var plateWeights: [Double] {
        userProperties.availableChangePlates.filter { $0 < 5 }.sorted()
    }

    // All possible plate options (excluding 2.5 since 5 lb is always available)
    private let allPlateOptions: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 2.0]

    private func isPlateActive(_ plate: Double) -> Bool {
        return plateWeights.contains { abs($0 - plate) < 0.01 }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with plate icon
                VStack(spacing: 8) {
                    Text("Change Plates")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    BarbellPlateIcon(size: 48)
                        .foregroundStyle(Color.appAccent.opacity(0.8))
                        .padding(.top, 4)
                }
                .padding(.top, 40)
                .padding(.bottom, 28)

                // Current Increment Section
                VStack(spacing: 12) {
                    Text("Current Increment")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    HStack(spacing: 16) {
                        Button {
                            if let current = selectedIncrement,
                               let currentIndex = availableWeightDeltas.firstIndex(where: { abs($0 - current) < 0.01 }),
                               currentIndex > 0 {
                                selectedIncrement = availableWeightDeltas[currentIndex - 1]
                                hapticFeedback.impactOccurred()
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle((selectedIncrement ?? 5.0) > minWeightDelta ? Color.appAccent : .gray)
                        }

                        VStack(spacing: 2) {
                            Text((selectedIncrement ?? 5.0).formatted(.number.precision(.fractionLength(2))))
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.white)
                            Text("LB")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appLabel)
                        }
                        .frame(width: 90)

                        Button {
                            if let current = selectedIncrement,
                               let currentIndex = availableWeightDeltas.firstIndex(where: { abs($0 - current) < 0.01 }),
                               currentIndex < availableWeightDeltas.count - 1 {
                                selectedIncrement = availableWeightDeltas[currentIndex + 1]
                                hapticFeedback.impactOccurred()
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle((selectedIncrement ?? 5.0) < maxWeightDelta ? Color.appAccent : .gray)
                        }
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 24)
                .background(Color(white: 0.18))
                .cornerRadius(16)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Available Section
                VStack(spacing: 16) {
                    Text("Available")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    FlowLayout(spacing: 12, centered: true) {
                        ForEach(allPlateOptions, id: \.self) { plate in
                            ChangePlateBubble(
                                plate: plate,
                                isActive: isPlateActive(plate),
                                onToggle: {
                                    hapticFeedback.impactOccurred()
                                    togglePlate(plate)
                                }
                            )
                        }
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 24)
                .background(Color(white: 0.18))
                .cornerRadius(16)
                .padding(.horizontal, 20)

                Spacer()

                // Done button
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.appAccent)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .padding(.bottom, 16)

                // Footer text
                Text("In addition to 5 LB, barbell exercises will have increment options that are 2X the available change plates.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
    }

    private func togglePlate(_ plate: Double) {
        if isPlateActive(plate) {
            // Remove plate
            userProperties.availableChangePlates.removeAll { abs($0 - plate) < 0.01 }
            // If current selection was this increment, default to 5
            if let current = selectedIncrement {
                let increment = plate * 2
                if abs(current - increment) < 0.01 {
                    selectedIncrement = 5.0
                }
            }
        } else {
            // Add plate
            userProperties.availableChangePlates.append(plate)
        }
        try? modelContext.save()

        // Sync to backend
        Task {
            await SyncService.shared.updateChangePlates(userProperties.availableChangePlates)
        }
    }
}

struct BarbellPlateIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Outer plate circle
            Circle()
                .fill(.primary)

            // Inner rim (slightly darker/recessed look)
            Circle()
                .fill(.primary.opacity(0.7))
                .frame(width: size * 0.72, height: size * 0.72)

            // Raised inner ring
            Circle()
                .stroke(.primary, lineWidth: size * 0.06)
                .frame(width: size * 0.55, height: size * 0.55)

            // Center hole (dark/empty)
            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: size * 0.22, height: size * 0.22)
        }
        .frame(width: size, height: size)
    }
}

struct ChangePlateBubble: View {
    let plate: Double
    let isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            onToggle()
        } label: {
            Text(formatPlate(plate))
                .font(.body.weight(.semibold))
                .foregroundStyle(isActive ? .black : .white)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(isActive ? Color.appAccent : Color(white: 0.22))
                )
                .overlay(
                    Capsule()
                        .stroke(isActive ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func formatPlate(_ value: Double) -> String {
        if value == floor(value) {
            return "\(Int(value)) lb"
        } else {
            return "\(value.formatted(.number.precision(.fractionLength(1...2)))) lb"
        }
    }
}

// Simple flow layout for wrapping bubbles
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var centered: Bool = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing, centered: centered)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing, centered: centered)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat, centered: Bool) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            var rowStartIndex = 0
            var rowWidth: CGFloat = 0

            for (index, subview) in subviews.enumerated() {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    // Center the completed row if needed
                    if centered {
                        let offset = (maxWidth - rowWidth + spacing) / 2
                        for i in rowStartIndex..<index {
                            positions[i].x += offset
                        }
                    }

                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                    rowStartIndex = index
                    rowWidth = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                rowWidth = x + size.width
                x += size.width + spacing
            }

            // Center the last row if needed
            if centered && !subviews.isEmpty {
                let offset = (maxWidth - rowWidth + spacing) / 2
                for i in rowStartIndex..<subviews.count {
                    positions[i].x += offset
                }
            }

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}
