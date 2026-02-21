//
//  HistoryView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var selectedSetData: SelectedSetData
    @Binding var selectedTab: Int
    var isVisible: Bool = true
    @State private var isDeleteModeActive = false
    @State private var setToDelete: LiftSets? = nil
    @State private var showDeleteConfirmation = false

    @State private var displayMonths: Int = 2
    @State private var sets: [LiftSets] = []
    @State private var estimated1RMs: [Estimated1RMs] = []
    @State private var hasMoreHistory = true
    @State private var groupedSets: [(date: Date, exerciseGroups: [ExerciseGroup])] = []
    @State private var effortCache: [UUID: EffortResult] = [:]

    struct ExerciseGroup: Identifiable {
        let id = UUID()
        let exerciseName: String
        let sets: [LiftSets]
    }

    struct EffortResult {
        let percent1RM: Double?
        let isPR: Bool
    }

    var body: some View {
        Group {
            if sets.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.appAccent.opacity(0.6))

                    Text("No History Yet")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Your training history will appear here as you log sets")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                List {
                    ForEach(groupedSets, id: \.date) { group in
                        Section {
                            ForEach(group.exerciseGroups) { exerciseGroup in
                                ExerciseGroupRow(
                                    exerciseGroup: exerciseGroup,
                                    isDeleteModeActive: isDeleteModeActive,
                                    onDelete: { set in
                                        setToDelete = set
                                        showDeleteConfirmation = true
                                    },
                                    onSelect: { set in
                                        selectedSetData.exerciseId = set.exercise?.id
                                        selectedSetData.reps = set.reps
                                        selectedSetData.weight = set.weight
                                        selectedSetData.shouldPopulate = true
                                        selectedTab = 1
                                    },
                                    effortCache: effortCache
                                )
                            }
                        } header: {
                            Text(formatDateHeader(group.date))
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    }

                    if hasMoreHistory {
                        Button {
                            displayMonths += 2
                            loadData()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Load Earlier History")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.appAccent)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color(white: 0.12))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
        }
        .toolbar {
            if isVisible && !sets.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isDeleteModeActive.toggle()
                    } label: {
                        Image(systemName: isDeleteModeActive ? "minus.circle.fill" : "minus.circle")
                            .foregroundStyle(isDeleteModeActive ? .red : Color.appAccent)
                    }
                }
            }
        }
        .alert("Delete Set", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let set = setToDelete {
                    let setId = set.id
                    set.deleted = true

                    // Also mark the associated Estimated1RMs as deleted
                    var estimated1RMId: UUID? = nil
                    if let associated1RM = estimated1RMs.first(where: { $0.setId == setId }) {
                        associated1RM.deleted = true
                        estimated1RMId = associated1RM.id
                    }

                    try? modelContext.save()

                    // Remove from local arrays and rebuild derived data
                    sets.removeAll { $0.id == setId }
                    estimated1RMs.removeAll { $0.setId == setId }
                    effortCache = Self.buildEffortCache(sets: sets, estimated1RMs: estimated1RMs)
                    groupedSets = Self.buildGroupedSets(from: sets)

                    Task {
                        await SyncService.shared.deleteLiftSet(setId)
                        if let e1rmId = estimated1RMId {
                            await SyncService.shared.deleteEstimated1RM(estimated1RMId: e1rmId, liftSetId: setId)
                        }
                    }
                }
            }
        } message: {
            if let set = setToDelete {
                Text("Delete \(set.reps) × \(set.weight.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs?")
            }
        }
        .onAppear {
            if sets.isEmpty {
                loadData()
            }
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                // Defer data reload so the subtab switch animation isn't blocked
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    loadData()
                }
            }
        }
    }

    private func loadData() {
        let cutoff = Calendar.current.date(byAdding: .month, value: -displayMonths, to: Date())!

        var setsDescriptor = FetchDescriptor<LiftSets>(
            predicate: #Predicate { !$0.deleted && $0.createdAt >= cutoff },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        setsDescriptor.fetchLimit = nil

        var e1rmDescriptor = FetchDescriptor<Estimated1RMs>(
            predicate: #Predicate { !$0.deleted && $0.createdAt >= cutoff }
        )
        e1rmDescriptor.fetchLimit = nil

        let fetchedSets = (try? modelContext.fetch(setsDescriptor)) ?? []
        let fetchedE1RMs = (try? modelContext.fetch(e1rmDescriptor)) ?? []

        sets = fetchedSets
        estimated1RMs = fetchedE1RMs

        // Precompute derived data so body evaluations are cheap
        effortCache = Self.buildEffortCache(sets: fetchedSets, estimated1RMs: fetchedE1RMs)
        groupedSets = Self.buildGroupedSets(from: fetchedSets)

        // Check if there's older data beyond the current window
        let olderCutoff = Calendar.current.date(byAdding: .month, value: -(displayMonths + 1), to: Date())!
        var olderDescriptor = FetchDescriptor<LiftSets>(
            predicate: #Predicate { !$0.deleted && $0.createdAt >= olderCutoff && $0.createdAt < cutoff }
        )
        olderDescriptor.fetchLimit = 1
        hasMoreHistory = ((try? modelContext.fetch(olderDescriptor)) ?? []).count > 0
    }

    private static func buildEffortCache(sets: [LiftSets], estimated1RMs: [Estimated1RMs]) -> [UUID: EffortResult] {
        let e1rmBySetId = Dictionary(uniqueKeysWithValues: estimated1RMs.compactMap { e1rm -> (UUID, Double)? in
            return (e1rm.setId, e1rm.value)
        })

        let byExercise = Dictionary(grouping: sets) { $0.exercise?.id }
        var cache: [UUID: EffortResult] = [:]

        for (_, exerciseSets) in byExercise {
            let sorted = exerciseSets.sorted { $0.createdAt < $1.createdAt }
            var runningMax: Double = 0

            for set in sorted {
                if set.isBaselineSet {
                    cache[set.id] = EffortResult(percent1RM: nil, isPR: false)
                    let baselineEstimate = e1rmBySetId[set.id]
                        ?? OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)
                    runningMax = max(runningMax, baselineEstimate)
                } else {
                    let estimated = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)
                    let isPR = estimated > runningMax
                    let percent1RM: Double? = runningMax > 0 ? estimated / runningMax : nil
                    cache[set.id] = EffortResult(percent1RM: percent1RM, isPR: isPR)
                    runningMax = max(runningMax, estimated)
                }
            }
        }

        return cache
    }

    private static func buildGroupedSets(from sets: [LiftSets]) -> [(date: Date, exerciseGroups: [ExerciseGroup])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sets) { set in
            calendar.startOfDay(for: set.createdAt)
        }

        return grouped.sorted { $0.key > $1.key }.map { dateKey, sets in
            let sortedSets = sets.sorted { $0.createdAt < $1.createdAt }
            var exerciseGroups: [ExerciseGroup] = []
            var currentExerciseName: String? = nil
            var currentSets: [LiftSets] = []

            for set in sortedSets {
                let exerciseName = set.exercise?.name ?? "Unknown"
                if exerciseName == currentExerciseName {
                    currentSets.append(set)
                } else {
                    if !currentSets.isEmpty {
                        exerciseGroups.append(ExerciseGroup(exerciseName: currentExerciseName!, sets: currentSets))
                    }
                    currentExerciseName = exerciseName
                    currentSets = [set]
                }
            }

            if !currentSets.isEmpty {
                exerciseGroups.append(ExerciseGroup(exerciseName: currentExerciseName!, sets: currentSets))
            }

            return (date: dateKey, exerciseGroups: exerciseGroups)
        }
    }

    private func formatDateHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        let baseString = formatter.string(from: date)

        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let ordinalSuffix = ordinalSuffix(for: day)

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let year = yearFormatter.string(from: date)

        return "\(baseString)\(ordinalSuffix) \(year)"
    }

    private func ordinalSuffix(for day: Int) -> String {
        switch day {
        case 11, 12, 13: return "th"
        default:
            switch day % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        }
    }
}

