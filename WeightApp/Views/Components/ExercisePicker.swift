//
//  ExercisePicker.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import SwiftUI

struct ExercisePicker: View {
    let exercises: [Exercises]
    @Binding var selectedExerciseId: UUID?
    let onAddExercise: () -> Void

    @State private var showExerciseSheet = false

    private var selectedName: String {
        guard let id = selectedExerciseId,
              let ex = exercises.first(where: { $0.id == id }) else {
            return exercises.first?.name ?? "Exercise"
        }
        return ex.name
    }

    var body: some View {
        HStack {
            Spacer()

            Button {
                showExerciseSheet = true
            } label: {
                Text(selectedName.lowercased())
                    .font(.system(size: 26, weight: .regular))
                    .tracking(6)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal)
        .sheet(isPresented: $showExerciseSheet) {
            ExerciseSelectionSheet(
                exercises: exercises,
                selectedExerciseId: $selectedExerciseId,
                onAddExercise: onAddExercise,
                isPresented: $showExerciseSheet
            )
        }
    }
}

// MARK: - Exercise Selection Sheet

private struct ExerciseSelectionSheet: View {
    let exercises: [Exercises]
    @Binding var selectedExerciseId: UUID?
    let onAddExercise: () -> Void
    @Binding var isPresented: Bool

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredExercises: [Exercises] {
        if searchText.isEmpty {
            return exercises.sorted { $0.name < $1.name }
        }
        return exercises
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name < $1.name }
    }

    private var groupedExercises: [(String, [Exercises])] {
        let grouped = Dictionary(grouping: filteredExercises) { exercise in
            String(exercise.name.prefix(1)).uppercased()
        }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 12) {
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    // Exercise list
                    if filteredExercises.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.3))
                            Text("No exercises found")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.5))
                            if !searchText.isEmpty {
                                Button {
                                    isPresented = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        onAddExercise()
                                    }
                                } label: {
                                    Text("Add \"\(searchText)\" as new exercise")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                            Spacer()
                        }
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                                    ForEach(groupedExercises, id: \.0) { letter, exercisesInGroup in
                                        Section {
                                            ForEach(exercisesInGroup) { exercise in
                                                ExerciseRow(
                                                    exercise: exercise,
                                                    isSelected: selectedExerciseId == exercise.id,
                                                    onSelect: {
                                                        selectedExerciseId = exercise.id
                                                        isPresented = false
                                                    }
                                                )
                                            }
                                        } header: {
                                            SectionHeader(letter: letter)
                                        }
                                    }
                                }
                                .padding(.bottom, 100)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onAddExercise()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isSearchFocused = true
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Exercise Row

private struct ExerciseRow: View {
    let exercise: Exercises
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Exercise type icon
                Image(systemName: iconForLoadType(exercise.exerciseLoadType))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.appAccent.opacity(0.8))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.body)
                        .foregroundStyle(.white)

                    Text(exercise.exerciseLoadType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.appAccent)
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.appAccent.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func iconForLoadType(_ loadType: ExerciseLoadType) -> String {
        switch loadType {
        case .barbell:
            return "figure.strengthtraining.traditional"
        case .singleLoad:
            return "dumbbell.fill"
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let letter: String

    var body: some View {
        HStack {
            Text(letter)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            Spacer()
        }
        .background(Color(white: 0.08))
    }
}
