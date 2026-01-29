import SwiftUI
import SwiftData
import Charts

struct CheckInView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Exercises.createdAt) private var exercises: [Exercises]
    @Query(sort: \LiftSet.createdAt, order: .reverse) private var allSets: [LiftSet]
    @Query private var userPropertiesItems: [UserProperties]
    @Query(sort: \Estimated1RM.createdAt, order: .reverse) private var allEstimated1RMs: [Estimated1RM]

    @ObservedObject var selectedSetData: SelectedSetData

    @State private var selectedExercisesId: UUID?
    @State private var showingAddExercises = false

    @State private var reps: Int = 8
    @State private var weight: Double = 20.0
    @State private var hasSetInitialValues = false

    @State private var newExercisesName: String = ""
    @State private var newExercisesLoadType: ExerciseLoadType = .barbell

    @State private var showSubmitOverlay = false
    @State private var overlayDidIncrease = false
    @State private var overlayDelta: Double = 0
    @State private var overlayNew1RM: Double = 0

    @State private var showWeightPicker = false
    @State private var weightInput: String = ""
    @State private var showRepsPicker = false
    @State private var repsInput: String = ""
    @State private var showExercisesDetails = false
    @State private var editingExercisesName = ""
    @State private var editingExercisesLoadType: ExerciseLoadType = .barbell
    @State private var showLogConfirmation = false
    @State private var showCancelOverlay = false
    @State private var showValidationMessage = false
    @State private var weightDelta: Double = 5.0
    @State private var showExercisesSelection = false
    @State private var selectedGraphTab: Int = 0 // 0 = Set Intensity, 1 = 1RM Graph
    @State private var logSetHighlighted = false
    @State private var selectedSquareId: UUID? = nil
    @State private var showBodyweightCapture = false
    @State private var bodyweightInput: String = ""
    @State private var showExercisesNotes = false
    @State private var exerciseNotesInput: String = ""

    enum SortColumn {
        case weight, reps, est1RM, gain
    }
    @State private var sortColumn: SortColumn = .gain
    @State private var sortAscending: Bool = true
    @State private var columnHighlighted = false

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    private let maxNotesLength = 500
    private let maxExercisesNameLength = 25

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var availablePlates: [Double] {
        userProperties.plateWeights.sorted { $0 > $1 }
    }

    private var selectedExercises: Exercises? {
        if let id = selectedExercisesId {
            return exercises.first(where: { $0.id == id })
        }
        return exercises.first
    }

    private var setsForSelected: [LiftSet] {
        guard let ex = selectedExercises else { return [] }
        return allSets.filter { $0.exercise?.id == ex.id }
    }

    private var estimated1RMsForSelected: [Estimated1RM] {
        guard let ex = selectedExercises else { return [] }
        return allEstimated1RMs.filter { $0.exercise?.id == ex.id }
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

        for set in sets {
            let estimated = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)
            let wasPR = estimated > currentMax
            // Calculate percentage of current 1RM (before this set)
            let percentage = currentMax > 0 ? (estimated / currentMax) * 100 : 100.0
            if wasPR {
                currentMax = estimated
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
        // For bodyweight exercises, add bodyweight to each set's weight before calculating
        let adjustedSets: [LiftSet]
        if selectedExercises?.exerciseLoadType == .bodyweightPlusSingleLoad, let bw = userProperties.bodyweight {
            adjustedSets = setsForSelected.compactMap { set in
                guard let ex = set.exercise else { return nil }
                let adjusted = LiftSet(exercise: ex, reps: set.reps, weight: set.weight + bw)
                adjusted.createdAt = set.createdAt
                adjusted.createdTimezone = set.createdTimezone
                return adjusted
            }
        } else {
            adjustedSets = setsForSelected
        }
        return OneRMCalculator.current1RM(from: adjustedSets)
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
        return Array(deltas).sorted()
    }

    private var minWeightDelta: Double {
        return availableWeightDeltas.first ?? 5.0
    }

    private var maxWeightDelta: Double {
        return 5.0
    }

    private var suggestions: [OneRMCalculator.Suggestion] {
        let rawSuggestions = OneRMCalculator.minimizedSuggestions(current1RM: current1RM, increment: weightDelta)
        // For bodyweight exercises, subtract bodyweight from suggested weights since we store only added weight
        if selectedExercises?.exerciseLoadType == .bodyweightPlusSingleLoad, let bw = userProperties.bodyweight {
            return rawSuggestions.map { suggestion in
                OneRMCalculator.Suggestion(
                    reps: suggestion.reps,
                    weight: max(0, suggestion.weight - bw),  // Subtract bodyweight to get added weight
                    projected1RM: suggestion.projected1RM,
                    delta: suggestion.delta
                )
            }
        }
        return rawSuggestions
    }

    private var topThreeSuggestions: [OneRMCalculator.Suggestion] {
        let filtered = suggestions.filter { $0.reps >= 5 && $0.reps <= 10 }

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
                .onAppear {
                    seedIfNeeded()
                    if selectedExercisesId == nil {
                        selectedExercisesId = exercises.first?.id
                        resetToDefaults()
                    }
                    // Initialize weight delta to 2.5 if available, otherwise closest option
                    if !availableWeightDeltas.contains(where: { abs($0 - weightDelta) < 0.01 }) {
                        // Current delta not valid, pick new one
                        if availableWeightDeltas.contains(where: { abs($0 - 2.5) < 0.01 }) {
                            weightDelta = 2.5
                        } else {
                            // Find closest to 2.5
                            weightDelta = availableWeightDeltas.min(by: { abs($0 - 2.5) < abs($1 - 2.5) }) ?? minWeightDelta
                        }
                    }
                }
                .onChange(of: selectedExercisesId) { _, _ in
                    resetToDefaults()
                }
                .onChange(of: selectedSetData.shouldPopulate) { _, shouldPopulate in
                    if shouldPopulate {
                        populateFromSelectedSet()
                        selectedSetData.shouldPopulate = false
                    }
                }
                .sheet(isPresented: $showingAddExercises) {
                    addExercisesSheet
                        .presentationDetents([.height(340)])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showWeightPicker) {
                    weightPickerSheet
                        .presentationDetents([.height(480)])
                        .presentationDragIndicator(.visible)
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
                    .presentationDetents([.fraction(0.95)])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showBodyweightCapture) {
                    bodyweightCaptureSheet
                        .presentationDetents([.height(480)])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showExercisesNotes) {
                    exerciseNotesSheet
                        .presentationDetents([.height(300)])
                        .presentationDragIndicator(.visible)
                }

                if showSubmitOverlay {
                    SubmitOverlayView(
                        didIncrease: overlayDidIncrease,
                        delta: overlayDelta,
                        new1RM: overlayNew1RM
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

                if showValidationMessage {
                    ValidationMessageOverlayView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(10)
                        .allowsHitTesting(false)
                }

                if showLogConfirmation {
                    ConfirmationOverlayView(
                        exerciseName: selectedExercises?.name ?? "Exercises",
                        reps: reps,
                        weight: weight,
                        userBodyweight: userProperties.bodyweight,
                        isBodyweightExercises: selectedExercises?.exerciseLoadType == .bodyweightPlusSingleLoad,
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
            .navigationBarHidden(true)
        }
    }

    private var addExercisesSheet: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Button("Cancel") {
                    newExercisesName = ""
                    newExercisesLoadType = .barbell
                    showingAddExercises = false
                }
                .foregroundStyle(Color.appAccent)

                Spacer()

                Text("Add Exercises")
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
                // Exercises Name Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercises Name")
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
        VStack(spacing: 20) {
            // Weight display
            Spacer()
                .frame(height: 20)
            VStack(spacing: 4) {
                Text(weightInput.isEmpty || weightInput == "---" ? "---" : weightInput)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(height: 60)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("lbs")
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
                                handleWeightInput(number)
                            } label: {
                                Text(number)
                                    .font(.title2.weight(.semibold))
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
                    Button {
                        if !weightInput.contains(".") {
                            if weightInput == "---" {
                                weightInput = "0."
                            } else if weightInput == "0" {
                                weightInput = "0."
                            } else {
                                weightInput += "."
                            }
                        }
                    } label: {
                        Text(".")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color(white: 0.18))
                            .cornerRadius(12)
                    }

                    Button {
                        handleWeightInput("0")
                    } label: {
                        Text("0")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color(white: 0.18))
                            .cornerRadius(12)
                    }

                    Button {
                        if !weightInput.isEmpty && weightInput != "---" {
                            weightInput.removeLast()
                            if weightInput.isEmpty {
                                weightInput = "---"
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
                    weightInput = "---"
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
                    if weightInput != "---", let value = Double(weightInput), value >= 0, value <= 1000 {
                        weight = value
                        hasSetInitialValues = true
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
            if hasSetInitialValues {
                weightInput = weight.rounded1().formatted(.number.precision(.fractionLength(2)))
            } else {
                weightInput = "---"
            }
        }
    }

    private func handleWeightInput(_ digit: String) {
        // If starting from "---", replace with digit
        if weightInput == "---" {
            weightInput = digit
            return
        }

        // Check if we're at max digits
        let parts = weightInput.split(separator: ".")
        let wholePart = String(parts.first ?? "")
        let decimalPart = parts.count > 1 ? String(parts[1]) : ""

        // If input is "0" and no decimal, replace it with the new digit
        if weightInput == "0" && digit != "0" {
            weightInput = digit
            return
        }

        // If we have 3 digits before decimal and no decimal point, overwrite with new digit
        if wholePart.count >= 3 && !weightInput.contains(".") {
            weightInput = digit
            return
        }

        // If we have 2 decimal places already, overwrite entire value with new digit
        if decimalPart.count >= 2 {
            weightInput = digit
            return
        }

        // Otherwise, append the digit if within limits
        let testInput = weightInput + digit
        if let value = Double(testInput), value <= 1000 {
            weightInput += digit
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
                                    .font(.title2.weight(.semibold))
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
                            .font(.title2.weight(.semibold))
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
            if hasSetInitialValues {
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
        VStack(spacing: 20) {
            // Bodyweight display
            Spacer()
                .frame(height: 20)
            VStack(spacing: 4) {
                Text(bodyweightInput.isEmpty || bodyweightInput == "---" ? "---" : bodyweightInput)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(height: 60)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("lbs")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(white: 0.12))
            .cornerRadius(12)
            .padding(.horizontal)

            Text("Enter your bodyweight")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            // Number pad
            VStack(spacing: 12) {
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { number in
                            Button {
                                handleBodyweightInput(number)
                            } label: {
                                Text(number)
                                    .font(.title2.weight(.semibold))
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
                    Button {
                        if !bodyweightInput.contains(".") {
                            if bodyweightInput == "---" {
                                bodyweightInput = "0."
                            } else if bodyweightInput == "0" {
                                bodyweightInput = "0."
                            } else {
                                bodyweightInput += "."
                            }
                        }
                    } label: {
                        Text(".")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color(white: 0.18))
                            .cornerRadius(12)
                    }

                    Button {
                        handleBodyweightInput("0")
                    } label: {
                        Text("0")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color(white: 0.18))
                            .cornerRadius(12)
                    }

                    Button {
                        if !bodyweightInput.isEmpty && bodyweightInput != "---" {
                            bodyweightInput.removeLast()
                            if bodyweightInput.isEmpty {
                                bodyweightInput = "---"
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
                    bodyweightInput = "---"
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
                    if bodyweightInput != "---", let value = Double(bodyweightInput), value > 0, value <= 1000 {
                        userProperties.bodyweight = value
                        try? modelContext.save()
                    }
                    showBodyweightCapture = false
                    showLogConfirmation = true
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
            if let bw = userProperties.bodyweight {
                bodyweightInput = bw.rounded1().formatted(.number.precision(.fractionLength(2)))
            } else {
                bodyweightInput = "---"
            }
        }
    }

    private func handleBodyweightInput(_ digit: String) {
        // Similar logic to weight input
        if bodyweightInput == "---" {
            if digit != "0" {
                bodyweightInput = digit
            }
            return
        }

        let parts = bodyweightInput.split(separator: ".")
        let wholePart = parts.first ?? ""

        if bodyweightInput == "0" {
            bodyweightInput = digit
            return
        }

        if wholePart.count >= 3 && !bodyweightInput.contains(".") {
            bodyweightInput = digit
            return
        }

        let testInput = bodyweightInput + digit
        if let value = Double(testInput), value <= 1000 {
            bodyweightInput += digit
        }
    }

    private var exerciseNotesSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    showExercisesNotes = false
                }
                .foregroundStyle(Color.appAccent)

                Spacer()

                Text("\(selectedExercises?.name ?? "Exercises") Notes")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button("Save") {
                    if let ex = selectedExercises {
                        ex.notes = exerciseNotesInput.isEmpty ? nil : exerciseNotesInput
                        try? modelContext.save()
                    }
                    showExercisesNotes = false
                }
                .foregroundStyle(Color.appAccent)
            }
            .padding(.horizontal)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Notes text editor
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $exerciseNotesInput)
                    .padding(8)
                    .background(Color(white: 0.12))
                    .cornerRadius(8)
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
            .padding(.horizontal)
            .padding(.bottom, 4)
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
            showExercisesSelection = true
        } label: {
            VStack(spacing: 4) {
                HStack {
                    Spacer()
                    Text(selectedExercises?.name ?? "Select Exercises")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.caption)
                }

                HStack {
                    Text("Current Estimated 1RM:")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(current1RM > 0 ? current1RM.rounded1().formatted(.number.precision(.fractionLength(2))) : "--")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                }
            }
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
            // Notes icon in left area
            if selectedExercises != nil {
                Button {
                    exerciseNotesInput = selectedExercises?.notes ?? ""
                    showExercisesNotes = true
                } label: {
                    HStack {
                        Image(systemName: "doc.plaintext")
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
            Text(current1RM > 0 ? current1RM.rounded1().formatted(.number.precision(.fractionLength(2))) : "--")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private struct EmptyGraphView: View {
        var body: some View {
            ZStack {
                // Sample chart with colorful bars
                Chart {
                    // Create sample bars with different intensity values to showcase colors
                    let green = Color(red: 0x84/255, green: 0xCC/255, blue: 0x16/255)
                    let yellow = Color(red: 0xEA/255, green: 0xB3/255, blue: 0x08/255)
                    let orange = Color(red: 0xF9/255, green: 0x73/255, blue: 0x16/255)
                    let red = Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255)
                    let cyan = Color(red: 0x06/255, green: 0xB6/255, blue: 0xD4/255)

                    let sampleData: [(height: Double, color: [Color])] = [
                        (60, [green, green.opacity(0.8)]), // Easy
                        (75, [yellow, yellow.opacity(0.8)]), // Moderate
                        (85, [orange, orange.opacity(0.8)]), // Hard
                        (95, [red, red.opacity(0.8)]), // Near Failure
                        (110, [cyan, cyan.opacity(0.8)]), // PR
                        (100, [red, red.opacity(0.8)]), // Near Failure
                        (90, [orange, orange.opacity(0.8)]), // Hard
                        (105, [red, red.opacity(0.8)]), // Near Failure
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

                // Overlay text
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.appAccent.opacity(0.3))

                    Text("No Estimates Yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Your 1RM estimates will appear here")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 95)
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

        private func colorForPercentage(_ percentage: Double, isPR: Bool) -> [Color] {
            // If it's a PR, use special cyan gradient
            if isPR {
                let cyan = Color(red: 0x06/255, green: 0xB6/255, blue: 0xD4/255)
                return [cyan, cyan.opacity(0.8)]
            }

            // Otherwise, color by percentage of current 1RM (intensity)
            switch percentage {
            case 85...:
                // 85%+ - Near Failure - Red
                let red = Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255)
                return [red, red.opacity(0.8)]
            case 75..<85:
                // 75-85% - Hard - Orange
                let orange = Color(red: 0xF9/255, green: 0x73/255, blue: 0x16/255)
                return [orange, orange.opacity(0.8)]
            case 65..<75:
                // 65-75% - Moderate - Yellow
                let yellow = Color(red: 0xEA/255, green: 0xB3/255, blue: 0x08/255)
                return [yellow, yellow.opacity(0.8)]
            default:
                // < 65% - Easy - Green
                let green = Color(red: 0x84/255, green: 0xCC/255, blue: 0x16/255)
                return [green, green.opacity(0.8)]
            }
        }

        private func barMark(index: Int, setInfo: SetWithPR, isSelected: Bool) -> some ChartContent {
            let colors: [Color]

            if isSelected {
                // Bright white gradient for selected bar
                colors = [.white, Color(white: 0.9)]
            } else {
                colors = colorForPercentage(setInfo.percentageOfCurrent, isPR: setInfo.wasPR)
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

    private var graphContentView: some View {
        Group {
            if setsWithPRInfo.isEmpty {
                EmptyGraphView()
            } else {
                ZStack {
                    HStack(spacing: 0) {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 0) {
                                    SetHistoryChart(setsWithPRInfo: setsWithPRInfo, showYAxis: false, selectedBarIndex: $selectedChartBarIndex)
                                        .id("chart-end")
                                }
                            }
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    proxy.scrollTo("chart-end", anchor: .trailing)
                                }
                            }
                            .onChange(of: setsWithPRInfo.count) { _, _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation {
                                        proxy.scrollTo("chart-end", anchor: .trailing)
                                    }
                                }
                            }
                        }

                        // Fixed Y-axis on the right
                        SetHistoryChartYAxis(setsWithPRInfo: setsWithPRInfo)
                    }

                    if let index = selectedChartBarIndex, index < setsWithPRInfo.count {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()

                        setDetailOverlay(for: setsWithPRInfo[index])
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            }
        }
    }

    @State private var selectedChartBarIndex: Int? = nil

    private func setDetailOverlay(for setInfo: SetWithPR) -> some View {
        VStack(spacing: 8) {
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
                Text("Intensity: \(Int(setInfo.percentageOfCurrent))% of current")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Text("Est. 1RM: \(setInfo.estimated1RM.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appAccent)
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
        let today = calendar.startOfDay(for: Date())
        return allSets.filter { set in
            set.exercise?.id == ex.id &&
            calendar.isDate(set.createdAt, inSameDayAs: today)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    private var lastDayDate: Date? {
        guard let ex = selectedExercises else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

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
        Group {
            if todaysSets.isEmpty && lastDaySets.isEmpty {
                // Empty state matching the graph placeholder
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.appAccent.opacity(0.3))

                    Text("No Sets Yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Your set intensity will appear here")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                // Today's Sets (now on top)
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
                        // Empty state when there's no today's sets but history exists
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
                                        selectedSquareId: selectedSquareId
                                    )
                                    .onTapGesture {
                                        weight = set.weight
                                        reps = set.reps
                                        hasSetInitialValues = true
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

                // Previous Day Sets (now on bottom)
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
                        // Truly empty - no visualization, just empty space
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
                                        selectedSquareId: selectedSquareId
                                    )
                                    .onTapGesture {
                                        weight = set.weight
                                        reps = set.reps
                                        hasSetInitialValues = true
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

                Spacer()
                    .frame(height: 8)
                }
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
                        Text("Sets")
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
            .padding(.top, 12)
            .padding(.bottom, 10)

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
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Legend
            HStack(spacing: 10) {
                LegendItem(color: Color(red: 0x84/255, green: 0xCC/255, blue: 0x16/255), label: "Easy")
                LegendItem(color: Color(red: 0xEA/255, green: 0xB3/255, blue: 0x08/255), label: "Moderate")
                LegendItem(color: Color(red: 0xF9/255, green: 0x73/255, blue: 0x16/255), label: "Hard")
                LegendItem(color: Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255), label: "Redline")
                LegendItem(color: Color(red: 0x06/255, green: 0xB6/255, blue: 0xD4/255), label: "Est. 1RM PR")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(height: 244)
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
                HStack(spacing: 3) {
                    Text("Options to")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Image(systemName: "arrow.up")
                        .font(.caption)
                        .foregroundStyle(.white)
                    Text("Est. 1RM")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        // Find previous delta in availableWeightDeltas
                        if let currentIndex = availableWeightDeltas.firstIndex(where: { abs($0 - weightDelta) < 0.01 }),
                           currentIndex > 0 {
                            weightDelta = availableWeightDeltas[currentIndex - 1]
                            hapticFeedback.impactOccurred()
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(weightDelta > minWeightDelta ? Color.appAccent : .gray)
                    }
                    .disabled(weightDelta <= minWeightDelta)

                    VStack(spacing: 0) {
                        Text(weightDelta.formatted(.number.precision(.fractionLength(1))))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Δ LB")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.appLabel)
                    }
                    .frame(width: 55)

                    Button {
                        // Find next delta in availableWeightDeltas
                        if let currentIndex = availableWeightDeltas.firstIndex(where: { abs($0 - weightDelta) < 0.01 }),
                           currentIndex < availableWeightDeltas.count - 1 {
                            weightDelta = availableWeightDeltas[currentIndex + 1]
                            hapticFeedback.impactOccurred()
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(weightDelta < maxWeightDelta ? Color.appAccent : .gray)
                    }
                    .disabled(weightDelta >= maxWeightDelta)
                }
            }

            if current1RM < 0.1 {
                // No data state
                ProgressOptionsEmptyState()
                    .frame(maxWidth: .infinity)
                    .frame(height: 135)
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
                                    .foregroundStyle(columnHighlighted && (sortColumn == .est1RM || sortColumn == .gain) ? Color.appAccent : Color.appLabel)
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
                                    .foregroundStyle(columnHighlighted && (sortColumn == .gain || sortColumn == .est1RM) ? Color.appAccent : Color.appLabel)
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
                            .frame(height: 112)
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
    }

    private var logSetSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Weight with increment/decrement
                HStack(spacing: 8) {
                    Button {
                        if !hasSetInitialValues {
                            weight = selectedExercises?.exerciseLoadType == .barbell ? 45.0 : 0.0
                        } else {
                            weight = max(0, weight - smallestPlateIncrement)
                        }
                        hasSetInitialValues = true
                        hapticFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.appAccent)
                    }

                    Button {
                        showWeightPicker = true
                    } label: {
                        VStack(spacing: 1) {
                            if selectedExercises?.exerciseLoadType == .bodyweightPlusSingleLoad {
                                Text("Bodyweight +")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Text(hasSetInitialValues ? weight.rounded1().formatted(.number.precision(.fractionLength(2))) : "---")
                                .font(.title3.weight(.bold))
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
                        if !hasSetInitialValues {
                            weight = selectedExercises?.exerciseLoadType == .barbell ? 45.0 : 0.0
                        } else {
                            weight = min(1000, weight + smallestPlateIncrement)
                        }
                        hasSetInitialValues = true
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
                        hasSetInitialValues = true
                        reps = max(1, reps - 1)
                        hapticFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.appAccent)
                    }

                    Button {
                        showRepsPicker = true
                    } label: {
                        VStack(spacing: 2) {
                            Text(hasSetInitialValues ? "\(reps)" : "---")
                                .font(.title3.weight(.bold))
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
                        hasSetInitialValues = true
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
                if !hasSetInitialValues {
                    showValidationMessage = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.18)) {
                                showValidationMessage = false
                            }
                        }
                    }
                } else {
                    // Check if bodyweight is needed
                    if selectedExercises?.exerciseLoadType == .bodyweightPlusSingleLoad && userProperties.bodyweight == nil {
                        showBodyweightCapture = true
                    } else {
                        showLogConfirmation = true
                    }
                }
            } label: {
                Text("Log Set")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.appAccent)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

        @State private var pulse = false

        var body: some View {
            ZStack {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    Image(systemName: didIncrease ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)

                    if didIncrease {
                        VStack(spacing: 4) {
                            Text("Increased 1RM by")
                                .font(.subheadline)
                            Text("+\(delta.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.appAccent)
                        }
                    } else {
                        Text("Set Logged")
                            .font(.headline)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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

    private struct CancelOverlayView: View {
        @State private var pulse = false

        var body: some View {
            ZStack {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)

                    Text("Cancelled")
                        .font(.headline)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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

    private struct ValidationMessageOverlayView: View {
        @State private var pulse = false

        var body: some View {
            ZStack {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.orange)

                    Text("Please enter weight and reps")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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
        let exerciseName: String
        let reps: Int
        let weight: Double
        let userBodyweight: Double?
        let isBodyweightExercises: Bool
        let onConfirm: () -> Void
        let onCancel: () -> Void

        private var displayWeight: Double {
            if isBodyweightExercises, let bw = userBodyweight {
                return bw + weight
            }
            return weight
        }

        private var weightText: String {
            if isBodyweightExercises, let bw = userBodyweight {
                return "\(bw.rounded1().formatted(.number.precision(.fractionLength(2)))) (BW) + \(weight.rounded1().formatted(.number.precision(.fractionLength(2)))) = \(displayWeight.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs"
            }
            return "\(weight.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs"
        }

        var body: some View {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onCancel()
                    }

                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Text("Confirm Log Set")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)

                        VStack(spacing: 6) {
                            Text(exerciseName)
                                .font(.headline)
                                .foregroundStyle(Color.appAccent)

                            Text("\(reps) reps × \(weightText)")
                                .font(.body)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            onCancel()
                        } label: {
                            Text("Cancel")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(white: 0.25))
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onConfirm()
                        } label: {
                            Text("Confirm")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.appAccent)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
                .background(
                    LinearGradient(
                        colors: [Color(white: 0.18), Color(white: 0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                .padding(.horizontal, 40)
            }
        }
    }

    private func addExercises() {
        let trimmed = newExercisesName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let ex = Exercises(name: trimmed, isCustom: true, loadType: newExercisesLoadType)
        modelContext.insert(ex)
        selectedExercisesId = ex.id

        newExercisesName = ""
        newExercisesLoadType = .barbell
        showingAddExercises = false
    }

    private func resetToDefaults() {
        reps = 8
        if current1RM < 0.1 {
            weight = 20.0
        } else {
            weight = (current1RM * 0.8).rounded()
        }
        hasSetInitialValues = false
    }

    private func populateFromSelectedSet() {
        if let exerciseId = selectedSetData.exerciseId {
            selectedExercisesId = exerciseId
        }
        if let repsValue = selectedSetData.reps {
            reps = repsValue
            hasSetInitialValues = true
        }
        if let weightValue = selectedSetData.weight {
            weight = weightValue
            hasSetInitialValues = true
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

        // Store the added weight (not total) for all exercises
        // For bodyweight exercises, we'll add bodyweight when calculating 1RM
        let actualWeight = weight == 0.0 ? 1.0 : weight
        let set = LiftSet(exercise: ex, reps: reps, weight: actualWeight)
        modelContext.insert(set)

        let simulatedSets = setsForSelected + [set]
        // For bodyweight exercises, add bodyweight before calculating 1RM
        let adjustedSets: [LiftSet]
        if ex.exerciseLoadType == .bodyweightPlusSingleLoad, let bw = userProperties.bodyweight {
            adjustedSets = simulatedSets.compactMap { s in
                guard let exercise = s.exercise else { return nil }
                let adjusted = LiftSet(exercise: exercise, reps: s.reps, weight: s.weight + bw)
                adjusted.createdAt = s.createdAt
                adjusted.createdTimezone = s.createdTimezone
                return adjusted
            }
        } else {
            adjustedSets = simulatedSets
        }
        let after = OneRMCalculator.current1RM(from: adjustedSets)

        let d = after - before
        let increased = d > 0.0001

        // Create a new Estimated1RM record for every set
        if after > 0 {
            let estimated = Estimated1RM(exercise: ex, value: after)
            modelContext.insert(estimated)
        }

        overlayDidIncrease = increased
        overlayDelta = d
        overlayNew1RM = after

        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            showSubmitOverlay = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
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

    private func deleteExercises() {
        guard let ex = selectedExercises, ex.isCustom else { return }

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

        showExercisesDetails = false
    }

    private func seedIfNeeded() {
        guard exercises.isEmpty else { return }

        let defaults: [(String, ExerciseLoadType)] = [
            ("Deadlift", .barbell),
            ("Squat", .barbell),
            ("Bench Press", .barbell),
            ("Overhead Press", .barbell),
            ("Barbell Row", .barbell),
            ("Pull Ups", .bodyweightPlusSingleLoad),
            ("Dips", .bodyweightPlusSingleLoad)
        ]
        for (name, loadType) in defaults {
            let exercise = Exercises(name: name, isCustom: false, loadType: loadType)
            modelContext.insert(exercise)
        }

        // Seed default plate weights
        if userProperties.plateWeights.isEmpty {
            userProperties.plateWeights = UserProperties.defaultPlateWeights
        }

        try? modelContext.save()
    }
}

struct ExercisesSelectionView: View {
    let exercises: [Exercises]
    @Binding var selectedExercisesId: UUID?
    let onAddExercises: () -> Void
    let onEditExercises: (Exercises) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    // Add Exercises Button (first item)
                    Button {
                        onAddExercises()
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.appAccent)

                            Text("Add Exercises")
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

                    ForEach(exercises) { exercise in
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
                .padding(16)
            }
        }
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
                // Placeholder icon
                Image(systemName: exerciseIcon(for: exercise))
                    .font(.system(size: 36))
                    .foregroundStyle(Color.appAccent)

                Text(exercise.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if exercise.isCustom {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .onTapGesture {
                        onEdit()
                    }
                }
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

    private func exerciseIcon(for exercise: Exercises) -> String {
        // Map exercise names to SF Symbols icons
        switch exercise.name.lowercased() {
        case let name where name.contains("bench"):
            return "figure.strengthtraining.traditional"
        case let name where name.contains("squat"):
            return "figure.squat"
        case let name where name.contains("deadlift"):
            return "figure.cooldown"
        case let name where name.contains("press") && name.contains("overhead"):
            return "figure.arms.open"
        case let name where name.contains("row"):
            return "figure.rowing"
        case let name where name.contains("pull"):
            return "figure.climbing"
        case let name where name.contains("dip"):
            return "figure.core.training"
        default:
            return "dumbbell.fill"
        }
    }
}

struct SetSquareView: View {
    let set: LiftSet
    let allSets: [LiftSet]
    let currentWeight: Double
    let currentReps: Int
    let hasSetValues: Bool
    let selectedSquareId: UUID?

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
        for prevSet in previousSets {
            let estimated = OneRMCalculator.estimate1RM(weight: prevSet.weight, reps: prevSet.reps)
            currentMax = max(currentMax, estimated)
        }

        let setEstimated1RM = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)
        let isPR = setEstimated1RM > currentMax
        let percentage = currentMax > 0 ? (setEstimated1RM / currentMax) * 100 : 100.0

        let color: Color
        if isPR {
            // PR - Special cyan
            color = Color(red: 0x06/255, green: 0xB6/255, blue: 0xD4/255)
        } else {
            switch percentage {
            case 85...:
                // Near Failure - Red
                color = Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255)
            case 75..<85:
                // Hard - Orange
                color = Color(red: 0xF9/255, green: 0x73/255, blue: 0x16/255)
            case 65..<75:
                // Moderate - Yellow
                color = Color(red: 0xEA/255, green: 0xB3/255, blue: 0x08/255)
            default:
                // Easy - Green
                color = Color(red: 0x84/255, green: 0xCC/255, blue: 0x16/255)
            }
        }

        return (color: color, isPR: isPR)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(set.weight))")
                .font(.caption.weight(.bold))
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
    }
}

struct DemoSetSquare: View {
    let color: Color

    private var actualColor: Color {
        switch color {
        case .green:
            return Color(red: 0x84/255, green: 0xCC/255, blue: 0x16/255) // Easy
        case .yellow:
            return Color(red: 0xEA/255, green: 0xB3/255, blue: 0x08/255) // Moderate
        case .orange:
            return Color(red: 0xF9/255, green: 0x73/255, blue: 0x16/255) // Hard
        case .red:
            return Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255) // Near Failure
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
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundStyle(
                    LinearGradient(
                        colors: isAnimating
                            ? [Color.appAccent.opacity(0.6), Color.appAccent.opacity(0.3)]
                            : [Color.appAccent.opacity(0.3), Color.appAccent.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(isAnimating ? 1.1 : 1.0)
            Text("No Sets Yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Complete a set to see progression suggestions")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
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
