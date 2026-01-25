//
//  PlateSelectionView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import SwiftUI
import SwiftData

// MARK: - Plate Model

@Model
class PlateModel {
    var weight: Double
    var diameterRaw: Double
    var thicknessRaw: Double
    var colorRaw: String
    var textColorRaw: String
    var quantity: Int
    var createdAt: Date

    init(weight: Double, diameter: PlateDiameter, thickness: PlateThickness, color: PlateColor, textColor: PlateTextColor, quantity: Int) {
        self.weight = weight
        self.diameterRaw = diameter.rawValue
        self.thicknessRaw = thickness.rawValue
        self.colorRaw = color.rawValue
        self.textColorRaw = textColor.rawValue
        self.quantity = quantity
        self.createdAt = Date()
    }

    var diameter: PlateDiameter {
        get { PlateDiameter(rawValue: diameterRaw) ?? .size17_7 }
        set { diameterRaw = newValue.rawValue }
    }

    var thickness: PlateThickness {
        get { PlateThickness(rawValue: thicknessRaw) ?? .t1_75 }
        set { thicknessRaw = newValue.rawValue }
    }

    var color: PlateColor {
        get { PlateColor(rawValue: colorRaw) ?? .red }
        set { colorRaw = newValue.rawValue }
    }

    var textColor: PlateTextColor {
        get { PlateTextColor(rawValue: textColorRaw) ?? .white }
        set { textColorRaw = newValue.rawValue }
    }

    enum PlateDiameter: Double, CaseIterable, Identifiable {
        case size6 = 6.0
        case size8 = 8.0
        case size10 = 10.0
        case size12 = 12.0
        case size15 = 15.0
        case size17_7 = 17.7  // Standard 45lb plate

        var id: Double { rawValue }

        var displayName: String {
            "\(rawValue.formatted(.number.precision(.fractionLength(0...1))))\""
        }
    }

    enum PlateThickness: Double, CaseIterable, Identifiable {
        case t0_25 = 0.25
        case t0_50 = 0.50
        case t0_75 = 0.75
        case t1_00 = 1.00
        case t1_25 = 1.25
        case t1_50 = 1.50
        case t1_75 = 1.75
        case t2_00 = 2.00

        var id: Double { rawValue }

        var displayName: String {
            "\(rawValue.formatted(.number.precision(.fractionLength(2))))\""
        }
    }

    enum PlateColor: String, CaseIterable, Identifiable {
        case red = "Red"
        case blue = "Blue"
        case green = "Green"
        case yellow = "Yellow"
        case orange = "Orange"
        case purple = "Purple"
        case cyan = "Cyan"
        case gray = "Gray"
        case black = "Black"
        case darkGray = "Dark Gray"

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .red: return .red
            case .blue: return .blue
            case .green: return .green
            case .yellow: return .yellow
            case .orange: return .orange
            case .purple: return .purple
            case .cyan: return Color.appAccent
            case .gray: return .gray
            case .black: return .black
            case .darkGray: return Color(white: 0.3)
            }
        }
    }

    enum PlateTextColor: String, CaseIterable, Identifiable {
        case white = "White"
        case black = "Black"

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .white: return .white
            case .black: return .black
            }
        }
    }

    static let availableWeights: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 2.5, 5, 10, 15, 25, 35, 45, 55]

    // Default plates
    static func createDefaults(in context: ModelContext) {
        let defaults: [(weight: Double, diameter: PlateDiameter, color: PlateColor, thickness: PlateThickness)] = [
            (55, .size17_7, .red, .t2_00),
            (45, .size17_7, .blue, .t1_75),
            (35, .size17_7, .yellow, .t1_50),
            (25, .size17_7, .green, .t1_25),
            (15, .size17_7, .black, .t1_00),
            (10, .size17_7, .black, .t1_00),
            (5, .size8, .gray, .t0_50),
            (2.5, .size6, .gray, .t0_50)
        ]

        for (weight, diameter, color, thickness) in defaults {
            let plate = PlateModel(
                weight: weight,
                diameter: diameter,
                thickness: thickness,
                color: color,
                textColor: .white,
                quantity: 2
            )
            context.insert(plate)
        }
    }

    static func ensureDefaults(existingPlates: [PlateModel], in context: ModelContext) {
        let defaults: [(weight: Double, diameter: PlateDiameter, color: PlateColor, thickness: PlateThickness)] = [
            (55, .size17_7, .red, .t2_00),
            (45, .size17_7, .blue, .t1_75),
            (35, .size17_7, .yellow, .t1_50),
            (25, .size17_7, .green, .t1_25),
            (15, .size17_7, .black, .t1_00),
            (10, .size17_7, .black, .t1_00),
            (5, .size8, .gray, .t0_50),
            (2.5, .size6, .gray, .t0_50)
        ]

        let existingWeights = Set(existingPlates.map { $0.weight })

        for (weight, diameter, color, thickness) in defaults {
            if !existingWeights.contains(weight) {
                let plate = PlateModel(
                    weight: weight,
                    diameter: diameter,
                    thickness: thickness,
                    color: color,
                    textColor: .white,
                    quantity: 2
                )
                context.insert(plate)
            }
        }
    }
}

