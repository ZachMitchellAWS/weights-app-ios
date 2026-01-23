import SwiftUI
import SwiftData
import Charts

struct CheckInView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Exercise.createdAt) private var exercises: [Exercise]
    @Query(sort: \LiftSet.createdAt, order: .reverse) private var allSets: [LiftSet]
    @Query private var settingsItems: [AppSettings]
    @Query(sort: \Estimated1RM.timestamp, order: .reverse) private var allEstimated1RMs: [Estimated1RM]

    @ObservedObject var selectedSetData: SelectedSetData

    @State private var selectedExerciseId: UUID?
    @State private var showingAddExercise = false

    @State private var reps: Int = 8
    @State private var weight: Double = 20.0
    @State private var rir: Int = 3

    @State private var newExerciseName: String = ""
    @State private var newExerciseLoadType: ExerciseLoadType = .twoSided

    @State private var showSubmitOverlay = false
    @State private var overlayDidIncrease = false
    @State private var overlayDelta: Double = 0
    @State private var overlayNew1RM: Double = 0

    @State private var showInfoPopup = false
    @State private var showWeightPicker = false
    @State private var selectedIncrementIndex: Int = 0
    @State private var showExerciseDetails = false
    @State private var editingExerciseName = ""
    @State private var editingExerciseLoadType: ExerciseLoadType = .twoSided
    @State private var showLogConfirmation = false
    @State private var showCancelOverlay = false
    @State private var lastHapticReps: Int?
    @State private var lastHapticRIR: Int?

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
        let rir: Int
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
            if wasPR {
                currentMax = estimated
            }
            result.append(SetWithPR(set: set, estimated1RM: estimated, wasPR: wasPR, rir: set.rir))
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

    private var currentExerciseIncrement: Double {
        guard let ex = selectedExercise else { return settings.twoSidedIncrement }
        return ex.exerciseLoadType == .twoSided ? settings.twoSidedIncrement : settings.oneSidedIncrement
    }

    private var availableIncrements: [Double] {
        let increments = settings.availableIncrements.isEmpty ? [2.5, 5.0] : settings.availableIncrements
        return increments.sorted()
    }

    private var smallestIncrement: Double {
        availableIncrements.first ?? 2.5
    }

    private var currentIncrement: Double {
        guard selectedIncrementIndex >= 0 && selectedIncrementIndex < availableIncrements.count else {
            return currentExerciseIncrement
        }
        return availableIncrements[selectedIncrementIndex]
    }

    private var suggestions: [OneRMCalculator.Suggestion] {
        OneRMCalculator.minimizedSuggestions(current1RM: current1RM, increment: currentIncrement)
    }

    private var topThreeSuggestions: [OneRMCalculator.Suggestion] {
        suggestions
            .filter { $0.reps >= 5 && $0.reps <= 10 }
            .sorted { $0.projected1RM < $1.projected1RM }
            .prefix(3)
            .map { $0 }
    }

    private var weightOptions: [Double] {
        let increment = smallestIncrement
        var options: [Double] = []
        var value: Double = 0
        while value <= 500 {
            options.append(value)
            value += increment
        }
        return options
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 12) {
                    // Styled Exercise Selector
                    styledExerciseSelector
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    // Estimated 1RM Graph
                    estimated1RMGraphWidget
                        .padding(.horizontal, 12)

                    // Progress Options
                    optionsSection
                        .padding(.horizontal, 12)

                    // Log Set Section
                    logSetSection

                    Spacer(minLength: 0)
                }
                .onAppear {
                    seedIfNeeded()
                    if selectedExerciseId == nil {
                        selectedExerciseId = exercises.first?.id
                        resetToDefaults()
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
                        .presentationDetents([.height(300)])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showExerciseDetails) {
                    exerciseDetailsSheet
                        .presentationDetents([.height(selectedExercise?.isCustom == true ? 420 : 340)])
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
                        rir: rir,
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
                .foregroundStyle(.cyan)

                Spacer()

                Text("Add Exercise")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button("Add") {
                    addExercise()
                }
                .foregroundStyle(.cyan)
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
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    showWeightPicker = false
                }
                .foregroundStyle(.cyan)

                Spacer()

                Text("Select Weight")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button("Done") {
                    showWeightPicker = false
                }
                .foregroundStyle(.cyan)
            }
            .padding()

            Picker("Weight", selection: $weight) {
                ForEach(weightOptions, id: \.self) { w in
                    Text(w.rounded1().formatted(.number.precision(.fractionLength(2))) + " lbs")
                        .tag(w)
                }
            }
            .pickerStyle(.wheel)
        }
        .background(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var exerciseDetailsSheet: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Button("Cancel") {
                    showExerciseDetails = false
                }
                .foregroundStyle(.cyan)

                Spacer()

                Text("Exercise Details")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button("Save") {
                    saveExerciseDetails()
                }
                .foregroundStyle(.cyan)
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
        Menu {
            ForEach(exercises) { ex in
                Button {
                    selectedExerciseId = ex.id
                } label: {
                    if selectedExerciseId == ex.id {
                        Label(ex.name, systemImage: "checkmark")
                    } else {
                        Text(ex.name)
                    }
                }
            }

            Divider()

            if selectedExercise != nil {
                Button {
                    if let ex = selectedExercise {
                        editingExerciseName = ex.name
                        editingExerciseLoadType = ex.exerciseLoadType
                        showExerciseDetails = true
                    }
                } label: {
                    Label("Edit Exercise…", systemImage: "pencil")
                }

                Divider()
            }

            Button {
                newExerciseName = ""
                showingAddExercise = true
            } label: {
                Label("Add Exercise…", systemImage: "plus")
            }
        } label: {
            HStack {
                Spacer()
                Text(selectedExercise?.name ?? "Select Exercise")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.subheadline)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
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
    }

    private var graphHeaderView: some View {
        HStack {
            Text("Current Estimated 1RM")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Text(current1RM > 0 ? current1RM.rounded1().formatted(.number.precision(.fractionLength(2))) : "--")
                .font(.title2.weight(.bold))
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
                        (60, [Color(red: 0.3, green: 0.8, blue: 0.3), Color(red: 0.2, green: 0.6, blue: 0.2)]), // Green (RIR 5+)
                        (75, [Color(red: 0.3, green: 0.8, blue: 0.3), Color(red: 0.2, green: 0.6, blue: 0.2)]), // Green
                        (85, [Color(red: 1.0, green: 0.9, blue: 0.2), Color(red: 0.9, green: 0.7, blue: 0.0)]), // Yellow (RIR 4)
                        (95, [Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 1.0, green: 0.4, blue: 0.0)]), // Orange (RIR 2-3)
                        (110, [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.0)]), // Gold (PR)
                        (100, [Color(red: 0.9, green: 0.2, blue: 0.2), Color(red: 0.7, green: 0.1, blue: 0.1)]), // Red (RIR 0-1)
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
                .frame(height: 140)
                .opacity(0.4)

                // Overlay text
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.cyan.opacity(0.3))

                    Text("No History Yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Your set history will appear here")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
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
            .frame(width: totalChartWidth, height: 140)
        }

        private func colorForRIR(_ rir: Int, isPR: Bool) -> [Color] {
            // If it's a PR, use gold gradient regardless of RIR
            if isPR {
                return [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.0)]
            }

            // Otherwise, color by RIR (difficulty)
            switch rir {
            case 0...1:
                // Very hard sets - Deep red to red
                return [Color(red: 0.9, green: 0.2, blue: 0.2), Color(red: 0.7, green: 0.1, blue: 0.1)]
            case 2...3:
                // Hard sets - Orange to amber
                return [Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 1.0, green: 0.4, blue: 0.0)]
            case 4:
                // Moderate sets - Yellow to gold
                return [Color(red: 1.0, green: 0.9, blue: 0.2), Color(red: 0.9, green: 0.7, blue: 0.0)]
            default:
                // Easy sets (5+) - Green shades
                return [Color(red: 0.3, green: 0.8, blue: 0.3), Color(red: 0.2, green: 0.6, blue: 0.2)]
            }
        }

        private func barMark(index: Int, setInfo: SetWithPR, isSelected: Bool) -> some ChartContent {
            let colors: [Color]

            if isSelected {
                // Bright white gradient for selected bar
                colors = [.white, Color(white: 0.9)]
            } else {
                colors = colorForRIR(setInfo.rir, isPR: setInfo.wasPR)
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
            .frame(width: 50, height: 140)
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
                Text("RIR: \(setInfo.rir >= 5 ? "5+" : "\(setInfo.rir)")")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Text("Est. 1RM: \(setInfo.estimated1RM.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan)
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

    private var estimated1RMGraphWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            graphHeaderView
            graphContentView
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

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Progress Options")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()

                // Increment adjustment buttons - compartmentalized
                HStack(spacing: 0) {
                    Button {
                        if selectedIncrementIndex > 0 {
                            selectedIncrementIndex -= 1
                            hapticFeedback.impactOccurred()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(selectedIncrementIndex > 0 ? .cyan : .gray)
                            Spacer()
                        }
                        .frame(width: 35, height: 32)
                        .contentShape(Rectangle())
                    }
                    .disabled(selectedIncrementIndex <= 0)

                    Text(currentIncrement.formatted(.number.precision(.fractionLength(2))))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36)

                    Button {
                        if selectedIncrementIndex < availableIncrements.count - 1 {
                            selectedIncrementIndex += 1
                            hapticFeedback.impactOccurred()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "chevron.up")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(selectedIncrementIndex < availableIncrements.count - 1 ? .cyan : .gray)
                            Spacer()
                        }
                        .frame(width: 35, height: 32)
                        .contentShape(Rectangle())
                    }
                    .disabled(selectedIncrementIndex >= availableIncrements.count - 1)
                }
                .frame(maxWidth: 106)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(white: 0.12))
                .cornerRadius(8)

                // Button {
                //     showInfoPopup = true
                // } label: {
                //     Image(systemName: "info.circle")
                //         .foregroundStyle(.cyan)
                // }
            }

            if current1RM < 0.1 {
                // No data state
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 32))
                        .foregroundStyle(.cyan.opacity(0.4))
                    Text("No Sets Yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Complete a set to see progression suggestions")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.05), Color(white: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 0) {
                    optionsHeaderRow
                    Divider()
                        .background(.white.opacity(0.2))
                    LazyVStack(spacing: 0) {
                        ForEach(topThreeSuggestions) { s in
                            OptionRow(s: s)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    hapticFeedback.impactOccurred()
                                    selectOption(s)
                                }
                            if s.id != topThreeSuggestions.last?.id {
                                Divider()
                                    .background(.white.opacity(0.2))
                            }
                        }
                    }
                }
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .alert("Progress Options", isPresented: $showInfoPopup) {
            Button("OK") { showInfoPopup = false }
        } message: {
            Text("This section shows the 3 most conservative progression options (5-10 reps, 0-1 RIR) ranked by smallest projected 1RM increase.\n\nCurrent Estimated 1RM is calculated using the Epley formula from your best previous set with 0-1 RIR:\n\n1RM = weight × (1 + reps/30)")
        }
    }

    private var optionsHeaderRow: some View {
        HStack(spacing: 10) {
            Text("Weight")
                .frame(width: 60, alignment: .center)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan.opacity(0.8))

            Text("Reps")
                .frame(width: 60, alignment: .center)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan.opacity(0.8))

            HStack(spacing: 4) {
                Text("Projected 1RM (Δ)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Image(systemName: "arrow.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.cyan.opacity(0.08), Color.cyan.opacity(0.04)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private var logSetSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Weight with increment/decrement
                VStack(spacing: 6) {
                    Text("Weight")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack(spacing: 8) {
                        Button {
                            weight = max(0, weight - smallestIncrement)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.cyan)
                        }

                        Button {
                            showWeightPicker = true
                        } label: {
                            VStack(spacing: 2) {
                                Text(weight.rounded1().formatted(.number.precision(.fractionLength(2))))
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white)
                                Text("lbs")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .frame(width: 75)
                        }
                        .buttonStyle(.plain)

                        Button {
                            weight = min(2000, weight + smallestIncrement)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.cyan)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.12))
                    .cornerRadius(12)
                }

                Divider()
                    .frame(height: 60)
                    .background(.white.opacity(0.2))

                // Reps and RIR with better labels
                VStack(spacing: 8) {
                    VStack(spacing: 4) {
                        Text("Reps")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .center)

                        HStack(spacing: 8) {
                            Slider(value: Binding(
                                get: { Double(reps) },
                                set: { newValue in
                                    let newReps = Int(newValue.rounded())
                                    if newReps != reps {
                                        if lastHapticReps != newReps {
                                            hapticFeedback.impactOccurred()
                                            lastHapticReps = newReps
                                        }
                                        reps = newReps
                                    }
                                }
                            ), in: 1...20, step: 1)
                            .tint(.cyan)
                            .accentColor(.cyan)

                            Text("\(reps)")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 24)
                        }
                    }

                    VStack(spacing: 4) {
                        Text("RIR")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .center)

                        HStack(spacing: 8) {
                            Slider(value: Binding(
                                get: { Double(rir) },
                                set: { newValue in
                                    let newRIR = Int(newValue.rounded())
                                    if newRIR != rir {
                                        if lastHapticRIR != newRIR {
                                            hapticFeedback.impactOccurred()
                                            lastHapticRIR = newRIR
                                        }
                                        rir = newRIR
                                    }
                                }
                            ), in: 0...5, step: 1)
                            .tint(.cyan)
                            .accentColor(.cyan)

                            Text(rir >= 5 ? "5+" : "\(rir)")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 24)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Submit button below
            Button {
                hapticFeedback.impactOccurred()
                showLogConfirmation = true
            } label: {
                Text("Log Set")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(.cyan)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
        .padding(.horizontal, 12)
    }

    private struct OptionRow: View {
        let s: OneRMCalculator.Suggestion

        var body: some View {
            HStack(spacing: 10) {
                Text(s.weight.rounded1().formatted(.number.precision(.fractionLength(2))))
                    .frame(width: 60, alignment: .center)
                    .foregroundStyle(.white)

                Text("\(s.reps)")
                    .frame(width: 60, alignment: .center)
                    .foregroundStyle(.white)

                let proj = s.projected1RM.rounded1()
                let delta = s.delta.rounded1()

                HStack(spacing: 4) {
                    Text(proj.formatted(.number.precision(.fractionLength(2))))
                        .foregroundStyle(.white)

                    Text("(\(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(2)))))")
                        .foregroundStyle(delta > 0 ? .green : .white.opacity(0.7))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .font(.body)
        }
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
        let rir: Int
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
                                .foregroundStyle(.cyan)

                            Text("\(reps) reps × \(weight.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs")
                                .font(.body)
                                .foregroundStyle(.white)

                            Text("RIR: \(rir >= 5 ? "5+" : "\(rir)")")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.7))
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
        rir = 3
        if current1RM < 0.1 {
            weight = 20.0
        } else {
            weight = (current1RM * 0.8).rounded()
        }

        // Reset increment to exercise default
        if let index = availableIncrements.firstIndex(of: currentExerciseIncrement) {
            selectedIncrementIndex = index
        } else if let closestIndex = availableIncrements.enumerated().min(by: { abs($0.element - currentExerciseIncrement) < abs($1.element - currentExerciseIncrement) })?.offset {
            selectedIncrementIndex = closestIndex
        }
    }

    private func populateFromSelectedSet() {
        if let exerciseId = selectedSetData.exerciseId {
            selectedExerciseId = exerciseId
        }
        if let repsValue = selectedSetData.reps {
            reps = repsValue
        }
        if let weightValue = selectedSetData.weight {
            weight = weightValue
        }
        if let rirValue = selectedSetData.rir {
            rir = rirValue
        }
    }

    private func selectOption(_ suggestion: OneRMCalculator.Suggestion) {
        reps = suggestion.reps
        weight = suggestion.weight
        rir = 1
    }

    private func logSet() {
        guard let ex = selectedExercise else { return }

        let before = current1RM

        // Convert 0.0 weight to 1.0 behind the scenes
        let actualWeight = weight == 0.0 ? 1.0 : weight
        let set = LiftSet(exercise: ex, reps: reps, weight: actualWeight, rir: rir)
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
