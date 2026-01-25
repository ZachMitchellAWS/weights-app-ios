//
//  TrendsView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import SwiftUI
import SwiftData

struct TrendsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LiftSet.createdAt) private var allSets: [LiftSet]
    @ObservedObject var selectedSetData: SelectedSetData
    @Binding var selectedTab: Int
    @State private var setToDelete: LiftSet? = nil
    @State private var showDeleteConfirmation = false
    @State private var isDeleteModeActive = false

    struct ExerciseGroup: Identifiable {
        let id = UUID()
        let exerciseName: String
        let sets: [LiftSet]
    }

    private var groupedSets: [(date: Date, exerciseGroups: [ExerciseGroup])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: allSets) { set in
            calendar.startOfDay(for: set.createdAt)
        }

        return grouped.sorted { $0.key > $1.key }.map { dateKey, sets in
            let sortedSets = sets.sorted { $0.createdAt < $1.createdAt }
            var exerciseGroups: [ExerciseGroup] = []
            var currentExerciseName: String? = nil
            var currentSets: [LiftSet] = []

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

    var body: some View {
        NavigationStack {
            Group {
                if allSets.isEmpty {
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
                                        allSets: allSets
                                    )
                                }
                            } header: {
                                Text(formatDateHeader(group.date))
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !allSets.isEmpty {
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
                        modelContext.delete(set)
                    }
                }
            } message: {
                if let set = setToDelete {
                    Text("Delete \(set.reps) × \(set.weight.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs?")
                }
            }
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
    let exerciseGroup: TrendsView.ExerciseGroup
    let isDeleteModeActive: Bool
    let onDelete: (LiftSet) -> Void
    let onSelect: (LiftSet) -> Void
    let allSets: [LiftSet]

    private func colorForPercentage(_ percentage: Double, isPR: Bool) -> Color {
        // If it's a PR, use gold
        if isPR {
            return Color(red: 1.0, green: 0.84, blue: 0.0)
        }

        // Otherwise, color by percentage of current 1RM (difficulty)
        switch percentage {
        case 95...:
            // 95%+ of current - Very hard sets - Red
            return Color(red: 0.9, green: 0.2, blue: 0.2)
        case 90..<95:
            // 90-95% of current - Hard sets - Orange
            return Color(red: 1.0, green: 0.6, blue: 0.2)
        case 80..<90:
            // 80-90% of current - Moderate sets - Yellow
            return Color(red: 1.0, green: 0.9, blue: 0.2)
        default:
            // < 80% of current - Easy sets - Green
            return Color(red: 0.3, green: 0.8, blue: 0.3)
        }
    }

    private func calculatePercentageAndPR(for set: LiftSet) -> (percentage: Double, isPR: Bool) {
        // Get all sets for this exercise that came before this set
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

        return (percentage: percentage, isPR: isPR)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Exercise name header
            Text(exerciseGroup.exerciseName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.appAccent)

            // Sets
            VStack(alignment: .leading, spacing: 4) {
                ForEach(exerciseGroup.sets) { set in
                    let result = calculatePercentageAndPR(for: set)
                    HStack(spacing: 12) {
                        // Color indicator
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorForPercentage(result.percentage, isPR: result.isPR))
                            .frame(width: 8, height: 24)

                        Text("\(set.reps) × \(set.weight.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer()

                        if result.isPR {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                Text("PR")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                        }

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
}
