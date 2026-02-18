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
    let allSets: [LiftSets]
    let allEstimated1RMs: [Estimated1RMs]
    @ObservedObject var selectedSetData: SelectedSetData
    @Binding var selectedTab: Int
    @Binding var isDeleteModeActive: Bool
    @Binding var setToDelete: LiftSets?
    @Binding var showDeleteConfirmation: Bool

    struct ExerciseGroup: Identifiable {
        let id = UUID()
        let exerciseName: String
        let sets: [LiftSets]
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

    var body: some View {
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
    let allSets: [LiftSets]

    private func colorForPercentage(_ percentage: Double, isPR: Bool) -> Color {
        if isPR {
            return .setPR
        }

        let bucket = TrendsCalculator.IntensityBucket.from(percentage: percentage)
        switch bucket {
        case .redline: return .setNearMax
        case .hard: return .setHard
        case .moderate: return .setModerate
        default: return .setEasy
        }
    }

    private func calculatePercentageAndPR(for set: LiftSets) -> (percentage: Double, isPR: Bool) {
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
            Text(exerciseGroup.exerciseName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.appAccent)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(exerciseGroup.sets) { set in
                    let result = calculatePercentageAndPR(for: set)
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorForPercentage(result.percentage, isPR: result.isPR))
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