// MARK: - Plate Collection View

struct PlateSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlateModel.weight, order: .reverse) private var plates: [PlateModel]
    @State private var showEditor = false
    @State private var editingPlate: PlateModel?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        // Plus Button (Top Left)
                        Button {
                            editingPlate = nil
                            showEditor = true
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                    .foregroundStyle(Color.appAccent.opacity(0.6))

                                VStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 50))
                                        .foregroundStyle(Color.appAccent)

                                    Text("Add New")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                            .frame(height: 160)
                            .background(Color(white: 0.08))
                            .cornerRadius(12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Existing Plates
                        ForEach(plates) { plate in
                            Button {
                                editingPlate = plate
                                showEditor = true
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(white: 0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                        )

                                    VStack(spacing: 12) {
                                        PlateVisualization(
                                            weight: plate.weight,
                                            diameter: plate.diameter,
                                            thickness: plate.thickness,
                                            color: plate.color,
                                            textColor: plate.textColor
                                        )
                                        .frame(height: 90)
                                        .padding(.horizontal, 12)

                                        VStack(spacing: 4) {
                                            Text("\(plate.weight.formatted(.number.precision(.fractionLength(0...2)))) lbs")
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(.white)

                                            HStack(spacing: 4) {
                                                Text("\(plate.diameter.displayName) • \(plate.color.rawValue)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.white.opacity(0.5))

                                                Text("×\(plate.quantity)")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(Color.appAccent)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 12)
                                }
                                .frame(height: 160)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    deletePlate(plate)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Plate Selection")
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
            .fullScreenCover(isPresented: $showEditor) {
                PlateEditorView(
                    editingPlate: editingPlate,
                    existingPlates: plates,
                    onSave: { plate in
                        savePlate(plate)
                    }
                )
            }
            .onAppear {
                if plates.isEmpty {
                    PlateModel.createDefaults(in: modelContext)
                } else {
                    // Ensure any missing default plates are added
                    PlateModel.ensureDefaults(existingPlates: plates, in: modelContext)
                }
                try? modelContext.save()
            }
        }
    }

    // MARK: - Helper Functions

    private func savePlate(_ plate: PlateModel) {
        if let editingPlate = editingPlate {
            // Update existing plate properties
            editingPlate.weight = plate.weight
            editingPlate.diameter = plate.diameter
            editingPlate.thickness = plate.thickness
            editingPlate.color = plate.color
            editingPlate.textColor = plate.textColor
            editingPlate.quantity = plate.quantity
        } else {
            // Check if replacing a plate with same weight
            if let existingPlate = plates.first(where: { $0.weight == plate.weight }) {
                // Delete the old plate
                modelContext.delete(existingPlate)
            }
            // Add new plate
            modelContext.insert(plate)
        }

        try? modelContext.save()
    }

    private func deletePlate(_ plate: PlateModel) {
        modelContext.delete(plate)
        try? modelContext.save()
    }
}

// MARK: - Plate Editor View

struct PlateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let editingPlate: PlateModel?
    let onSave: (PlateModel) -> Void
    let existingPlates: [PlateModel]

    @State private var selectedWeight: Double
    @State private var selectedDiameter: PlateModel.PlateDiameter
    @State private var selectedThickness: PlateModel.PlateThickness
    @State private var selectedColor: PlateModel.PlateColor
    @State private var selectedTextColor: PlateModel.PlateTextColor
    @State private var selectedQuantity: Int
    @State private var showDuplicateAlert = false
    @State private var pendingPlate: PlateModel?

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    init(editingPlate: PlateModel?, existingPlates: [PlateModel], onSave: @escaping (PlateModel) -> Void) {
        self.editingPlate = editingPlate
        self.existingPlates = existingPlates
        self.onSave = onSave

        // Initialize state
        _selectedWeight = State(initialValue: editingPlate?.weight ?? 45)
        _selectedDiameter = State(initialValue: editingPlate?.diameter ?? .size17_7)
        _selectedThickness = State(initialValue: editingPlate?.thickness ?? .t1_75)
        _selectedColor = State(initialValue: editingPlate?.color ?? .red)
        _selectedTextColor = State(initialValue: editingPlate?.textColor ?? .white)
        _selectedQuantity = State(initialValue: editingPlate?.quantity ?? 2)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    // Plate Preview Container - Front and Side Views
                    HStack(spacing: 12) {
                        // Front View
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(white: 0.08))
                                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)

                            VStack(spacing: 4) {
                                PlateVisualization(
                                    weight: selectedWeight,
                                    diameter: selectedDiameter,
                                    thickness: selectedThickness,
                                    color: selectedColor,
                                    textColor: selectedTextColor
                                )
                                .padding(20)

                                Text("Front")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }

                        // Side View
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(white: 0.08))
                                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)

                            VStack(spacing: 4) {
                                PlateSideView(
                                    diameter: selectedDiameter,
                                    thickness: selectedThickness,
                                    color: selectedColor
                                )
                                .padding(20)

                                Text("Side")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    .frame(height: 200)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Controls
                    VStack(spacing: 12) {
                        // Weight, Text Color, and Quantity Row
                        HStack(spacing: 16) {
                            // Weight Dropdown
                            VStack(alignment: .leading, spacing: 4) {
                                Text("WEIGHT")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.5))

                                Menu {
                                    ForEach(PlateModel.availableWeights, id: \.self) { weight in
                                        Button {
                                            selectedWeight = weight
                                        } label: {
                                            HStack {
                                                Text("\(weight.formatted(.number.precision(.fractionLength(0...2)))) lbs")
                                                if selectedWeight == weight {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text("\(selectedWeight.formatted(.number.precision(.fractionLength(0...2)))) lbs")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)

                                        Spacer()

                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(width: 100)
                                    .background(Color(white: 0.15))
                                    .cornerRadius(8)
                                }
                            }

                            // Text Color Selector
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TEXT")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.5))

                                HStack(spacing: 8) {
                                    ForEach(PlateModel.PlateTextColor.allCases) { textColor in
                                        Button {
                                            selectedTextColor = textColor
                                        } label: {
                                            ZStack {
                                                // Background for visibility
                                                Circle()
                                                    .fill(textColor == .white ? Color.white : Color.black)
                                                    .frame(width: 40, height: 40)

                                                // Border
                                                Circle()
                                                    .strokeBorder(
                                                        selectedTextColor == textColor ? Color.appAccent : Color.white.opacity(0.4),
                                                        lineWidth: selectedTextColor == textColor ? 2 : 1
                                                    )
                                                    .frame(width: 40, height: 40)

                                                // Checkmark for selected
                                                if selectedTextColor == textColor {
                                                    Image(systemName: "checkmark")
                                                        .font(.caption.weight(.bold))
                                                        .foregroundStyle(textColor == .white ? Color.black : Color.white)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            // Quantity Stepper
                            VStack(alignment: .leading, spacing: 4) {
                                Text("QTY")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.5))

                                HStack(spacing: 10) {
                                    Button {
                                        if selectedQuantity > 0 {
                                            selectedQuantity -= 1
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(selectedQuantity > 0 ? Color.appAccent : Color.gray)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(selectedQuantity <= 0)

                                    Text("\(selectedQuantity)")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(minWidth: 28)

                                    Button {
                                        if selectedQuantity < 99 {
                                            selectedQuantity += 1
                                        }
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(selectedQuantity < 99 ? Color.appAccent : Color.gray)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(selectedQuantity >= 99)
                                }
                            }
                        }

                        // Diameter Slider
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("DIAMETER")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.5))
                                Spacer()
                                Text(selectedDiameter.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.appAccent)
                            }

                            HStack(spacing: 10) {
                                Image(systemName: "circle")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.4))

                                Slider(
                                    value: Binding(
                                        get: { Double(PlateModel.PlateDiameter.allCases.firstIndex(of: selectedDiameter) ?? 0) },
                                        set: { newValue in
                                            let oldIndex = PlateModel.PlateDiameter.allCases.firstIndex(of: selectedDiameter) ?? 0
                                            let newIndex = Int(newValue)
                                            if oldIndex != newIndex {
                                                hapticFeedback.impactOccurred()
                                                selectedDiameter = PlateModel.PlateDiameter.allCases[newIndex]
                                            }
                                        }
                                    ),
                                    in: 0...Double(PlateModel.PlateDiameter.allCases.count - 1),
                                    step: 1
                                )
                                .tint(Color.appAccent)

                                Image(systemName: "circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }

                        // Thickness Slider
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("THICKNESS")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.5))
                                Spacer()
                                Text(selectedThickness.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.appAccent)
                            }

                            HStack(spacing: 10) {
                                Rectangle()
                                    .frame(width: 10, height: 3)
                                    .foregroundStyle(.white.opacity(0.4))
                                    .cornerRadius(1.5)

                                Slider(
                                    value: Binding(
                                        get: { Double(PlateModel.PlateThickness.allCases.firstIndex(of: selectedThickness) ?? 0) },
                                        set: { newValue in
                                            let oldIndex = PlateModel.PlateThickness.allCases.firstIndex(of: selectedThickness) ?? 0
                                            let newIndex = Int(newValue)
                                            if oldIndex != newIndex {
                                                hapticFeedback.impactOccurred()
                                                selectedThickness = PlateModel.PlateThickness.allCases[newIndex]
                                            }
                                        }
                                    ),
                                    in: 0...Double(PlateModel.PlateThickness.allCases.count - 1),
                                    step: 1
                                )
                                .tint(Color.appAccent)

                                Rectangle()
                                    .frame(width: 18, height: 10)
                                    .foregroundStyle(.white.opacity(0.4))
                                    .cornerRadius(2)
                            }
                        }

                        // Color Selection
                        VStack(alignment: .leading, spacing: 6) {
                            Text("COLOR")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.5))

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                                ForEach(PlateModel.PlateColor.allCases) { plateColor in
                                    Button {
                                        selectedColor = plateColor
                                    } label: {
                                        Circle()
                                            .fill(plateColor.color)
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(
                                                        selectedColor == plateColor ? Color.appAccent : Color.white.opacity(0.3),
                                                        lineWidth: selectedColor == plateColor ? 3 : 1
                                                    )
                                            )
                                            .overlay(
                                                selectedColor == plateColor ?
                                                Image(systemName: "checkmark")
                                                    .font(.callout.weight(.bold))
                                                    .foregroundStyle(.white)
                                                    .shadow(color: .black.opacity(0.5), radius: 2)
                                                : nil
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 12)

                    // Save Button
                    Button {
                        handleSave()
                    } label: {
                        Text(editingPlate == nil ? "ADD PLATE" : "UPDATE PLATE")
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
            .navigationTitle(editingPlate == nil ? "New Plate" : "Edit Plate")
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
                Button("Cancel", role: .cancel) {
                    pendingPlate = nil
                }
                Button("Replace", role: .destructive) {
                    if let plate = pendingPlate {
                        onSave(plate)
                        dismiss()
                    }
                }
            } message: {
                Text("A plate with \(selectedWeight.formatted(.number.precision(.fractionLength(0...2)))) lbs already exists. Do you want to replace it?")
            }
        }
    }

    private func handleSave() {
        let plate = PlateModel(
            weight: selectedWeight,
            diameter: selectedDiameter,
            thickness: selectedThickness,
            color: selectedColor,
            textColor: selectedTextColor,
            quantity: selectedQuantity
        )

        // Check for duplicate weight (excluding current plate if editing)
        let isDuplicate = existingPlates.contains { existingPlate in
            existingPlate.weight == selectedWeight && existingPlate.id != editingPlate?.id
        }

        if isDuplicate {
            // Show alert for duplicate
            pendingPlate = plate
            showDuplicateAlert = true
        } else {
            // No duplicate, save directly
            onSave(plate)
            dismiss()
        }
    }
}

