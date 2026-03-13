import SwiftUI
import SwiftData

struct SplitEditorView: View {
    let exercises: [Exercise]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<WorkoutSplit> { !$0.deleted }, sort: \WorkoutSplit.createdAt)
    private var splits: [WorkoutSplit]

    @State private var activeId: UUID?
    @State private var showNewSplitAlert = false
    @State private var newSplitName = ""

    var body: some View {
        NavigationStack {
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
                        Text("Split Catalog")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        Spacer()

                        Button {
                            newSplitName = ""
                            showNewSplitAlert = true
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
                    .padding(.bottom, 16)

                    if splits.isEmpty {
                        Spacer()
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
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(splits) { split in
                                    splitCard(for: split)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 20)
                        }
                    }

                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { splitId in
                if let split = splits.first(where: { $0.id == splitId }) {
                    SplitDetailView(
                        split: split,
                        exercises: exercises
                    )
                }
            }
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
                        WorkoutSplitStore.setActiveSplitId(split.id)
                        Task { await SyncService.shared.updateActiveSplit(split.id) }
                    }
                    Task { await SyncService.shared.syncSplit(split) }
                }
            } message: {
                Text("Enter a name for this split")
            }
        }
        .onAppear {
            activeId = WorkoutSplitStore.activeSplitId()
        }
    }

    @ViewBuilder
    private func splitCard(for split: WorkoutSplit) -> some View {
        let isActive = activeId == split.id

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                // Checkmark toggle
                Button {
                    if activeId == split.id {
                        activeId = nil
                        WorkoutSplitStore.setActiveSplitId(nil)
                        Task { await SyncService.shared.updateActiveSplit(nil) }
                    } else {
                        activeId = split.id
                        WorkoutSplitStore.setActiveSplitId(split.id)
                        Task { await SyncService.shared.updateActiveSplit(split.id) }
                    }
                } label: {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isActive ? Color.appAccent : .white.opacity(0.3))
                }
                .buttonStyle(.plain)

                // Card body — navigates to detail
                NavigationLink(value: split.id) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(split.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("\(split.days.count) days")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !split.days.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(split.days.enumerated()), id: \.element.id) { index, day in
                            let color = Color.dayChipColors[index % Color.dayChipColors.count]
                            dayChip(name: day.name, count: day.exerciseIds.count, color: color)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.top, 10)
                .padding(.leading, 36) // 22pt icon + 14pt spacing
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
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isActive ? Color.appAccent : Color.white.opacity(0.2), lineWidth: isActive ? 2 : 1)
        )
        .contextMenu {
            Button(role: .destructive) {
                withAnimation {
                    deleteSplit(split)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func dayChip(name: String, count: Int, color: Color) -> some View {
        Text("\(name) (\(count))")
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    private func deleteSplit(_ split: WorkoutSplit) {
        split.deleted = true
        try? modelContext.save()
        Task { await SyncService.shared.deleteSplit(split.id) }
        activeId = WorkoutSplitStore.activeSplitId()
    }

}

// MARK: - Split Detail View

struct SplitDetailView: View {
    @Bindable var split: WorkoutSplit
    let exercises: [Exercise]
    @Environment(\.modelContext) private var modelContext

    @State private var showNewDayAlert = false
    @State private var newDayName = ""
    @State private var showRenameAlert = false
    @State private var renameName = ""
    @Environment(\.editMode) private var editMode

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: — Days Section
                HStack {
                    Text("DAYS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .kerning(1)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 6)

            if split.days.isEmpty {
                Spacer()
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
                Spacer()
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

                    ForEach(split.days) { day in
                        NavigationLink {
                            DayDetailView(
                                split: split,
                                dayId: day.id,
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

                Text("Hold and drag to reorder")
                    .font(.footnote.italic())
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }
            } // VStack
        }
        .navigationTitle(split.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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

                    Button {
                        newDayName = ""
                        showNewDayAlert = true
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
                split.days.append(WorkoutDay(name: trimmed))
                saveAndSync()
            }
        } message: {
            Text("Enter a name for this day")
        }
    }

    private func removeDays(at offsets: IndexSet) {
        split.days.remove(atOffsets: offsets)
        saveAndSync()
    }

    private func moveDays(from source: IndexSet, to destination: Int) {
        split.days.move(fromOffsets: source, toOffset: destination)
        saveAndSync()
    }

    private func saveAndSync() {
        try? modelContext.save()
        Task { await SyncService.shared.syncSplit(split) }
    }
}

// MARK: - Day Detail View

struct DayDetailView: View {
    @Bindable var split: WorkoutSplit
    let dayId: UUID
    let exercises: [Exercise]
    @Environment(\.modelContext) private var modelContext

    @State private var showAddExercise = false
    @State private var showRenameAlert = false
    @State private var renameName = ""
    @Environment(\.editMode) private var editMode

    private var dayIndex: Int? {
        split.days.firstIndex(where: { $0.id == dayId })
    }

    private var day: WorkoutDay? {
        guard let idx = dayIndex else { return nil }
        return split.days[idx]
    }

    private var orderedExercises: [Exercise] {
        guard let day else { return [] }
        let exerciseMap = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        return day.exerciseIds.compactMap { exerciseMap[$0] }
    }

    private var unsequencedExercises: [Exercise] {
        guard let day else { return exercises }
        let sequencedIds = Set(day.exerciseIds)
        return exercises
            .filter { !sequencedIds.contains($0.id) }
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

            if orderedExercises.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No exercises in this day")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                    Button("Add All Exercise") {
                        guard let idx = dayIndex else { return }
                        split.days[idx].exerciseIds = exercises
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

                Text("Hold and drag to reorder")
                    .font(.footnote.italic())
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }
        }
        .navigationTitle(day?.name ?? "Day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        renameName = day?.name ?? ""
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
        .alert("Rename Day", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                let trimmed = renameName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, let idx = dayIndex else { return }
                split.days[idx].name = trimmed
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
                            guard let idx = dayIndex else { return }
                            split.days[idx].exerciseIds.append(exercise.id)
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
        guard let idx = dayIndex else { return }
        split.days[idx].exerciseIds.remove(atOffsets: offsets)
        saveAndSync()
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        guard let idx = dayIndex else { return }
        split.days[idx].exerciseIds.move(fromOffsets: source, toOffset: destination)
        saveAndSync()
    }

    private func saveAndSync() {
        try? modelContext.save()
        Task { await SyncService.shared.syncSplit(split) }
    }
}