struct ExerciseGroupRow: View {
    let exerciseGroup: HistoryView.ExerciseGroup
    let isDeleteModeActive: Bool
    let onDelete: (LiftSets) -> Void
    let onSelect: (LiftSets) -> Void
    let effortCache: [UUID: HistoryView.EffortResult]

    private func colorForEffort(percent1RM: Double?, isPR: Bool, set: LiftSets) -> Color {
        if isPR {
            return .setPR
        }

        // Baseline sets → white
        if set.isBaselineSet {
            return .white
        }

        // For 0-weight sets, use rep-based coloring
        if set.weight == 0 {
            switch set.reps {
            case 12...: return .setNearMax
            case 9..<12: return .setHard
            case 6..<9: return .setModerate
            default: return .setEasy
            }
        }

        let bucket = TrendsCalculator.IntensityBucket.from(percent1RM: percent1RM ?? 0)
        switch bucket {
        case .pr: return .setPR
        case .redline: return .setNearMax
        case .hard: return .setHard
        case .moderate: return .setModerate
        case .easy: return .setEasy
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exerciseGroup.exerciseName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.appAccent)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(exerciseGroup.sets) { set in
                    let result = effortCache[set.id] ?? HistoryView.EffortResult(percent1RM: nil, isPR: false)
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorForEffort(percent1RM: result.percent1RM, isPR: result.isPR, set: set))
                            .frame(width: 8, height: 24)

                        Text("\(set.reps) × \(set.weight.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs")
                            .font(.callout)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer()

                        Text(formatTime(set.createdAt))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))

                        if isDeleteModeActive {
                            Button {
                                onDelete(set)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(Color(white: 0.12))
                    .cornerRadius(8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isDeleteModeActive {
                            onSelect(set)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
