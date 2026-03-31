import SwiftUI
import SwiftData

struct GroupEditorView: View {
    let exercises: [Exercise]
    @Binding var activeGroupId: UUID

    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<ExerciseGroup> { !$0.deleted })
    private var allGroups: [ExerciseGroup]

    @State private var showNewGroupSheet = false
    @State private var showEditGroupSheet = false
    @State private var editingGroup: ExerciseGroup?
    @State private var showDeleteConfirmation = false
    @State private var groupToDelete: ExerciseGroup?

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    private var builtInGroups: [ExerciseGroup] {
        allGroups.filter { !$0.isCustom }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var customGroups: [ExerciseGroup] {
        allGroups.filter { $0.isCustom }.sorted { $0.sortOrder < $1.sortOrder }
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
                // Header
                HStack {
                    Text("Exercise Groups")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        showNewGroupSheet = true
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
                .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 16) {
                        // Built-in section
                        if !builtInGroups.isEmpty {
                            sectionHeader("Presets")

                            ForEach(builtInGroups, id: \.groupId) { group in
                                groupCard(group: group, isEditable: false)
                            }
                        }

                        // Custom section
                        if !customGroups.isEmpty {
                            sectionHeader("Your Groups")

                            ForEach(customGroups, id: \.groupId) { group in
                                groupCard(group: group, isEditable: true)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .padding(.top, 8)
                }
            }
        }
        .sheet(isPresented: $showNewGroupSheet) {
            GroupFormSheet(
                exercises: exercises,
                existingGroup: nil
            ) { name, selectedIds in
                createGroup(name: name, exerciseIds: selectedIds)
            }
        }
        .sheet(isPresented: $showEditGroupSheet) {
            if let group = editingGroup {
                GroupFormSheet(
                    exercises: exercises,
                    existingGroup: group
                ) { name, selectedIds in
                    updateGroup(group, name: name, exerciseIds: selectedIds)
                }
            }
        }
        .alert("Delete Group?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                groupToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let group = groupToDelete {
                    deleteGroup(group)
                }
                groupToDelete = nil
            }
        } message: {
            if let group = groupToDelete {
                Text("This will permanently delete \"\(group.name)\".")
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func groupCard(group: ExerciseGroup, isEditable: Bool) -> some View {
        let isActive = activeGroupId == group.groupId

        VStack(alignment: .leading, spacing: 10) {
            // Title row
            HStack(spacing: 12) {
                Button {
                    hapticFeedback.impactOccurred()
                    activeGroupId = group.groupId
                } label: {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isActive ? Color.appAccent : .white.opacity(0.3))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(group.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        if !group.isCustom {
                            Text("PRESET")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(4)
                        }
                    }

                    Text("\(group.exerciseIds.count) exercise\(group.exerciseIds.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                if isEditable {
                    Button {
                        hapticFeedback.impactOccurred()
                        editingGroup = group
                        showEditGroupSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        hapticFeedback.impactOccurred()
                        groupToDelete = group
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Exercise icons row
            exerciseIconsRow(for: group)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.appAccent : Color.white.opacity(0.1), lineWidth: isActive ? 2 : 1)
        )
    }

    @ViewBuilder
    private func exerciseIconsRow(for group: ExerciseGroup) -> some View {
        let groupExercises = group.exerciseIds.compactMap { id in
            exercises.first(where: { $0.id == id })
        }

        if !groupExercises.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(groupExercises, id: \.id) { exercise in
                        VStack(spacing: 4) {
                            ExerciseIconView(exercise: exercise, size: 32)
                                .foregroundStyle(.white.opacity(0.6))
                            Text(exercise.name)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(height: 24, alignment: .top)
                        }
                        .frame(width: 58)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Actions

    private func createGroup(name: String, exerciseIds: [UUID]) {
        let nextSortOrder = (allGroups.map(\.sortOrder).max() ?? 0) + 1
        let group = ExerciseGroup(
            name: name,
            exerciseIds: exerciseIds,
            sortOrder: nextSortOrder,
            isCustom: true
        )
        modelContext.insert(group)
        activeGroupId = group.groupId
        try? modelContext.save()
        Task { await SyncService.shared.syncGroup(group) }
    }

    private func updateGroup(_ group: ExerciseGroup, name: String, exerciseIds: [UUID]) {
        group.name = name
        group.exerciseIds = exerciseIds
        group.lastModifiedDatetime = Date()
        try? modelContext.save()
        Task { await SyncService.shared.syncGroup(group) }
    }

    private func deleteGroup(_ group: ExerciseGroup) {
        group.deleted = true
        if activeGroupId == group.groupId {
            activeGroupId = ExerciseGroup.tierExercisesId
        }
        try? modelContext.save()
        Task { await SyncService.shared.deleteGroup(group.groupId) }
    }
}

// MARK: - Group Form Sheet

struct GroupFormSheet: View {
    let exercises: [Exercise]
    let existingGroup: ExerciseGroup?
    let onSave: (_ name: String, _ exerciseIds: [UUID]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedExerciseIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.10).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NAME")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.5))

                            TextField("Group name", text: $name)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(Color(white: 0.16))
                                .cornerRadius(10)
                        }

                        // Exercise picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("EXERCISES (\(selectedExerciseIds.count))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.5))

                            ForEach(exercises.sorted { $0.name < $1.name }, id: \.id) { exercise in
                                exerciseRow(exercise)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(existingGroup != nil ? "Edit Group" : "New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !selectedExerciseIds.isEmpty else { return }
                        // Preserve order: existing exercises keep their order, new ones appended
                        let orderedIds: [UUID]
                        if let existing = existingGroup {
                            let kept = existing.exerciseIds.filter { selectedExerciseIds.contains($0) }
                            let added = exercises.sorted { $0.name < $1.name }
                                .map(\.id)
                                .filter { selectedExerciseIds.contains($0) && !kept.contains($0) }
                            orderedIds = kept + added
                        } else {
                            orderedIds = exercises.sorted { $0.name < $1.name }
                                .map(\.id)
                                .filter { selectedExerciseIds.contains($0) }
                        }
                        onSave(trimmed, orderedIds)
                        dismiss()
                    }
                    .foregroundStyle(Color.appAccent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedExerciseIds.isEmpty)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large])
        .onAppear {
            if let group = existingGroup {
                name = group.name
                selectedExerciseIds = Set(group.exerciseIds)
            }
        }
    }

    @ViewBuilder
    private func exerciseRow(_ exercise: Exercise) -> some View {
        let isSelected = selectedExerciseIds.contains(exercise.id)

        Button {
            if isSelected {
                selectedExerciseIds.remove(exercise.id)
            } else {
                selectedExerciseIds.insert(exercise.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.appAccent : .white.opacity(0.3))

                ExerciseIconView(exercise: exercise, size: 28)
                    .foregroundStyle(.white.opacity(0.7))

                Text(exercise.name)
                    .font(.subheadline)
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.appAccent.opacity(0.08) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
