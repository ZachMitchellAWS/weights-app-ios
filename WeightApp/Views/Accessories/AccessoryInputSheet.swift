//
//  AccessoryInputSheet.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/3/26.
//

import SwiftUI

struct AccessoryInputSheet: View {
    let metricType: String
    let onSave: (Double, Date) -> Void
    var weightUnit: WeightUnit = .lbs

    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @FocusState private var isFocused: Bool

    private var unitLabel: String {
        switch metricType {
        case "steps": return "steps"
        case "protein": return "g"
        case "bodyweight": return weightUnit.label
        default: return ""
        }
    }

    private var title: String {
        switch metricType {
        case "steps": return "Log Steps"
        case "protein": return "Log Protein"
        case "bodyweight": return "Log Weight"
        default: return "Log"
        }
    }

    private var isDecimal: Bool {
        metricType == "bodyweight"
    }

    private var parsedValue: Double? {
        Double(inputText)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("0", text: $inputText)
                        .keyboardType(isDecimal ? .decimalPad : .numberPad)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .focused($isFocused)

                    Text(unitLabel)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Button {
                    if let value = parsedValue, value > 0 {
                        let saveValue = metricType == "bodyweight" ? weightUnit.toLbs(value) : value
                        onSave(saveValue, selectedDate)
                        dismiss()
                    }
                } label: {
                    Text("Save")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.appAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(parsedValue == nil || parsedValue! <= 0)
                .opacity(parsedValue != nil && parsedValue! > 0 ? 1 : 0.4)

                Button {
                    showDatePicker.toggle()
                } label: {
                    if showDatePicker {
                        Text(selectedDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        Text("Now ▾")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                if showDatePicker {
                    DatePicker(
                        "Date",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                }
            }
            .padding(24)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([showDatePicker ? .large : .medium])
        .onAppear {
            isFocused = true
            selectedDate = Date()
        }
    }
}
