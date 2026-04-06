//
//  SettingsView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/26/26.
//

import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userPropertiesItems: [UserProperties]
    @Environment(\.scenePhase) private var scenePhase

    @State private var showPlateSelection = false
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var showSavedConfirmation = false
    @State private var isSaving = false

    // Draft state — initialized from userProperties in .onAppear
    @State private var draftBodyweight: Double = 180
    @State private var draftBiologicalSex: String? = nil
    @State private var draftWeightUnit: WeightUnit = .lbs
    @State private var draftMinReps: Int = 5
    @State private var draftMaxReps: Int = 12

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var hasChanges: Bool {
        let props = userProperties
        let storedBodyweight = props.bodyweight ?? (draftWeightUnit == .kg ? draftWeightUnit.toLbs(82.0) : 200.0)
        let draftBodyweightLbs = draftWeightUnit.toLbs(draftBodyweight)
        if abs(draftBodyweightLbs - storedBodyweight) > 0.01 { return true }
        if draftBiologicalSex != props.biologicalSex { return true }
        if draftWeightUnit != props.preferredWeightUnit { return true }
        if draftMinReps != props.progressMinReps { return true }
        if draftMaxReps != props.progressMaxReps { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                profileSection
                progressSection
                notificationsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .background(Color.black)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPlateSelection) {
            AvailableChangePlatesView()
        }
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await refreshNotificationStatus() } }
        }
        .onAppear {
            loadDrafts()
            Task {
                await SyncService.shared.syncUserProperties()
                loadDrafts()
            }
        }
        .overlay(alignment: .bottom) {
            if hasChanges {
                Button { save() } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Save")
                                .font(.headline)
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if showSavedConfirmation {
                SavedCheckmarkAlert()
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: hasChanges)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showSavedConfirmation)
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PROFILE")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.leading, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                // Bodyweight
                VStack(spacing: 0) {
                    Text("Bodyweight")
                        .foregroundStyle(.white)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    HStack(spacing: 0) {
                        Picker("Weight", selection: $draftBodyweight) {
                            let range = draftWeightUnit.bodyweightPickerRange
                            ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: 1.0)), id: \.self) { weight in
                                Text("\(Int(weight))").tag(weight)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 150)

                        Text(draftWeightUnit.label)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.trailing, 24)
                    }
                    .padding(.bottom, 4)
                }

                Divider().overlay(Color.white.opacity(0.1))

                // Biological Sex
                HStack {
                    Text("Biological Sex")
                        .foregroundStyle(.white)
                        .font(.subheadline)
                    Spacer()
                    Picker("Biological Sex", selection: Binding(
                        get: { draftBiologicalSex ?? "" },
                        set: { draftBiologicalSex = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().overlay(Color.white.opacity(0.1))

                // Weight Unit
                HStack {
                    Text("Weight Unit")
                        .foregroundStyle(.white)
                        .font(.subheadline)
                    Spacer()
                    Picker("Weight Unit", selection: $draftWeightUnit) {
                        ForEach(WeightUnit.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .onChange(of: draftWeightUnit) { oldUnit, newUnit in
            // Convert draft bodyweight to the new unit
            let lbs = oldUnit.toLbs(draftBodyweight)
            draftBodyweight = newUnit.fromLbs(lbs).rounded()
            // Clamp to picker range
            let range = newUnit.bodyweightPickerRange
            draftBodyweight = min(max(draftBodyweight, range.lowerBound), range.upperBound)
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PROGRESS")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.leading, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                // Change Plates row
                Button {
                    showPlateSelection = true
                } label: {
                    HStack {
                        Text("Change Plates")
                            .foregroundStyle(.white)
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.white.opacity(0.3))
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider().overlay(Color.white.opacity(0.1))

                // Rep Range
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Rep Range")
                            .foregroundStyle(.white)
                            .font(.subheadline)
                        Text("e1RM ↑")
                            .foregroundStyle(Color.setPR)
                            .font(.caption)
                        Spacer()
                        Text("\(draftMinReps)–\(draftMaxReps) reps")
                            .foregroundStyle(.white.opacity(0.5))
                            .font(.subheadline)
                    }

                    RangeSliderView(
                        minValue: Binding(
                            get: { Double(draftMinReps) },
                            set: { draftMinReps = Int($0) }
                        ),
                        maxValue: Binding(
                            get: { Double(draftMaxReps) },
                            set: { draftMaxReps = Int($0) }
                        ),
                        bounds: 1...12,
                        minSpan: Double(UserProperties.minRepRangeSpan)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOTIFICATIONS")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.leading, 16)
                .padding(.bottom, 8)

            Button {
                if let status = notificationStatus, status == .denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else if notificationStatus == .notDetermined {
                    PushNotificationService.shared.requestPermissionIfNeeded()
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        await refreshNotificationStatus()
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(Color.appAccent)
                        .font(.system(size: 20))
                    Text("Notifications")
                        .foregroundStyle(.white)
                    Spacer()
                    if let status = notificationStatus {
                        switch status {
                        case .authorized, .provisional, .ephemeral:
                            Text("Enabled")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.4))
                        case .denied:
                            Text("Open Settings")
                                .font(.subheadline)
                                .foregroundStyle(Color.appAccent)
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.appAccent)
                        case .notDetermined:
                            Text("Enable")
                                .font(.subheadline)
                                .foregroundStyle(Color.appAccent)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    // MARK: - Helpers

    private func loadDrafts() {
        let props = userProperties
        let unit = props.preferredWeightUnit
        draftWeightUnit = unit
        draftBodyweight = props.bodyweight.map { unit.fromLbs($0).rounded() } ?? (unit == .kg ? 82.0 : 180.0)
        draftBiologicalSex = props.biologicalSex
        draftMinReps = props.progressMinReps
        draftMaxReps = props.progressMaxReps
    }

    private func save() {
        isSaving = true

        let props = userProperties
        let lbsValue = draftWeightUnit.toLbs(draftBodyweight)

        let bodyweightChanged = {
            let stored = props.bodyweight ?? (draftWeightUnit == .kg ? draftWeightUnit.toLbs(82.0) : 200.0)
            return abs(lbsValue - stored) > 0.01
        }()
        let sexChanged = draftBiologicalSex != props.biologicalSex
        let unitChanged = draftWeightUnit != props.preferredWeightUnit
        let repsChanged = draftMinReps != props.progressMinReps || draftMaxReps != props.progressMaxReps

        props.bodyweight = lbsValue
        props.biologicalSex = draftBiologicalSex
        props.preferredWeightUnit = draftWeightUnit
        props.progressMinReps = draftMinReps
        props.progressMaxReps = draftMaxReps
        try? modelContext.save()

        if bodyweightChanged {
            Task { await SyncService.shared.updateBodyweight(lbsValue) }
        }
        if sexChanged {
            Task { await SyncService.shared.updateBiologicalSex(draftBiologicalSex) }
        }
        if unitChanged {
            Task { await SyncService.shared.updateWeightUnit(draftWeightUnit.rawValue) }
        }
        if repsChanged {
            Task { await SyncService.shared.updateProgressRepRange(minReps: draftMinReps, maxReps: draftMaxReps) }
        }

        // Brief loading state then show confirmation alert
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            await MainActor.run {
                isSaving = false
                withAnimation { showSavedConfirmation = true }
            }
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                withAnimation { showSavedConfirmation = false }
            }
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationStatus = settings.authorizationStatus
        }
    }
}

// MARK: - Saved Checkmark Alert

private struct SavedCheckmarkAlert: View {
    @State private var checkmarkTrimEnd: CGFloat = 0

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 64, height: 64)

                Circle()
                    .stroke(Color.green.opacity(0.3), lineWidth: 2)
                    .frame(width: 64, height: 64)

                CheckmarkShape()
                    .trim(from: 0, to: checkmarkTrimEnd)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 28, height: 28)
            }

            Text("Saved")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(28)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(0.1)) {
                checkmarkTrimEnd = 1
            }
        }
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width * 0.35, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
