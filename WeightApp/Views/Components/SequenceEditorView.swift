import SwiftUI
import SwiftData

struct SequenceEditorView: View {
    let exercises: [Exercises]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<WorkoutSequence> { !$0.deleted })
    private var sequences: [WorkoutSequence]

    @State private var activeId: UUID?
    @State private var showNewSequenceAlert = false
    @State private var newSequenceName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if sequences.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "list.number")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("No sequences yet")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                        Button("Create Sequence") {
                            showNewSequenceAlert = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                    }
                } else {
                    List {
                        ForEach(sequences) { seq in
                            NavigationLink(value: seq.id) {
                                HStack {
                                    Button {
                                        activeId = seq.id
                                        WorkoutSequenceStore.setActiveSequenceId(seq.id)
                                    } label: {
                                        Image(systemName: activeId == seq.id ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 20))
                                            .foregroundStyle(activeId == seq.id ? Color.appAccent : .white.opacity(0.3))
                                    }
                                    .buttonStyle(.plain)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(seq.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.white)
                                        Text("\(seq.exerciseIds.count) exercises")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.5))
                                    }

                                    Spacer()
                                }
                            }
                            .listRowBackground(Color(white: 0.12))
                            .listRowSeparatorTint(.white.opacity(0.08))
                        }
                        .onDelete(perform: deleteSequences)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Sequences")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { sequenceId in
                if let seq = sequences.first(where: { $0.id == sequenceId }) {
                    SequenceDetailView(
                        sequence: seq,
                        exercises: exercises
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.appAccent)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newSequenceName = ""
                        showNewSequenceAlert = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("New Sequence", isPresented: $showNewSequenceAlert) {
                TextField("Name", text: $newSequenceName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    guard !newSequenceName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let seq = WorkoutSequence(
                        name: newSequenceName.trimmingCharacters(in: .whitespaces)
                    )
                    modelContext.insert(seq)
                    try? modelContext.save()
                    if sequences.count == 0 {
                        // Will be 1 after insert, set as active
                        activeId = seq.id
                        WorkoutSequenceStore.setActiveSequenceId(seq.id)
                    }
                    Task { await SyncService.shared.syncSequence(seq) }
                }
            } message: {
                Text("Enter a name for this sequence")
            }
        }
        .onAppear {
            activeId = WorkoutSequenceStore.activeSequenceId() ?? sequences.first?.id
        }
    }

    private func deleteSequences(at offsets: IndexSet) {
        for index in offsets {
            let seq = sequences[index]
            seq.deleted = true
            try? modelContext.save()
            Task { await SyncService.shared.deleteSequence(seq.id) }
        }
        activeId = WorkoutSequenceStore.activeSequenceId() ?? sequences.first?.id
    }
}

// MARK: - Sequence Detail View

struct SequenceDetailView: View {
    @Bindable var sequence: WorkoutSequence
    let exercises: [Exercises]
    @Environment(\.modelContext) private var modelContext

    @State private var showAddExercise = false
    @State private var showRenameAlert = false
    @State private var renameName = ""
    @Environment(\.editMode) private var editMode

    private var orderedExercises: [Exercises] {
        let exerciseMap = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        return sequence.exerciseIds.compactMap { exerciseMap[$0] }
    }

    private var unsequencedExercises: [Exercises] {
        let sequencedIds = Set(sequence.exerciseIds)
        return exercises
            .filter { !sequencedIds.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if orderedExercises.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No exercises in this sequence")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                    Button("Add All Exercises") {
                        sequence.exerciseIds = exercises
                            .sorted { $0.createdAt < $1.createdAt }
                            .map { $0.id }
                        saveAndSync()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appAccent)
                }
            } else {
                List {
                    if editMode?.wrappedValue.isEditing == true {
                        Text("Drag to reorder exercises")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.clear)
                    }

                    ForEach(orderedExercises) { exercise in
                        HStack(spacing: 12) {
                            ExerciseIconView(exercise: exercise, size: 32)
                                .foregroundStyle(Color.appAccent)

                            Text(exercise.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)

                            Spacer()

                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .listRowBackground(Color(white: 0.12))
                        .listRowSeparatorTint(.white.opacity(0.08))
                    }
                    .onDelete(perform: removeExercises)
                    .onMove(perform: moveExercises)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(sequence.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        renameName = sequence.name
                        showRenameAlert = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.appAccent)
                    }

                    if !unsequencedExercises.isEmpty {
                        Button {
                            showAddExercise = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.appAccent)
                        }
                    }

                    EditButton()
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showAddExercise) {
            addExerciseSheet
        }
        .alert("Rename Sequence", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                let trimmed = renameName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                sequence.name = trimmed
                saveAndSync()
            }
        }
    }

    private var addExerciseSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    ForEach(unsequencedExercises) { exercise in
                        Button {
                            sequence.exerciseIds.append(exercise.id)
                            saveAndSync()
                            if unsequencedExercises.isEmpty {
                                showAddExercise = false
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ExerciseIconView(exercise: exercise, size: 32)
                                    .foregroundStyle(Color.appAccent)

                                Text(exercise.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)

                                Spacer()

                                Image(systemName: "plus.circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                        .listRowBackground(Color(white: 0.12))
                        .listRowSeparatorTint(.white.opacity(0.08))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showAddExercise = false
                    }
                    .foregroundStyle(Color.appAccent)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func removeExercises(at offsets: IndexSet) {
        sequence.exerciseIds.remove(atOffsets: offsets)
        saveAndSync()
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        sequence.exerciseIds.move(fromOffsets: source, toOffset: destination)
        saveAndSync()
    }

    private func saveAndSync() {
        try? modelContext.save()
        Task { await SyncService.shared.syncSequence(sequence) }
    }
}
