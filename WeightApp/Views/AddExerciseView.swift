//
//  AddExerciseView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import SwiftUI

struct AddExerciseView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""

    let onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise Name") {
                    TextField("e.g. Romanian Deadlift", text: $name)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Add Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onCreate(trimmed)
                        dismiss()
                    }
                }
            }
        }
    }
}