// MARK: - Plate Visualization Component

struct PlateVisualization: View {
    let weight: Double
    let diameter: PlateModel.PlateDiameter
    let thickness: PlateModel.PlateThickness
    let color: PlateModel.PlateColor
    let textColor: PlateModel.PlateTextColor

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let plateSize = size * (CGFloat(diameter.rawValue) / 20.0)
            let holeSize = plateSize * 0.18
            let thicknessEffect = CGFloat(thickness.rawValue) * 2

            ZStack {
                // Main plate body
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                color.color.opacity(0.95),
                                color.color,
                                color.color.opacity(0.75)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: plateSize / 2
                        )
                    )
                    .frame(width: plateSize, height: plateSize)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)

                // Outer ring detail
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 2)
                    .frame(width: plateSize * 0.92, height: plateSize * 0.92)

                // Inner ring detail
                Circle()
                    .stroke(Color.black.opacity(0.3), lineWidth: 3)
                    .frame(width: plateSize * 0.75, height: plateSize * 0.75)

                // Weight text - positioned above hole
                Text("\(weight.formatted(.number.precision(.fractionLength(0...2))))")
                    .font(.system(size: plateSize * 0.18, weight: .black))
                    .foregroundStyle(textColor.color)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, plateSize * 0.1)
                    .offset(y: -plateSize * 0.2)

                // LBS text - positioned below hole
                Text("LBS")
                    .font(.system(size: plateSize * 0.08, weight: .bold))
                    .foregroundStyle(textColor.color.opacity(0.9))
                    .tracking(2)
                    .offset(y: plateSize * 0.2)

                // Center hole
                Circle()
                    .fill(Color.black)
                    .frame(width: holeSize, height: holeSize)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 0)

                // 3D thickness effect
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.5),
                                Color.clear,
                                Color.black.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: thicknessEffect
                    )
                    .frame(width: plateSize, height: plateSize)

                // Shine/highlight effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.35, y: 0.35),
                            startRadius: 0,
                            endRadius: plateSize * 0.4
                        )
                    )
                    .frame(width: plateSize, height: plateSize)
                    .blendMode(.overlay)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Plate Side View Component

