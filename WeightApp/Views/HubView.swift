import SwiftUI
import SwiftData

enum HubSection: Int, CaseIterable {
    case splits = 0
    case exercises = 1
    case setPlans = 2

    var label: String {
        switch self {
        case .splits: return "Splits"
        case .exercises: return "Exercises"
        case .setPlans: return "Set Plans"
        }
    }
}

struct HubView: View {
    let exercises: [Exercises]
    @Binding var selectedExercisesId: UUID?
    @Binding var selectedSection: HubSection
    let deepLinkExerciseId: UUID?
    let onExerciseCreated: (_ name: String, _ loadType: ExerciseLoadType, _ movementType: ExerciseMovementType, _ icon: String) -> Void
    let onExerciseSaved: (_ exercise: Exercises, _ name: String, _ movementType: ExerciseMovementType, _ icon: String, _ notes: String?) -> Void
    let onExerciseDeleted: (_ exercise: Exercises) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control
            Picker("Section", selection: $selectedSection) {
                ForEach(HubSection.allCases, id: \.self) { section in
                    Text(section.label).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 8)
            .onChange(of: selectedSection) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            // Content
            switch selectedSection {
            case .splits:
                SplitEditorView(exercises: exercises)
            case .exercises:
                ExercisesSelectionView(
                    exercises: exercises,
                    selectedExercisesId: $selectedExercisesId,
                    initialDeepLinkExerciseId: deepLinkExerciseId,
                    onExerciseCreated: onExerciseCreated,
                    onExerciseSaved: onExerciseSaved,
                    onExerciseDeleted: onExerciseDeleted
                )
            case .setPlans:
                SetPlanCatalogView()
            }

            // Done button (all tabs)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 8)
        }
        .background(
            LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .onAppear {
            // Style the segmented control to match dark theme
            UISegmentedControl.appearance().backgroundColor = UIColor(white: 0.12, alpha: 1)
            UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Color.appAccent)
            UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.7)], for: .normal)
            UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        }
    }
}
