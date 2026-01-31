//
//  PlateSelectionView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import SwiftUI
import SwiftData

// MARK: - Plate Selection View

struct PlateSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var userPropertiesItems: [UserProperties]
    @State private var showAddWeight = false
    @State private var selectedWeight: Double = 45

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var plates: [Double] {
        userProperties.availableChangePlates.filter { $0 < 5 }.sorted { $0 > $1 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    // Available Plates List
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(plates, id: \.self) { weight in
                                HStack {
                                    Text("\(weight.formatted(.number.precision(.fractionLength(0...2)))) lbs")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.white)

                                    Spacer()

                                    Button(role: .destructive) {
                                        deletePlate(weight: weight)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                            .font(.title3)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(Color(white: 0.08))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                )
                            }
                        }
                        .padding(20)
                    }

                    // Add Button
                    Button {
                        showAddWeight = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                            Text("ADD WEIGHT INCREMENT")
                                .font(.headline)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.appAccent)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Available Plate Increments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.6))
                            .font(.system(size: 28))
                    }
                }
            }
            .sheet(isPresented: $showAddWeight) {
                AddWeightView(
                    existingWeights: plates,
                    onAdd: { weight in
                        addPlate(weight: weight)
                        showAddWeight = false
                    }
                )
            }
            .onAppear {
                if userProperties.availableChangePlates.isEmpty {
                    userProperties.availableChangePlates = UserProperties.defaultAvailableChangePlates
                    try? modelContext.save()
                }
            }
        }
    }

    private func addPlate(weight: Double) {
        if !userProperties.availableChangePlates.contains(weight) {
            userProperties.availableChangePlates.append(weight)
            try? modelContext.save()

            // Sync to backend
            Task {
                await SyncService.shared.updateChangePlates(userProperties.availableChangePlates)
            }
        }
    }

    private func deletePlate(weight: Double) {
        userProperties.availableChangePlates.removeAll { $0 == weight }
        try? modelContext.save()

        // Sync to backend
        Task {
            await SyncService.shared.updateChangePlates(userProperties.availableChangePlates)
        }
    }
}

// MARK: - Add Weight View

struct AddWeightView: View {
    @Environment(\.dismiss) private var dismiss
    let existingWeights: [Double]
    let onAdd: (Double) -> Void

    @State private var selectedWeight: Double = 45
    @State private var showDuplicateAlert = false

    let availableWeights: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 2.5]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("Select Weight")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.top, 20)

                    // Weight Picker
                    Picker("Weight", selection: $selectedWeight) {
                        ForEach(availableWeights, id: \.self) { weight in
                            Text("\(weight.formatted(.number.precision(.fractionLength(0...2)))) lbs")
                                .tag(weight)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 200)

                    Spacer()

                    // Add Button
                    Button {
                        if existingWeights.contains(selectedWeight) {
                            showDuplicateAlert = true
                        } else {
                            onAdd(selectedWeight)
                        }
                    } label: {
                        Text("ADD WEIGHT")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.appAccent)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Add Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.6))
                            .font(.system(size: 28))
                    }
                }
            }
            .alert("Duplicate Weight", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("\(selectedWeight.formatted(.number.precision(.fractionLength(0...2)))) lbs already exists in your plate collection.")
            }
        }
    }
}
