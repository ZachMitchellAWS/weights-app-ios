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

            Menu {
                ForEach(exercises) { ex in
                    Button(ex.name) {
                        selectedExerciseId = ex.id
                    }
                }

                Divider()

                Button {
                    onAddExercise()
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
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

            Spacer()
        }
        .padding(.horizontal)
    }
}
