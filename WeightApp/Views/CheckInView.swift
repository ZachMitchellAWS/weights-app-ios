import SwiftUI
import SwiftData
import Charts

struct CheckInView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Exercise.createdAt) private var exercises: [Exercise]
    @Query(sort: \LiftSet.createdAt, order: .reverse) private var allSets: [LiftSet]
    @Query private var settingsItems: [AppSettings]
    @Query(sort: \Estimated1RM.timestamp, order: .reverse) private var allEstimated1RMs: [Estimated1RM]
    @Query(sort: \PlateModel.weight, order: .reverse) private var availablePlates: [PlateModel]

    @ObservedObject var selectedSetData: SelectedSetData

    @State private var selectedExerciseId: UUID?
    @State private var showingAddExercise = false

    @State private var reps: Int = 8
    @State private var weight: Double = 20.0
    @State private var hasSetInitialValues = false

    @State private var newExerciseName: String = ""
    @State private var newExerciseLoadType: ExerciseLoadType = .twoSided

    @State private var showSubmitOverlay = false
    @State private var overlayDidIncrease = false
    @State private var overlayDelta: Double = 0
    @State private var overlayNew1RM: Double = 0

    @State private var showWeightPicker = false
    @State private var weightInput: String = ""
    @State private var showRepsPicker = false
    @State private var repsInput: String = ""
    @State private var showExerciseDetails = false
    @State private var editingExerciseName = ""
    @State private var editingExerciseLoadType: ExerciseLoadType = .twoSided
    @State private var showLogConfirmation = false
    @State private var showCancelOverlay = false
    @State private var weightDelta: Double = 5.0
    @State private var showExerciseSelection = false
    @State private var selectedGraphTab: Int = 0 // 0 = Set Intensity, 1 = 1RM Graph

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    private var settings: AppSettings {
        if let s = settingsItems.first { return s }
        let s = AppSettings()
        modelContext.insert(s)
        return s
    }

    private var selectedExercise: Exercise? {
        if let id = selectedExerciseId {
            return exercises.first(where: { $0.id == id })
        }
        return exercises.first
    }

    private var setsForSelected: [LiftSet] {
        guard let ex = selectedExercise else { return [] }
        return allSets.filter { $0.exercise?.id == ex.id }
    }

    private var estimated1RMsForSelected: [Estimated1RM] {
        guard let ex = selectedExercise else { return [] }
        return allEstimated1RMs.filter { $0.exercise?.id == ex.id }
    }

    private struct SetWithPR {
        let set: LiftSet
        let estimated1RM: Double
        let wasPR: Bool
        let percentageOfCurrent: Double
    }

    private var setsWithPRInfo: [SetWithPR] {
        guard let ex = selectedExercise else { return [] }
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
        return OneRMCalculator.current1RM(from: setsForSelected)
    }

    private var smallestPlateIncrement: Double {
        // Get the smallest available plate weight
        // Since we need to load both sides of the barbell, the increment is 2x the smallest plate
        let smallestPlate = availablePlates.min(by: { $0.weight < $1.weight })?.weight ?? 2.5
        return smallestPlate * 2.0
    }

    private var availableWeightDeltas: [Double] {
        // Calculate all physically achievable increments from available plates
        // Each plate can go on both sides, so increment = plate × 2
        var deltas = Set<Double>()
        for plate in availablePlates {
            let increment = plate.weight * 2.0
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
        OneRMCalculator.minimizedSuggestions(current1RM: current1RM, increment: weightDelta)
    }

    private var topThreeSuggestions: [OneRMCalculator.Suggestion] {
        suggestions
            .filter { $0.reps >= 5 && $0.reps <= 10 }
            .sorted { $0.projected1RM < $1.projected1RM }
            .prefix(5)
            .map { $0 }
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
                    // Styled Exercise Selector
                    styledExerciseSelector
                        .padding(.top, 12)

                    // Estimated 1RM Graph
                    estimated1RMGraphWidget

                    // Progress Options
                    optionsSection

                    Divider()
                        .background(.white.opacity(0.15))
                        .padding(.horizontal, 4)

                    // Log Set Section
                    logSetSection

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .onAppear {
                    seedIfNeeded()
                    if selectedExerciseId == nil {
                        selectedExerciseId = exercises.first?.id
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
                .onChange(of: selectedExerciseId) { _, _ in
                    resetToDefaults()
                }
                .onChange(of: selectedSetData.shouldPopulate) { _, shouldPopulate in
                    if shouldPopulate {
                        populateFromSelectedSet()
                        selectedSetData.shouldPopulate = false
                    }
                }
                .sheet(isPresented: $showingAddExercise) {
                    addExerciseSheet
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
                .sheet(isPresented: $showExerciseDetails) {
                    exerciseDetailsSheet
                        .presentationDetents([.height(selectedExercise?.isCustom == true ? 420 : 340)])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showExerciseSelection) {
                    ExerciseSelectionView(
                        exercises: exercises,
                        selectedExerciseId: $selectedExerciseId,
                        onAddExercise: {
                            showExerciseSelection = false
                            showingAddExercise = true
                        },
                        onEditExercise: { exercise in
                            showExerciseSelection = false
                            editingExerciseName = exercise.name
                            editingExerciseLoadType = exercise.exerciseLoadType
                            showExerciseDetails = true
                        }
                    )
                    .presentationDetents([.fraction(0.95)])
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

                if showLogConfirmation {
                    ConfirmationOverlayView(
                        exerciseName: selectedExercise?.name ?? "Exercise",
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
            .navigationBarHidden(true)
        }
    }

    private var addExerciseSheet: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Button("Cancel") {
                    newExerciseName = ""
                    newExerciseLoadType = .twoSided
                    showingAddExercise = false
                }
                .foregroundStyle(Color.appAccent)

                Spacer()

                Text("Add Exercise")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button("Add") {
                    addExercise()
                }
                .foregroundStyle(Color.appAccent)
                .disabled(newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            VStack(spacing: 16) {
                // Exercise Name Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercise Name")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    TextField("e.g. Romanian Deadlift", text: $newExerciseName)
                        .textInputAutocapitalization(.words)
                        .font(.body)
                        .padding(14)
                        .background(Color(white: 0.12))
                        .cornerRadius(10)
                        .foregroundStyle(.white)
                }

                // Load Type Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Load Type")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    Picker("Load Type", selection: $newExerciseLoadType) {
                        ForEach(ExerciseLoadType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
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
                Text(weightInput.isEmpty || weightInput == "0" ? "0" : weightInput)
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
                            if weightInput == "0" {
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
                        if !weightInput.isEmpty && weightInput != "0" {
                            weightInput.removeLast()
                            if weightInput.isEmpty {
                                weightInput = "0"
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
                    weightInput = "0"
                } label: {
                    Text("Clear")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.black.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color.yellow.opacity(0.5))
                        .cornerRadius(12)
                }

                Button {
                    if let value = Double(weightInput), value > 0, value <= 1000 {
                        weight = value
                        hasSetInitialValues = true
                    }
                    showWeightPicker = false
                } label: {
                    Text("Done")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color.green)
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
            if weight > 0 {
                weightInput = "\(Int(weight))"
            } else {
                weightInput = "0"
            }
        }
    }

    private func handleWeightInput(_ digit: String) {
        // Check if we're at max digits (3 digits before decimal)
        let parts = weightInput.split(separator: ".")
        let wholePart = parts.first ?? ""

        // If input is "0", replace it with the new digit (prevent leading zeros)
        if weightInput == "0" {
            weightInput = digit
            return
        }

        // If we have 3 digits before decimal and no decimal point, overwrite with new digit
        if wholePart.count >= 3 && !weightInput.contains(".") {
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
                Text(repsInput.isEmpty || repsInput == "0" ? "0" : repsInput)
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
                        if !repsInput.isEmpty && repsInput != "0" {
                            repsInput.removeLast()
                            if repsInput.isEmpty {
                                repsInput = "0"
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
                    repsInput = "0"
                } label: {
                    Text("Clear")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.black.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color.yellow.opacity(0.5))
                        .cornerRadius(12)
                }

                Button {
                    if let value = Int(repsInput), value > 0, value <= 99 {
                        reps = value
                    }
                    showRepsPicker = false
                } label: {
                    Text("Done")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color.green)
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
            if reps > 0 {
                repsInput = "\(reps)"
            } else {
                repsInput = "0"
            }
        }
    }

    private func handleRepsInput(_ digit: String) {
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

    private var exerciseDetailsSheet: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Button("Cancel") {
                    showExerciseDetails = false
                }
                .foregroundStyle(Color.appAccent)

                Spacer()

                Text("Exercise Details")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button("Save") {
                    saveExerciseDetails()
                }
                .foregroundStyle(Color.appAccent)
                .disabled(editingExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(editingExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            VStack(spacing: 16) {
                // Exercise Name Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercise Name")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    TextField("Exercise name", text: $editingExerciseName)
                        .textInputAutocapitalization(.words)
                        .font(.body)
                        .padding(14)
                        .background(Color(white: 0.12))
                        .cornerRadius(10)
                        .foregroundStyle(.white)
                }

                // Load Type Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Load Type")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    Picker("Load Type", selection: $editingExerciseLoadType) {
                        ForEach(ExerciseLoadType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Delete button for custom exercises
                if selectedExercise?.isCustom == true {
                    Button {
                        deleteExercise()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Exercise")
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

    private var styledExerciseSelector: some View {
        Button {
            showExerciseSelection = true
        } label: {
            HStack {
                Spacer()
                Text(selectedExercise?.name ?? "Select Exercise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.caption)
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
                    // Create sample bars with different RIR values to showcase colors
                    let sampleData: [(height: Double, color: [Color])] = [
                        (60, [Color(red: 0.3, green: 0.8, blue: 0.3), Color(red: 0.2, green: 0.6, blue: 0.2)]), // Green (easy)
                        (75, [Color(red: 1.0, green: 0.9, blue: 0.2), Color(red: 0.9, green: 0.7, blue: 0.0)]), // Yellow (moderate)
                        (85, [Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 1.0, green: 0.4, blue: 0.0)]), // Orange (hard)
                        (95, [Color(red: 0.9, green: 0.2, blue: 0.2), Color(red: 0.7, green: 0.1, blue: 0.1)]), // Red (very hard)
                        (110, [Color.white, Color(white: 0.9)]), // White (PR)
                        (100, [Color(red: 0.9, green: 0.2, blue: 0.2), Color(red: 0.7, green: 0.1, blue: 0.1)]), // Red
                        (90, [Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 1.0, green: 0.4, blue: 0.0)]), // Orange
                        (105, [Color(red: 0.9, green: 0.2, blue: 0.2), Color(red: 0.7, green: 0.1, blue: 0.1)]), // Red
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

                    Text("No History Yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Your set history will appear here")
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
            // If it's a PR, use bright white gradient to stand out from intensity colors
            if isPR {
                return [Color.white, Color(white: 0.9)]
            }

            // Otherwise, color by percentage of current 1RM (difficulty)
            switch percentage {
            case 95...:
                // 95%+ of current - Very hard sets - Deep red to red
                return [Color(red: 0.9, green: 0.2, blue: 0.2), Color(red: 0.7, green: 0.1, blue: 0.1)]
            case 90..<95:
                // 90-95% of current - Hard sets - Orange to amber
                return [Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 1.0, green: 0.4, blue: 0.0)]
            case 80..<90:
                // 80-90% of current - Moderate sets - Yellow to gold
                return [Color(red: 1.0, green: 0.9, blue: 0.2), Color(red: 0.9, green: 0.7, blue: 0.0)]
            default:
                // < 80% of current - Easy sets - Green shades
                return [Color(red: 0.3, green: 0.8, blue: 0.3), Color(red: 0.2, green: 0.6, blue: 0.2)]
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
        guard let ex = selectedExercise else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return allSets.filter { set in
            set.exercise?.id == ex.id &&
            calendar.isDate(set.createdAt, inSameDayAs: today)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    private var lastDaySets: [LiftSet] {
        guard let ex = selectedExercise else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Find the most recent day (before today) when this exercise was performed
        let previousDays = allSets
            .filter { $0.exercise?.id == ex.id && $0.createdAt < today }
            .map { calendar.startOfDay(for: $0.createdAt) }

        guard let lastDay = Set(previousDays).sorted(by: >).first else { return [] }

        return allSets.filter { set in
            set.exercise?.id == ex.id &&
            calendar.isDate(set.createdAt, inSameDayAs: lastDay)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    private var setComparisonView: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                // Today's Sets (now on top)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    if todaysSets.isEmpty && lastDaySets.isEmpty {
                        // Demo visualization - only when both are empty
                        HStack(spacing: 6) {
                            DemoSetSquare(color: .green)
                            DemoSetSquare(color: .yellow)
                            DemoSetSquare(color: .orange)
                            DemoSetSquare(color: .red)
                            DemoSetSquare(color: .orange)
                            Spacer()
                        }
                        .frame(height: 42)
                    } else if todaysSets.isEmpty {
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
                            HStack(spacing: 4) {
                                ForEach(Array(todaysSets.enumerated()), id: \.element.id) { index, set in
                                    SetSquareView(set: set, allSets: allSets)
                                        .onTapGesture {
                                            weight = set.weight
                                            reps = set.reps
                                            hasSetInitialValues = true
                                            hapticFeedback.impactOccurred()
                                        }
                                }
                            }
                        }
                        .frame(height: 42)
                    }
                }

                // Last Day Sets (now on bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last Day")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    if lastDaySets.isEmpty && todaysSets.isEmpty {
                        // Demo visualization - only when both are empty
                        HStack(spacing: 6) {
                            DemoSetSquare(color: .green)
                            DemoSetSquare(color: .green)
                            DemoSetSquare(color: .yellow)
                            DemoSetSquare(color: .orange)
                            DemoSetSquare(color: .green)
                            Spacer()
                        }
                        .frame(height: 42)
                    } else if lastDaySets.isEmpty {
                        // Truly empty - no visualization, just empty space
                        Spacer()
                            .frame(height: 42)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(lastDaySets.enumerated()), id: \.element.id) { index, set in
                                    SetSquareView(set: set, allSets: allSets)
                                        .onTapGesture {
                                            weight = set.weight
                                            reps = set.reps
                                            hasSetInitialValues = true
                                            hapticFeedback.impactOccurred()
                                        }
                                }
                            }
                        }
                        .frame(height: 42)
                    }
                }
            }

            // Dim overlay for demo visualization
            if lastDaySets.isEmpty && todaysSets.isEmpty {
                LinearGradient(
                    colors: [Color(white: 0.18), Color(white: 0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            // Informative overlay when showing demo
            if lastDaySets.isEmpty && todaysSets.isEmpty {
                VStack(spacing: 2) {
                    Text("Set Intensity Tracker")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.appAccent)
                    Text("Colors show intensity")
                        .font(.caption2)
                        .foregroundStyle(Color.appAccent.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(white: 0.12))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.appAccent.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var estimated1RMGraphWidget: some View {
        VStack(spacing: 0) {
            // Tab Selector - Segmented Picker Style
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.1))
                    .frame(height: 32)

                // Sliding indicator
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.appAccent)
                        .frame(width: geometry.size.width / 2 - 4, height: 28)
                        .offset(x: selectedGraphTab == 0 ? 2 : geometry.size.width / 2 + 2)
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
                            .foregroundStyle(selectedGraphTab == 0 ? .white : .white.opacity(0.5))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            .foregroundStyle(selectedGraphTab == 1 ? .white : .white.opacity(0.5))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(height: 32)
                }
            }
            .frame(height: 32)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Content
            Group {
                if selectedGraphTab == 0 {
                    setComparisonView
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        graphHeaderView
                        graphContentView
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
        }
        .frame(height: 215)
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
                Text("Progress Options")
                    .font(.headline)
                    .foregroundStyle(.white)

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

                    VStack(spacing: 2) {
                        Text(weightDelta.formatted(.number.precision(.fractionLength(1))))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Δ LB")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.appLabel)
                    }
                    .frame(width: 50)

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
                    .frame(height: 160)
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(Array(topThreeSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                                ProgressOptionCard(
                                    suggestion: suggestion,
                                    isSelected: isOptionSelected(suggestion)
                                )
                                .onTapGesture {
                                    hapticFeedback.impactOccurred()
                                    selectOption(suggestion)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .frame(height: 160)

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
                    .frame(height: 40)
                    .allowsHitTesting(false)
                }
            }
        }
        .padding(16)
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
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                // Weight with increment/decrement
                HStack(spacing: 8) {
                    Button {
                        if !hasSetInitialValues {
                            weight = 45.0
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
                        hasSetInitialValues = true
                        showWeightPicker = true
                    } label: {
                        VStack(spacing: 2) {
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
                            weight = 45.0
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
                .padding(.vertical, 6)
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
                        hasSetInitialValues = true
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
                .padding(.vertical, 6)
                .background(Color(white: 0.12))
                .cornerRadius(10)
                .frame(maxWidth: .infinity)
            }

            // Log Set button spanning full width
            Button {
                hapticFeedback.impactOccurred()
                showLogConfirmation = true
            } label: {
                Text("Log Set")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
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

    private struct ConfirmationOverlayView: View {
        let exerciseName: String
        let reps: Int
        let weight: Double
        let onConfirm: () -> Void
        let onCancel: () -> Void

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

                            Text("\(reps) reps × \(weight.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs")
                                .font(.body)
                                .foregroundStyle(.white)
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
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onConfirm()
                        } label: {
                            Text("Confirm")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.green)
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

    private func addExercise() {
        let trimmed = newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let ex = Exercise(name: trimmed, isCustom: true, loadType: newExerciseLoadType)
        modelContext.insert(ex)
        selectedExerciseId = ex.id

        newExerciseName = ""
        newExerciseLoadType = .twoSided
        showingAddExercise = false
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
            selectedExerciseId = exerciseId
        }
        if let repsValue = selectedSetData.reps {
            reps = repsValue
            hasSetInitialValues = true
        }
        if let weightValue = selectedSetData.weight {
            weight = weightValue
            hasSetInitialValues = true
        }
    }

    private func isOptionSelected(_ suggestion: OneRMCalculator.Suggestion) -> Bool {
        // Check if current Log Set values match this suggestion
        return weight == suggestion.weight && reps == suggestion.reps
    }

    private func selectOption(_ suggestion: OneRMCalculator.Suggestion) {
        reps = suggestion.reps
        weight = suggestion.weight
        hasSetInitialValues = true
    }

    private func logSet() {
        guard let ex = selectedExercise else { return }

        let before = current1RM

        // Convert 0.0 weight to 1.0 behind the scenes
        let actualWeight = weight == 0.0 ? 1.0 : weight
        let set = LiftSet(exercise: ex, reps: reps, weight: actualWeight, rir: 0)
        modelContext.insert(set)

        let simulatedSets = setsForSelected + [set]
        let after = OneRMCalculator.current1RM(from: simulatedSets)

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

    private func saveExerciseDetails() {
        guard let ex = selectedExercise else { return }

        let trimmed = editingExerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        ex.name = trimmed
        ex.exerciseLoadType = editingExerciseLoadType

        showExerciseDetails = false
    }

    private func deleteExercise() {
        guard let ex = selectedExercise, ex.isCustom else { return }

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
        selectedExerciseId = exercises.first(where: { $0.id != ex.id })?.id

        showExerciseDetails = false
    }

    private func seedIfNeeded() {
        guard exercises.isEmpty else { return }

        let defaults: [(String, ExerciseLoadType)] = [
            ("Deadlifts", .twoSided),
            ("Squat", .twoSided),
            ("Bench Press", .twoSided),
            ("Overhead Press", .twoSided),
            ("Barbell Row", .twoSided),
            ("Pull-Up", .oneSided),
            ("Dip", .oneSided)
        ]
        for (name, loadType) in defaults {
            modelContext.insert(Exercise(name: name, isCustom: false, loadType: loadType))
        }

        if settingsItems.isEmpty {
            modelContext.insert(AppSettings())
        }
    }
}

struct ExerciseSelectionView: View {
    let exercises: [Exercise]
    @Binding var selectedExerciseId: UUID?
    let onAddExercise: () -> Void
    let onEditExercise: (Exercise) -> Void
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
                    // Add Exercise Button (first item)
                    Button {
                        onAddExercise()
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

                    ForEach(exercises) { exercise in
                        ExerciseCardButton(
                            exercise: exercise,
                            isSelected: selectedExerciseId == exercise.id,
                            onSelect: {
                                selectedExerciseId = exercise.id
                                dismiss()
                            },
                            onEdit: {
                                onEditExercise(exercise)
                            }
                        )
                    }
                }
                .padding(16)
            }
        }
    }
}

struct ExerciseCardButton: View {
    let exercise: Exercise
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

    private func exerciseIcon(for exercise: Exercise) -> String {
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
            color = Color.white
        } else {
            switch percentage {
            case 95...:
                color = Color(red: 0.9, green: 0.2, blue: 0.2)
            case 90..<95:
                color = Color(red: 1.0, green: 0.6, blue: 0.2)
            case 80..<90:
                color = Color(red: 1.0, green: 0.9, blue: 0.2)
            default:
                color = Color(red: 0.3, green: 0.8, blue: 0.3)
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
    }
}

struct DemoSetSquare: View {
    let color: Color

    private var actualColor: Color {
        switch color {
        case .green:
            return Color(red: 0.3, green: 0.8, blue: 0.3)
        case .yellow:
            return Color(red: 1.0, green: 0.9, blue: 0.2)
        case .orange:
            return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .red:
            return Color(red: 0.9, green: 0.2, blue: 0.2)
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
                .foregroundStyle(.white.opacity(0.7))
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
