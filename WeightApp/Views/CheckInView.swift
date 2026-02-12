import SwiftUI
import SwiftData
import Charts

struct CheckInView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var today = Calendar.current.startOfDay(for: Date())

    @Query(filter: #Predicate<Exercises> { !$0.deleted }, sort: \Exercises.createdAt) private var exercises: [Exercises]
    @Query(filter: #Predicate<LiftSet> { !$0.deleted }, sort: \LiftSet.createdAt, order: .reverse) private var allSets: [LiftSet]
    @Query private var userPropertiesItems: [UserProperties]
    @Query(filter: #Predicate<Estimated1RM> { !$0.deleted }, sort: \Estimated1RM.createdAt, order: .reverse) private var allEstimated1RMs: [Estimated1RM]

    @ObservedObject var selectedSetData: SelectedSetData
    var initialExerciseId: UUID? = nil

    @State private var selectedExercisesId: UUID?
    @State private var hasAppliedInitialExercise = false
    @State private var showingAddExercises = false

    @State private var reps: Int = 8
    @State private var weight: Double = 20.0
    @State private var hasSetInitialValues = false
    @State private var hasSetWeight = false
    @State private var hasSetReps = false

    @State private var newExercisesName: String = ""
    @State private var newExercisesLoadType: ExerciseLoadType = .barbell
    @State private var newExercisesIcon: String = "LiftTheBullIcon"

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
    @State private var showExercisesDetails = false
    @State private var editingExercisesName = ""
    @State private var editingExercisesLoadType: ExerciseLoadType = .barbell
    @State private var showLogConfirmation = false
    @State private var showCancelOverlay = false
    @State private var weightDelta: Double = 5.0
    @State private var showExercisesSelection = false
    @State private var selectedGraphTab: Int = 0 // 0 = Set Intensity, 1 = 1RM Graph
    @State private var showPROnly: Bool = false
    @State private var logSetHighlighted = false
    @State private var selectedSquareId: UUID? = nil
    @State private var showBodyweightCapture = false
    @State private var tempBodyweight: Double = 0
    @State private var showEditExerciseName = false
    @State private var editExerciseNameInput: String = ""
    @State private var editingExerciseIcon: String = "LiftTheBullIcon"
    @State private var exerciseNotesInput: String = ""
    @State private var showNotesCopied = false
    @State private var showNoExercisesAlert = false
    @State private var isRetryingSync = false
    @State private var showDeleteSection = false
    @State private var showDeleteConfirmation = false
    @State private var deleteConfirmationChecked = false
    @State private var showIncrementSelection = false
    @State private var showExpandedProgressOptions = false

    enum SortColumn {
        case weight, reps, est1RM, gain
    }
    @State private var sortColumn: SortColumn = .gain
    @State private var sortAscending: Bool = true
    @State private var columnHighlighted = false

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    private let maxNotesLength = 500
    private let maxExercisesNameLength = 25
    private let lastSelectedExerciseKey = "lastSelectedExerciseId"

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var availablePlates: [Double] {
        userProperties.availableChangePlates.sorted { $0 > $1 }
    }

    private var selectedExercises: Exercises? {
        guard let id = selectedExercisesId else { return nil }
        return exercises.first(where: { $0.id == id })
    }

    private var setsForSelected: [LiftSet] {
        guard let ex = selectedExercises else { return [] }
        return allSets.filter { $0.exercise?.id == ex.id }
    }

    private var estimated1RMsForSelected: [Estimated1RM] {
        guard let ex = selectedExercises else { return [] }
        return allEstimated1RMs.filter { $0.exercise?.id == ex.id }
    }

    private var hasUnsavedExerciseChanges: Bool {
        guard let ex = selectedExercises else { return false }
        let trimmedName = editExerciseNameInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // Read all @State vars before any early return so SwiftUI tracks them as dependencies
        let nameChanged = trimmedName != ex.name
        let iconChanged = editingExerciseIcon != ex.icon
        let notesChanged = exerciseNotesInput != (ex.notes ?? "")

        guard !trimmedName.isEmpty else { return false }
        return nameChanged || iconChanged || notesChanged
    }

    private struct SetWithPR {
        let set: LiftSet
        let estimated1RM: Double
        let wasPR: Bool
        let percentageOfCurrent: Double
    }

    private var setsWithPRInfo: [SetWithPR] {
        guard let ex = selectedExercises else { return [] }
        // Get all sets for this exercise in chronological order (oldest first)
        // Filter for valid sets (weight >= 0, reps >= 1)
        let sets = allSets
            .filter { $0.exercise?.id == ex.id && $0.weight >= 0 && $0.reps >= 1 }
            .reversed()

        var result: [SetWithPR] = []
        var currentMax: Double = 0
        var maxReps: Int = 0

        for set in sets {
            let estimated = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)

            // For 0-weight sets, PR is based on reps; otherwise based on 1RM
            let wasPR: Bool
            if set.weight == 0 {
                wasPR = set.reps > maxReps
            } else {
                wasPR = estimated > currentMax
            }

            // Calculate percentage of current 1RM (before this set)
            let percentage = currentMax > 0 ? (estimated / currentMax) * 100 : 100.0

            if wasPR {
                currentMax = max(currentMax, estimated)
                maxReps = max(maxReps, set.reps)
            }
            result.append(SetWithPR(set: set, estimated1RM: estimated, wasPR: wasPR, percentageOfCurrent: percentage))
        }

        return result
    }

    private var current1RM: Double {
        // Use the latest Estimated1RM if available, otherwise calculate from sets
        if let latest = estimated1RMsForSelected.first {
            return latest.value
        }
        return OneRMCalculator.current1RM(from: setsForSelected)
    }

    private var lastPRPlusOneSuggestion: OneRMCalculator.Suggestion? {
        guard let lastPR = setsWithPRInfo.last(where: { $0.wasPR }),
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
        NavigationStack {
            ZStack {
                // Main content
                VStack(spacing: 12) {
                    // Styled Exercises Selector
                    styledExercisesSelector
                        .padding(.top, 12)

                    // Estimated 1RM Graph
                    estimated1RMGraphWidget

                    // Progress Options
                    optionsSection

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
                    SubmitOverlayView(
                        didIncrease: overlayDidIncrease,
                        delta: overlayDelta,
                        new1RM: overlayNew1RM,
                        intensityLabel: overlayIntensityLabel,
                        intensityColor: overlayIntensityColor
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
                    .allowsHitTesting(false)
                }

                if showCancelOverlay {
                    CancelOverlayView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
                            showCancelOverlay = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                await MainActor.run {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        showCancelOverlay = false
                                    }
                                }
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(11)
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
            }
            .onChange(of: selectedExercisesId) { _, newId in
                resetToDefaults()
                validateWeightDelta()
                // Save selected exercise to UserDefaults
                if let id = newId {
                    UserDefaults.standard.set(id.uuidString, forKey: lastSelectedExerciseKey)
                }
            }
            .onChange(of: selectedSetData.shouldPopulate) { _, shouldPopulate in
                if shouldPopulate {
                    populateFromSelectedSet()
                    selectedSetData.shouldPopulate = false
                }
            }
            .onChange(of: showBodyweightCapture) { _, isShowing in
                if isShowing {
                    tempBodyweight = userProperties.bodyweight ?? 0
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    let currentDay = Calendar.current.startOfDay(for: Date())
                    if currentDay != today {
                        today = currentDay
                    }
                }
            }
            .sheet(isPresented: $showingAddExercises) {
                addExercisesSheet
                    .presentationDetents([.fraction(0.92)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showWeightPicker) {
                weightPickerSheet
                    .presentationDetents([.height(500)])
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
            .sheet(isPresented: $showExercisesDetails) {
                exerciseDetailsSheet
                    .presentationDetents([.height(selectedExercises?.isCustom == true ? 420 : 340)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showExercisesSelection) {
                ExercisesSelectionView(
                    exercises: exercises,
                    selectedExercisesId: $selectedExercisesId,
                    onAddExercises: {
                        showExercisesSelection = false
                        showingAddExercises = true
                    },
                    onEditExercises: { exercise in
                        showExercisesSelection = false
                        editingExercisesName = exercise.name
                        editingExercisesLoadType = exercise.exerciseLoadType
                        showExercisesDetails = true
                    }
                )
                .presentationDetents([.large])
                .interactiveDismissDisabled(false)
                .presentationDragIndicator(.visible)
            }
                .sheet(isPresented: $showBodyweightCapture) {
                    bodyweightCaptureSheet
                        .presentationDetents([.height(500)])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showEditExerciseName) {
                    editExerciseNameSheet
                        .presentationDetents([.fraction(0.92)])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showIncrementSelection) {
                    AvailableChangePlatesView()
                        .presentationDetents([.height(480), .large])
                        .presentationDragIndicator(.visible)
                }
                .alert("No Exercises Found", isPresented: $showNoExercisesAlert) {
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
            .navigationBarHidden(true)
        }
        .ignoresSafeArea(.keyboard)
    }

    private var addExercisesSheet: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Button("Cancel") {
                    newExercisesName = ""
                    newExercisesLoadType = .barbell
                    newExercisesIcon = "LiftTheBullIcon"
                    showingAddExercises = false
                }
                .foregroundStyle(Color.appAccent)

                Spacer()

                Text("Add Exercise")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button("Add") {
                    addExercises()
                }
                .foregroundStyle(Color.appAccent)
                .disabled(newExercisesName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(newExercisesName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            VStack(spacing: 16) {
                // Exercise Name Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercise Name")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    TextField("e.g. Romanian Deadlift", text: $newExercisesName)
                        .textInputAutocapitalization(.words)
                        .font(.body)
                        .padding(14)
                        .background(Color(white: 0.12))
                        .cornerRadius(10)
                        .foregroundStyle(.white)
                        .onChange(of: newExercisesName) { _, newValue in
                            if newValue.count > maxExercisesNameLength {
                                newExercisesName = String(newValue.prefix(maxExercisesNameLength))
                            }
                            // Auto-select icon based on name
                            // newExercisesIcon = IconCarouselPicker.suggestedIcon(for: newValue)
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
                                newExercisesLoadType = type
                            } label: {
                                HStack {
                                    Text(type.rawValue)
                                    if newExercisesLoadType == type {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(newExercisesLoadType.rawValue)
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

                    IconCarouselPicker(selectedIcon: $newExercisesIcon)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
                let minWeight = selectedExercises?.exerciseLoadType == .singleLoad ? 0.0 : 0.01
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

    private var bodyweightCaptureSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    Spacer()
                        .frame(height: 8)

                    Text("Set Bodyweight")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Text("Your bodyweight is used for calculating 1RM on bodyweight exercises")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()
                        .frame(height: 20)

                    // Weight Picker
                    HStack(spacing: 0) {
                        Picker("Weight", selection: $tempBodyweight) {
                            ForEach(Array(stride(from: 50.0, through: 500.0, by: 0.5)), id: \.self) { weight in
                                Text("\(weight, specifier: "%.1f")")
                                    .tag(weight)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)

                        Text("lbs")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.trailing, 40)
                    }
                    .frame(height: 200)

                    Spacer()

                    // Buttons
                    HStack(spacing: 16) {
                        Button {
                            tempBodyweight = 0
                            userProperties.bodyweight = nil
                            try? modelContext.save()
                            showBodyweightCapture = false
                            showLogConfirmation = true
                        } label: {
                            Text("Clear")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                        }

                        Button {
                            userProperties.bodyweight = tempBodyweight
                            try? modelContext.save()
                            showBodyweightCapture = false
                            showLogConfirmation = true
                        } label: {
                            Text("Done")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.appAccent)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private var editExerciseNameSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    showEditExerciseName = false
                }
                .foregroundStyle(Color.appAccent)

                Spacer()

                Text("Edit Exercise")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button("Save") {
                    saveEditedExercise()
                }
                .foregroundStyle(Color.appAccent)
                .disabled(!hasUnsavedExerciseChanges)
                .opacity(hasUnsavedExerciseChanges ? 1.0 : 0.5)
            }
            .padding(.horizontal)
            .padding(.top, 24)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 20) {
                    // Name text field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        TextField("Exercise name", text: $editExerciseNameInput)
                            .textInputAutocapitalization(.words)
                            .font(.body)
                            .padding(14)
                            .background(Color(white: 0.12))
                            .cornerRadius(10)
                            .foregroundStyle(.white)
                            .onChange(of: editExerciseNameInput) { _, newValue in
                                if newValue.count > maxExercisesNameLength {
                                    editExerciseNameInput = String(newValue.prefix(maxExercisesNameLength))
                                }
                            }

                        HStack {
                            Text("\(editExerciseNameInput.count) / \(maxExercisesNameLength)")
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

                        Text(selectedExercises?.exerciseLoadType.rawValue ?? "Unknown")
                            .font(.body)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(white: 0.08))
                            .cornerRadius(10)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    // Icon Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        IconCarouselPicker(selectedIcon: $editingExerciseIcon)
                    }

                    // Notes text field
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Notes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            if !exerciseNotesInput.isEmpty || !(selectedExercises?.notes?.isEmpty ?? true) {
                                Button {
                                    let textToCopy = exerciseNotesInput.isEmpty ? (selectedExercises?.notes ?? "") : exerciseNotesInput
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

                        TextEditor(text: $exerciseNotesInput)
                            .padding(8)
                            .frame(minHeight: 100)
                            .background(Color(white: 0.12))
                            .cornerRadius(10)
                            .foregroundStyle(.white)
                            .scrollContentBackground(.hidden)
                            .onChange(of: exerciseNotesInput) { _, newValue in
                                if newValue.count > maxNotesLength {
                                    exerciseNotesInput = String(newValue.prefix(maxNotesLength))
                                }
                            }

                        HStack {
                            Text("\(exerciseNotesInput.count) / \(maxNotesLength)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                        }
                    }

                    // Delete section (collapsed by default)
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
                .padding(.horizontal)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .alert("Delete Exercise?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                performExerciseDeletion()
            }
        } message: {
            Text("This will permanently delete \"\(selectedExercises?.name ?? "this exercise")\" and all its workout history.")
        }
        .onDisappear {
            // Reset delete section state when sheet closes
            showDeleteSection = false
            deleteConfirmationChecked = false
        }
    }

    private var exerciseDetailsSheet: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Button("Cancel") {
                    showExercisesDetails = false
                }
                .foregroundStyle(Color.appAccent)

                Spacer()

                Text("Exercises Details")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button("Save") {
                    saveExercisesDetails()
                }
                .foregroundStyle(Color.appAccent)
                .disabled(editingExercisesName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(editingExercisesName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            VStack(spacing: 16) {
                // Exercises Name Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercises Name")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    TextField("Exercises name", text: $editingExercisesName)
                        .textInputAutocapitalization(.words)
                        .font(.body)
                        .padding(14)
                        .background(Color(white: 0.12))
                        .cornerRadius(10)
                        .foregroundStyle(.white)
                        .onChange(of: editingExercisesName) { _, newValue in
                            if newValue.count > maxExercisesNameLength {
                                editingExercisesName = String(newValue.prefix(maxExercisesNameLength))
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
                                editingExercisesLoadType = type
                            } label: {
                                HStack {
                                    Text(type.rawValue)
                                    if editingExercisesLoadType == type {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(editingExercisesLoadType.rawValue)
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

                // Delete button for custom exercises
                if selectedExercises?.isCustom == true {
                    Button {
                        deleteExercises()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Exercises")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var styledExercisesSelector: some View {
        Button {
            hapticFeedback.impactOccurred()
            showExercisesSelection = true
        } label: {
            HStack(spacing: 8) {
                if selectedExercises != nil {
                    // Selected state: left-aligned with padding for edit button
                    Text(selectedExercises?.name ?? "")
                        .font(.bebasNeue(size: 22))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.leading, 36)

                    Spacer()

                    if !setsForSelected.isEmpty {
                        HStack(spacing: 6) {
                            Text("Est. 1RM")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                            Text(current1RM.rounded1().formatted(.number.precision(.fractionLength(2))))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.appAccent)
                        }
                    }
                } else {
                    // Unselected state: centered text
                    Spacer()
                    Text("Select Exercise")
                        .font(.bebasNeue(size: 22))
                        .foregroundStyle(.white)
                    Spacer()
                }

                Image(systemName: "chevron.down")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(height: 28)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
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
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            // Edit icon in left area
            if selectedExercises != nil {
                Button {
                    hapticFeedback.impactOccurred()
                    editExerciseNameInput = selectedExercises?.name ?? ""
                    editingExerciseIcon = selectedExercises?.icon ?? "LiftTheBullIcon"
                    exerciseNotesInput = selectedExercises?.notes ?? ""
                    showEditExerciseName = true
                } label: {
                    HStack {
                        Image(systemName: "pencil")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.appAccent)
                            .padding(.leading, 12)
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                    .frame(width: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var graphHeaderView: some View {
        HStack {
            Text("Current Estimated 1RM")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Text(!setsForSelected.isEmpty ? current1RM.rounded1().formatted(.number.precision(.fractionLength(2))) : "--")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    private struct EmptyGraphView: View {
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

    private struct SetHistoryChart: View {
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

        private func colorForPercentage(_ percentage: Double, isPR: Bool, weight: Double, reps: Int) -> [Color] {
            // If it's a PR, use special PR color
            if isPR {
                return [.setPR, .setPR.opacity(0.8)]
            }

            // For 0-weight sets, color by reps (more reps = harder)
            if weight == 0 {
                switch reps {
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

            // Otherwise, color by percentage of current 1RM (intensity)
            switch percentage {
            case 85...:
                return [.setNearMax, .setNearMax.opacity(0.8)]
            case 75..<85:
                return [.setHard, .setHard.opacity(0.8)]
            case 65..<75:
                return [.setModerate, .setModerate.opacity(0.8)]
            default:
                return [.setEasy, .setEasy.opacity(0.8)]
            }
        }

        private func barMark(index: Int, setInfo: SetWithPR, isSelected: Bool) -> some ChartContent {
            let colors: [Color]

            if isSelected {
                // Bright white gradient for selected bar
                colors = [.white, Color(white: 0.9)]
            } else {
                colors = colorForPercentage(setInfo.percentageOfCurrent, isPR: setInfo.wasPR, weight: setInfo.set.weight, reps: setInfo.set.reps)
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

    private struct SetHistoryChartYAxis: View {
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

    private var filteredSetsWithPRInfo: [SetWithPR] {
        if showPROnly {
            return setsWithPRInfo.filter { $0.wasPR }
        }
        return setsWithPRInfo
    }

    private var graphContentView: some View {
        Group {
            if setsWithPRInfo.isEmpty {
                EmptyGraphView()
            } else {
                let displayData = filteredSetsWithPRInfo
                ZStack {
                    HStack(spacing: 0) {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 0) {
                                    SetHistoryChart(setsWithPRInfo: displayData, showYAxis: false, selectedBarIndex: $selectedChartBarIndex)
                                        .id("chart-end")
                                }
                            }
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    proxy.scrollTo("chart-end", anchor: .trailing)
                                }
                            }
                            .onChange(of: displayData.count) { _, _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation {
                                        proxy.scrollTo("chart-end", anchor: .trailing)
                                    }
                                }
                            }
                        }

                        // Fixed Y-axis on the right
                        SetHistoryChartYAxis(setsWithPRInfo: displayData)
                    }

                    if let index = selectedChartBarIndex, index < displayData.count {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()

                        setDetailOverlay(for: displayData[index])
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            }
        }
    }

    @State private var selectedChartBarIndex: Int? = nil

    private func setDetailOverlay(for setInfo: SetWithPR) -> some View {
        let isZeroWeight = setInfo.set.weight == 0

        return VStack(spacing: 8) {
            if setInfo.wasPR {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text("PR Set")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }

            VStack(spacing: 4) {
                Text("Weight: \(setInfo.set.weight.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Text("Reps: \(setInfo.set.reps)")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                if !isZeroWeight {
                    Text("Intensity: \(Int(setInfo.percentageOfCurrent))% of current")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Text("Est. 1RM: \(setInfo.estimated1RM.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs")
                        .font(.title3)
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }

    private var todaysSets: [LiftSet] {
        guard let ex = selectedExercises else { return [] }
        let calendar = Calendar.current
        let today = self.today
        return allSets.filter { set in
            set.exercise?.id == ex.id &&
            calendar.isDate(set.createdAt, inSameDayAs: today)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    private var lastDayDate: Date? {
        guard let ex = selectedExercises else { return nil }
        let calendar = Calendar.current
        let today = self.today

        let previousDays = allSets
            .filter { $0.exercise?.id == ex.id && $0.createdAt < today }
            .map { calendar.startOfDay(for: $0.createdAt) }

        return Set(previousDays).sorted(by: >).first
    }

    private var lastDaySets: [LiftSet] {
        guard let ex = selectedExercises else { return [] }
        guard let lastDay = lastDayDate else { return [] }
        let calendar = Calendar.current

        return allSets.filter { set in
            set.exercise?.id == ex.id &&
            calendar.isDate(set.createdAt, inSameDayAs: lastDay)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    private var setComparisonView: some View {
        let placeholderSquares: [[Color]] = [
            [.setEasy, .setModerate, .setHard, .setPR, .setNearMax, .setHard, .setModerate],
            [.setModerate, .setHard, .setNearMax, .setPR, .setHard, .setModerate, .setEasy]
        ]

        return Group {
            if todaysSets.isEmpty && lastDaySets.isEmpty {
                // Empty state with placeholder grid of colored squares
                ZStack {
                    // Placeholder grid
                    VStack(spacing: 16) {
                        ForEach(0..<placeholderSquares.count, id: \.self) { row in
                            HStack(spacing: 10) {
                                ForEach(0..<placeholderSquares[row].count, id: \.self) { col in
                                    let color = placeholderSquares[row][col]
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(color.opacity(0.3))
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(color.opacity(0.5), lineWidth: 1.5)
                                        )
                                }
                            }
                        }
                    }

                    // Overlay text (commented out to simplify)
                    // VStack(spacing: 8) {
                    //     Text("No Sets Yet")
                    //         .font(.subheadline.weight(.semibold))
                    //         .foregroundStyle(.white)
                    //
                    //     Text("Your set intensity will appear here")
                    //         .font(.caption)
                    //         .foregroundStyle(.white.opacity(0.7))
                    // }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    // Today's Sets
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Today:")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(formatShortDate(Date()))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        if todaysSets.isEmpty {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.appAccent.opacity(0.3), Color.appAccent.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 42, height: 42)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.appAccent.opacity(0.4), lineWidth: 1.5)
                                )
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(Array(todaysSets.enumerated()), id: \.element.id) { index, set in
                                        SetSquareView(
                                            set: set,
                                            allSets: allSets,
                                            currentWeight: weight,
                                            currentReps: reps,
                                            hasSetValues: hasSetInitialValues,
                                            selectedSquareId: selectedSquareId,
                                            allEstimated1RMs: allEstimated1RMs
                                        )
                                        .onTapGesture {
                                            weight = set.weight
                                            reps = set.reps
                                            hasSetInitialValues = true
                                            hasSetWeight = true
                                            hasSetReps = true
                                            selectedSquareId = set.id
                                            highlightLogSet()
                                            hapticFeedback.impactOccurred()
                                            Task {
                                                try? await Task.sleep(nanoseconds: 300_000_000)
                                                await MainActor.run {
                                                    selectedSquareId = nil
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                                .padding(.horizontal, 2)
                            }
                            .frame(height: 46)
                        }
                    }

                    // Previous Day Sets
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text(lastDayDate != nil ? "Previous Day:" : "Previous Day")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            if let date = lastDayDate {
                                Text(formatShortDate(date))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }

                        if lastDaySets.isEmpty {
                            Spacer()
                                .frame(height: 42)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(Array(lastDaySets.enumerated()), id: \.element.id) { index, set in
                                        SetSquareView(
                                            set: set,
                                            allSets: allSets,
                                            currentWeight: weight,
                                            currentReps: reps,
                                            hasSetValues: hasSetInitialValues,
                                            selectedSquareId: selectedSquareId,
                                            allEstimated1RMs: allEstimated1RMs
                                        )
                                        .onTapGesture {
                                            weight = set.weight
                                            reps = set.reps
                                            hasSetInitialValues = true
                                            hasSetWeight = true
                                            hasSetReps = true
                                            selectedSquareId = set.id
                                            highlightLogSet()
                                            hapticFeedback.impactOccurred()
                                            Task {
                                                try? await Task.sleep(nanoseconds: 300_000_000)
                                                await MainActor.run {
                                                    selectedSquareId = nil
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                                .padding(.horizontal, 2)
                            }
                            .frame(height: 46)
                        }
                    }
                }

                Spacer()
                    .frame(height: 8)
            }
        }
    }

    private var estimated1RMGraphWidget: some View {
        VStack(spacing: 0) {
            // Tab Selector - Segmented Picker Style
            ZStack(alignment: .center) {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.1))
                    .frame(height: 32)

                // Sliding indicator
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.appAccent)
                        .frame(width: geometry.size.width / 2 - 4, height: 28)
                        .offset(x: selectedGraphTab == 0 ? 2 : geometry.size.width / 2 + 2, y: 2)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedGraphTab)
                }
                .frame(height: 32)

                // Tab buttons
                HStack(spacing: 0) {
                    Button {
                        selectedGraphTab = 0
                        hapticFeedback.impactOccurred()
                    } label: {
                        Text("Set Intensity")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedGraphTab == 0 ? .black : .white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(height: 32)

                    Button {
                        selectedGraphTab = 1
                        hapticFeedback.impactOccurred()
                    } label: {
                        Text("Estimated 1RM")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedGraphTab == 1 ? .black : .white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(height: 32)
                }
            }
            .frame(height: 32)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, selectedGraphTab == 1 ? 4 : 10)

            // Show PR Only toggle (only visible on Estimated 1RM tab with data)
            if selectedGraphTab == 1 && !setsWithPRInfo.isEmpty {
                HStack(spacing: 4) {
                    Spacer()
                    Button {
                        showPROnly.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showPROnly ? "checkmark.square.fill" : "square")
                                .font(.caption2)
                                .foregroundStyle(Color.appAccent)
                            Text("Show PRs Only")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .frame(height: 14)
            }

            // Content
            VStack {
                if selectedGraphTab == 0 {
                    setComparisonView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    graphContentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 136)
            .padding(.horizontal, 16)
            .padding(.top, selectedGraphTab == 1 ? 2 : 8)
            .padding(.bottom, 6)

            // Legend (only show when there's data)
            if (selectedGraphTab == 0 && !(todaysSets.isEmpty && lastDaySets.isEmpty)) ||
               (selectedGraphTab == 1 && !setsWithPRInfo.isEmpty) {
                HStack(spacing: 10) {
                    LegendItem(color: .setEasy, label: "Easy")
                    LegendItem(color: .setModerate, label: "Moderate")
                    LegendItem(color: .setHard, label: "Hard")
                    LegendItem(color: .setNearMax, label: "Redline")
                    LegendItem(color: .setPR, label: "Est. 1RM PR")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
        .frame(height: 220)
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
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with weight delta controls
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Progress Options")
                        .font(.inter(size: 17))
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

                if setsForSelected.isEmpty {
                    // Empty state: show slider icon to open change plates
                    Button {
                        hapticFeedback.impactOccurred()
                        showIncrementSelection = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.appAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(white: 0.12))
                            .cornerRadius(10)
                    }
                } else {
                    // Has data: show increment/decrement controls
                    HStack(spacing: 6) {
                        Button {
                            // If at minimum, open change plates view to add smaller increments
                            if weightDelta <= minWeightDelta {
                                hapticFeedback.impactOccurred()
                                showIncrementSelection = true
                            } else if let currentIndex = availableWeightDeltas.firstIndex(where: { abs($0 - weightDelta) < 0.01 }),
                               currentIndex > 0 {
                                weightDelta = availableWeightDeltas[currentIndex - 1]
                                hapticFeedback.impactOccurred()
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(weightDelta > minWeightDelta ? Color.appAccent : .gray)
                        }

                        Button {
                            hapticFeedback.impactOccurred()
                            showIncrementSelection = true
                        } label: {
                            VStack(spacing: 0) {
                                Text(weightDelta.formatted(.number.precision(.fractionLength(1))))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("Δ LB")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.appLabel)
                            }
                            .frame(width: 45)
                        }
                        .buttonStyle(.plain)

                        Button {
                            // If at maximum, open change plates view
                            if weightDelta >= maxWeightDelta {
                                hapticFeedback.impactOccurred()
                                showIncrementSelection = true
                            } else if let currentIndex = availableWeightDeltas.firstIndex(where: { abs($0 - weightDelta) < 0.01 }),
                               currentIndex < availableWeightDeltas.count - 1 {
                                weightDelta = availableWeightDeltas[currentIndex + 1]
                                hapticFeedback.impactOccurred()
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(weightDelta < maxWeightDelta ? Color.appAccent : .gray)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.12))
                    .cornerRadius(8)
                }
            }

            if setsForSelected.isEmpty {
                // Empty state content
                ProgressOptionsEmptyState()
                    .frame(maxWidth: .infinity)
                    .frame(height: 172)
            } else {
                VStack(spacing: 8) {
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
                                Text("EST. 1RM")
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
                                            columnHighlighted: columnHighlighted
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
                            .frame(height: 140)
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

                        // Gradient fade indicator for scrollable content
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
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 0)
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
        .onLongPressGesture(minimumDuration: 0.5) {
            hapticFeedback.impactOccurred()
            showExpandedProgressOptions = true
        }
        .sheet(isPresented: $showExpandedProgressOptions) {
            ExpandedProgressOptionsSheet(
                suggestions: filteredSuggestions,
                sortColumn: $sortColumn,
                sortAscending: $sortAscending,
                onSelect: { suggestion in
                    selectOption(suggestion)
                    showExpandedProgressOptions = false
                }
            )
            .presentationDetents([.fraction(0.92)])
            .presentationDragIndicator(.visible)
        }
    }

    private var logSetSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Weight with increment/decrement
                HStack(spacing: 8) {
                    Button {
                        guard selectedExercises != nil else {
                            showExercisesSelection = true
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
                            showExercisesSelection = true
                            return
                        }
                        showWeightPicker = true
                    } label: {
                        VStack(spacing: 1) {
                            Text(hasSetWeight ? weight.rounded1().formatted(.number.precision(.fractionLength(2))) : "---")
                                .font(.title2)
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
                            showExercisesSelection = true
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(white: 0.12))
                .cornerRadius(10)
                .frame(maxWidth: .infinity)

                Divider()
                    .background(.white.opacity(0.2))

                // Reps
                HStack(spacing: 8) {
                    Button {
                        guard selectedExercises != nil else {
                            showExercisesSelection = true
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
                            showExercisesSelection = true
                            return
                        }
                        showRepsPicker = true
                    } label: {
                        VStack(spacing: 2) {
                            Text(hasSetReps ? "\(reps)" : "---")
                                .font(.title2)
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
                            showExercisesSelection = true
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(white: 0.12))
                .cornerRadius(10)
                .frame(maxWidth: .infinity)
            }

            // Log Set button spanning full width
            Button {
                hapticFeedback.impactOccurred()
                guard selectedExercises != nil else {
                    showExercisesSelection = true
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
        .padding(.top, 4)
        .padding(.bottom, 8)
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
                .stroke(Color.appAccent, lineWidth: logSetHighlighted ? 3 : 0)
                .animation(.easeInOut(duration: 0.5).repeatCount(1, autoreverses: true), value: logSetHighlighted)
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

        private let squareSize: CGFloat = 160

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
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .scaleEffect(iconScale)
                            .opacity(iconOpacity)
                    }

                    if didIncrease {
                        VStack(spacing: 4) {
                            Text("Increased 1RM by")
                                .font(.subheadline)
                            Text("+\(delta.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs")
                                .font(.title.weight(.semibold))
                                .foregroundStyle(Color.appLogoColor)
                        }
                    } else {
                        VStack(spacing: 2) {
                            Text(intensityLabel)
                                .font(.bebasNeue(size: 28))
                                .foregroundStyle(.white)
                            Text("Set Logged")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .frame(width: squareSize, height: squareSize)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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

    private struct CancelOverlayView: View {
        @State private var pulse = false

        private let squareSize: CGFloat = 160

        var body: some View {
            ZStack {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.7))

                    Text("Not Logged")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(width: squareSize, height: squareSize)
                .background(Color(white: 0.2).opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.appLogoColor.opacity(0.5), lineWidth: 1.5)
                )
                .scaleEffect(pulse ? 1.02 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.22).repeatCount(2, autoreverses: true)) {
                        pulse = true
                    }
                }
            }
        }
    }

    private struct ConfirmationOverlayView: View {
        let exercise: Exercises?
        let reps: Int
        let weight: Double
        let onConfirm: () -> Void
        let onCancel: () -> Void

        private var weightText: String {
            return "\(weight.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs"
        }

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
                            Text(weightText)
                                .font(.title2)
                                .foregroundStyle(.white)
                        }

                        Rectangle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 1, height: 24)

                        HStack(spacing: 6) {
                            Text("\(reps)")
                                .font(.title2)
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

                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 1)
                        .padding(.horizontal, 4)

                    // Buttons
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
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.appLogoColor.opacity(0.5), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
                .padding(.horizontal, 32)
            }
        }
    }

    private func addExercises() {
        let trimmed = newExercisesName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let ex = Exercises(name: trimmed, isCustom: true, loadType: newExercisesLoadType, icon: newExercisesIcon)
        modelContext.insert(ex)
        selectedExercisesId = ex.id

        // Sync new custom exercise to backend
        Task { await SyncService.shared.syncExercise(ex) }

        newExercisesName = ""
        newExercisesLoadType = .barbell
        newExercisesIcon = "LiftTheBullIcon"
        showingAddExercises = false
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
        highlightLogSet()
    }

    private func isOptionSelected(_ suggestion: OneRMCalculator.Suggestion) -> Bool {
        // Check if current Log Set values match this suggestion
        return weight == suggestion.weight && reps == suggestion.reps
    }

    private func highlightLogSet() {
        logSetHighlighted = true
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                logSetHighlighted = false
            }
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

    private func selectOption(_ suggestion: OneRMCalculator.Suggestion) {
        reps = suggestion.reps
        weight = suggestion.weight
        hasSetInitialValues = true
        hasSetWeight = true
        hasSetReps = true
        highlightLogSet()
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

        let before = current1RM

        let set = LiftSet(exercise: ex, reps: reps, weight: weight)
        modelContext.insert(set)

        let simulatedSets = setsForSelected + [set]
        let after = OneRMCalculator.current1RM(from: simulatedSets)

        let d = after - before
        let increased = d > 0.0001

        // Create a new Estimated1RM record for every set, tracking which set created it
        let estimated = Estimated1RM(exercise: ex, value: after, setId: set.id)
        modelContext.insert(estimated)

        // Sync lift set and estimated 1RM to backend
        Task {
            await SyncService.shared.syncLiftSet(set)
            await SyncService.shared.syncEstimated1RM(estimated)
        }

        overlayDidIncrease = increased
        overlayDelta = d
        overlayNew1RM = after

        // Calculate intensity color and label for the overlay
        if increased {
            overlayIntensityColor = .setPR
            overlayIntensityLabel = "PR"
        } else if weight == 0 {
            // Bodyweight exercise - color by reps
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
        } else {
            // Weighted exercise - color by percentage of 1RM
            // Use THIS set's estimated 1RM, not the running max
            let setEstimate = OneRMCalculator.estimate1RM(weight: weight, reps: reps)
            let percentage = before > 0 ? (setEstimate / before) * 100 : 100.0
            switch percentage {
            case 85...:
                overlayIntensityColor = .setNearMax
                overlayIntensityLabel = "Redline"
            case 75..<85:
                overlayIntensityColor = .setHard
                overlayIntensityLabel = "Hard"
            case 65..<75:
                overlayIntensityColor = .setModerate
                overlayIntensityLabel = "Moderate"
            default:
                overlayIntensityColor = .setEasy
                overlayIntensityLabel = "Easy"
            }
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            showSubmitOverlay = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    showSubmitOverlay = false
                }
            }
        }
    }

    private func saveExercisesDetails() {
        guard let ex = selectedExercises else { return }

        let trimmed = editingExercisesName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        ex.name = trimmed
        ex.exerciseLoadType = editingExercisesLoadType

        showExercisesDetails = false
    }

    private func saveEditedExercise() {
        guard let ex = selectedExercises else { return }

        let trimmed = editExerciseNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        ex.name = trimmed
        ex.icon = editingExerciseIcon
        ex.notes = exerciseNotesInput.isEmpty ? nil : exerciseNotesInput
        try? modelContext.save()

        // Sync edited exercise to backend
        Task { await SyncService.shared.syncExercise(ex) }

        showEditExerciseName = false
    }

    private func performExerciseDeletion() {
        guard let ex = selectedExercises else { return }

        let exerciseId = ex.id

        // Delete associated sets
        let setsToDelete = allSets.filter { $0.exercise?.id == ex.id }
        for set in setsToDelete {
            modelContext.delete(set)
        }

        // Delete associated 1RM records
        let estimatesToDelete = allEstimated1RMs.filter { $0.exercise?.id == ex.id }
        for estimate in estimatesToDelete {
            modelContext.delete(estimate)
        }

        // Delete the exercise
        modelContext.delete(ex)
        try? modelContext.save()

        // Close the edit sheet
        showEditExerciseName = false

        // Select a different exercise
        selectedExercisesId = exercises.first(where: { $0.id != ex.id })?.id

        // Sync deletion to backend immediately
        Task { await SyncService.shared.deleteExercise(exerciseId) }
    }

    private func deleteExercises() {
        guard let ex = selectedExercises, ex.isCustom else { return }

        let exerciseId = ex.id

        // Delete associated sets
        let setsToDelete = allSets.filter { $0.exercise?.id == ex.id }
        for set in setsToDelete {
            modelContext.delete(set)
        }

        // Delete associated 1RM records
        let estimatesToDelete = allEstimated1RMs.filter { $0.exercise?.id == ex.id }
        for estimate in estimatesToDelete {
            modelContext.delete(estimate)
        }

        // Delete the exercise
        modelContext.delete(ex)

        // Select a different exercise
        selectedExercisesId = exercises.first(where: { $0.id != ex.id })?.id

        // Sync deletion to backend
        Task { await SyncService.shared.deleteExercise(exerciseId) }

        showExercisesDetails = false
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
        }
    }
}

struct ExercisesSelectionView: View {
    let exercises: [Exercises]
    @Binding var selectedExercisesId: UUID?
    let onAddExercises: () -> Void
    let onEditExercises: (Exercises) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var filteredExercises: [Exercises] {
        if searchText.isEmpty {
            return exercises.sorted { $0.name < $1.name }
        }
        return exercises
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Title
                Text("Select Exercise")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

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
                .background(Color(white: 0.15))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if filteredExercises.isEmpty && !searchText.isEmpty {
                    // Empty search results
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("No exercises found")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.5))
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onAddExercises()
                            }
                        } label: {
                            Text("Add \"\(searchText)\" as new exercise")
                                .font(.subheadline)
                                .foregroundStyle(Color.appAccent)
                        }
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            // Add Exercises Button (only show when not searching)
                            if searchText.isEmpty {
                                Button {
                                    onAddExercises()
                                } label: {
                                    VStack(spacing: 12) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 36))
                                            .foregroundStyle(Color.appAccent)

                                        Text("Add Exercise")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 140)
                                    .padding(12)
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
                                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                                            .foregroundStyle(Color.appAccent.opacity(0.5))
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            ForEach(filteredExercises) { exercise in
                                ExercisesCardButton(
                                    exercise: exercise,
                                    isSelected: selectedExercisesId == exercise.id,
                                    onSelect: {
                                        selectedExercisesId = exercise.id
                                        dismiss()
                                    },
                                    onEdit: {
                                        onEditExercises(exercise)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct ExercisesCardButton: View {
    let exercise: Exercises
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(spacing: 12) {
                // Exercise icon
                ExerciseIconView(exercise: exercise, size: 90)
                    .foregroundStyle(Color.appAccent)

                Text(exercise.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(height: 36, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .padding(12)
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
                    .stroke(isSelected ? Color.appAccent : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
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
    let allEstimated1RMs: [Estimated1RM]

    private var isMatching: Bool {
        guard hasSetValues else { return false }
        return abs(set.weight - currentWeight) < 0.01 && set.reps == currentReps
    }

    private var isSelected: Bool {
        selectedSquareId == set.id
    }

    private var colorAndPR: (color: Color, isPR: Bool) {
        // Calculate percentage of current 1RM at time of this set
        let previousSets = allSets
            .filter { $0.exercise?.id == set.exercise?.id && $0.createdAt < set.createdAt }
            .sorted { $0.createdAt < $1.createdAt }

        var currentMax: Double = 0
        var maxReps: Int = 0
        for prevSet in previousSets {
            let estimated = OneRMCalculator.estimate1RM(weight: prevSet.weight, reps: prevSet.reps)
            currentMax = max(currentMax, estimated)
            maxReps = max(maxReps, prevSet.reps)
        }

        let setEstimated1RM = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)

        // For 0-weight sets, use rep-based comparison for PR
        let isPR: Bool
        if set.weight == 0 {
            isPR = set.reps > maxReps
        } else {
            isPR = setEstimated1RM > currentMax
        }

        let color: Color
        if isPR {
            color = .setPR
        } else if set.weight == 0 {
            // For 0-weight sets, color based on reps (more reps = harder)
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
            let percentage = currentMax > 0 ? (setEstimated1RM / currentMax) * 100 : 100.0
            switch percentage {
            case 85...:
                color = .setNearMax
            case 75..<85:
                color = .setHard
            case 65..<75:
                color = .setModerate
            default:
                color = .setEasy
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
                .stroke(Color.appAccent, lineWidth: isMatching || isSelected ? 3 : 0)
                .animation(.easeInOut(duration: 0.15), value: isMatching)
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
        if let associated1RM = allEstimated1RMs.first(where: { $0.setId == setId }) {
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

struct ProgressOptionsEmptyState: View {
    var body: some View {
        ZStack {
            // Subtle radial gradient background
            RadialGradient(
                colors: [
                    Color.appLogoColor.opacity(0.08),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 80
            )

            // Content
            VStack(spacing: 14) {
                // Lift the Bull logo with subtle glow
                Image("LiftTheBullIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .foregroundStyle(Color.appLogoColor)
                    .shadow(color: Color.appLogoColor.opacity(0.3), radius: 14, x: 0, y: 0)

                Text("Log your first set below")
                    .font(.interSemiBold(size: 16))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .offset(y: -11)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Expanded Progress Options Sheet

struct ExpandedProgressOptionsSheet: View {
    let suggestions: [OneRMCalculator.Suggestion]
    @Binding var sortColumn: CheckInView.SortColumn
    @Binding var sortAscending: Bool
    let onSelect: (OneRMCalculator.Suggestion) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var columnHighlighted = true
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
            // Slim title header
            Text("Progress Options")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.top, 8)

            // Header row with column labels
            HStack(spacing: 12) {
                columnButton(title: "WEIGHT", column: .weight, width: 65)
                Spacer().frame(width: 1)
                columnButton(title: "REPS", column: .reps, width: 50)
                Spacer().frame(width: 1)
                columnButton(title: "EST. 1RM", column: .est1RM, width: 60)
                Spacer().frame(width: 1)
                columnButton(title: "GAIN", column: .gain, width: 65)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.12))

            // Scrollable options list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(sortedSuggestions) { suggestion in
                        ProgressOptionCard(
                            suggestion: suggestion,
                            isSelected: false,
                            sortColumn: sortColumn,
                            columnHighlighted: columnHighlighted
                        )
                        .onTapGesture {
                            hapticFeedback.impactOccurred()
                            onSelect(suggestion)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Close button
            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.appAccent)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color.black)
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