struct PlateSideView: View {
    let diameter: PlateModel.PlateDiameter
    let thickness: PlateModel.PlateThickness
    let color: PlateModel.PlateColor

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let plateHeight = size * (CGFloat(diameter.rawValue) / 20.0)
            let plateThickness = CGFloat(thickness.rawValue) * 15 // Scale for visibility

            ZStack {
                // Main plate rectangle (side view)
                RoundedRectangle(cornerRadius: plateThickness * 0.15)
                    .fill(
                        LinearGradient(
                            colors: [
                                color.color.opacity(0.7),
                                color.color,
                                color.color.opacity(0.8),
                                color.color.opacity(0.6)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: plateThickness, height: plateHeight)
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 2, y: 3)

                // Left edge highlight
                RoundedRectangle(cornerRadius: plateThickness * 0.15)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: plateThickness * 0.3, height: plateHeight)
                    .offset(x: -plateThickness * 0.35)
                    .blendMode(.overlay)

                // Right edge shadow
                RoundedRectangle(cornerRadius: plateThickness * 0.15)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(0.3)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: plateThickness * 0.3, height: plateHeight)
                    .offset(x: plateThickness * 0.35)

                // Top edge detail
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: plateThickness, height: 1)
                    .offset(y: -plateHeight / 2)

                // Bottom edge detail
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: plateThickness, height: 1)
                    .offset(y: plateHeight / 2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
