import SwiftUI
import SwiftData

struct SplitEditorView: View {
    let exercises: [Exercises]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<WorkoutSplit> { !$0.deleted })
    private var splits: [WorkoutSplit]

    @Query(filter: #Predicate<WorkoutSequence> { !$0.deleted })
    private var allSequences: [WorkoutSequence]

    @State private var activeId: UUID?
    @State private var showNewSplitAlert = false
    @State private var newSplitName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    LinearGradient(
                        colors: [Color(white: 0.14), Color(white: 0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    if splits.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.3))
                            Text("No splits yet")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.5))
                            Button("Create Split") {
                                showNewSplitAlert = true
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appAccent)
                        }
                    } else {
                        List {
                            ForEach(splits) { split in
                                NavigationLink(value: split.id) {
                                    HStack {
                                        Button {
                                            activeId = split.id
                                            WorkoutSequenceStore.setActiveSplitId(split.id)
                                        } label: {
                                            Image(systemName: activeId == split.id ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 20))
                                                .foregroundStyle(activeId == split.id ? Color.appAccent : .white.opacity(0.3))
                                        }
                                        .buttonStyle(.plain)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(split.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.white)
                                            Text("\(split.dayIds.count) days")
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.5))
                                        }

                                        Spacer()
                                    }
                                }
                                .listRowBackground(Color(white: 0.12))
                                .listRowSeparatorTint(.white.opacity(0.08))
                            }
                            .onDelete(perform: deleteSplits)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }

                // Bottom Done button
                Button { dismiss() } label: {
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
                .background(Color(white: 0.10))
            }
            .navigationTitle("Splits")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { splitId in
                if let split = splits.first(where: { $0.id == splitId }) {
                    SplitDetailView(
                        split: split,
                        exercises: exercises
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newSplitName = ""
                        showNewSplitAlert = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("New Split", isPresented: $showNewSplitAlert) {
                TextField("Name", text: $newSplitName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    guard !newSplitName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let split = WorkoutSplit(
                        name: newSplitName.trimmingCharacters(in: .whitespaces)
                    )
                    modelContext.insert(split)
                    try? modelContext.save()
                    if splits.count == 0 {
                        activeId = split.id
                        WorkoutSequenceStore.setActiveSplitId(split.id)
                    }
                    Task { await SyncService.shared.syncSplit(split) }
                }
            } message: {
                Text("Enter a name for this split")
            }
        }
        .onAppear {
            activeId = WorkoutSequenceStore.activeSplitId() ?? splits.first?.id
        }
    }

    private func deleteSplits(at offsets: IndexSet) {
        for index in offsets {
            let split = splits[index]
            split.deleted = true
            try? modelContext.save()
            Task { await SyncService.shared.deleteSplit(split.id) }
        }
        activeId = WorkoutSequenceStore.activeSplitId() ?? splits.first?.id
    }
}

// MARK: - Split Detail View

struct SplitDetailView: View {
    @Bindable var split: WorkoutSplit
    let exercises: [Exercises]
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<WorkoutSequence> { !$0.deleted })
    private var allSequences: [WorkoutSequence]

    @State private var showAddDay = false
    @State private var showNewDayAlert = false
    @State private var newDayName = ""
    @State private var showRenameAlert = false
    @State private var renameName = ""
    @Environment(\.editMode) private var editMode

    private var orderedDays: [WorkoutSequence] {
        let seqMap = Dictionary(uniqueKeysWithValues: allSequences.map { ($0.id, $0) })
        return split.dayIds.compactMap { seqMap[$0] }
    }

    private var unassignedDays: [WorkoutSequence] {
        let assignedIds = Set(split.dayIds)
        return allSequences
            .filter { !assignedIds.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if orderedDays.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "calendar")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No days in this split")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                    Button("Create Day") {
                        showNewDayAlert = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appAccent)
                }
            } else {
                List {
                    if editMode?.wrappedValue.isEditing == true {
                        Text("Drag to reorder days")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.clear)
                    }

                    ForEach(orderedDays) { day in
                        NavigationLink {
                            SequenceDetailView(
                                sequence: day,
                                exercises: exercises
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.appAccent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(day.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white)
                                    Text("\(day.exerciseIds.count) exercises")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.5))
                                }

                                Spacer()

                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        .listRowBackground(Color(white: 0.12))
                        .listRowSeparatorTint(.white.opacity(0.08))
                    }
                    .onDelete(perform: removeDays)
                    .onMove(perform: moveDays)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(split.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        renameName = split.name
                        showRenameAlert = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.appAccent)
                    }

                    Menu {
                        Button {
                            newDayName = ""
                            showNewDayAlert = true
                        } label: {
                            Label("New Day", systemImage: "plus")
                        }

                        if !unassignedDays.isEmpty {
                            Button {
                                showAddDay = true
                            } label: {
                                Label("Add Existing Day", systemImage: "arrow.right.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.appAccent)
                    }

                    EditButton()
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showAddDay) {
            addDaySheet
        }
        .alert("Rename Split", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                let trimmed = renameName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                split.name = trimmed
                saveAndSync()
            }
        }
        .alert("New Day", isPresented: $showNewDayAlert) {
            TextField("Name", text: $newDayName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                let trimmed = newDayName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                let day = WorkoutSequence(name: trimmed)
                modelContext.insert(day)
                split.dayIds.append(day.id)
                try? modelContext.save()
                Task {
                    await SyncService.shared.syncSequence(day)
                    await SyncService.shared.syncSplit(split)
                }
            }
        } message: {
            Text("Enter a name for this day")
        }
    }

    private var addDaySheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    ForEach(unassignedDays) { day in
                        Button {
                            split.dayIds.append(day.id)
                            saveAndSync()
                            if unassignedDays.isEmpty {
                                showAddDay = false
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.appAccent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(day.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white)
                                    Text("\(day.exerciseIds.count) exercises")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.5))
                                }

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
            .navigationTitle("Add Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showAddDay = false
                    }
                    .foregroundStyle(Color.appAccent)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func removeDays(at offsets: IndexSet) {
        split.dayIds.remove(atOffsets: offsets)
        saveAndSync()
    }

    private func moveDays(from source: IndexSet, to destination: Int) {
        split.dayIds.move(fromOffsets: source, toOffset: destination)
        saveAndSync()
    }

    private func saveAndSync() {
        try? modelContext.save()
        Task { await SyncService.shared.syncSplit(split) }
    }
}
