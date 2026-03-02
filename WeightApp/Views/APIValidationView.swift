//
//  APIValidationView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/20/26.
//

import SwiftUI

// MARK: - Test Step Model

enum TestStatus {
    case pending
    case running
    case passed
    case failed(String)
}

@Observable
class TestStep: Identifiable {
    let id: Int
    let name: String
    var status: TestStatus = .pending
    let run: () async throws -> Void

    init(id: Int, name: String, run: @escaping () async throws -> Void) {
        self.id = id
        self.name = name
        self.run = run
    }

    var statusIcon: String {
        switch status {
        case .pending: return "circle"
        case .running: return "progress.indicator"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var statusColor: Color {
        switch status {
        case .pending: return .gray
        case .running: return .blue
        case .passed: return .green
        case .failed: return .red
        }
    }

    var errorDetail: String? {
        if case .failed(let detail) = status { return detail }
        return nil
    }
}

// MARK: - API Validation View

struct APIValidationView: View {
    @State private var steps: [TestStep] = []
    @State private var isRunning = false
    @State private var shareItem: ShareItem?

    // Shared test data IDs
    private let testExerciseId = UUID()
    private let testLiftSetId = UUID()
    private let testE1RMId = UUID()
    private let testSplitId = UUID()
    private let testDayId = UUID()

    var passedCount: Int {
        steps.filter { if case .passed = $0.status { return true }; return false }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(steps) { step in
                            TestStepRow(step: step)
                        }
                    }
                    .padding()
                }

                // Bottom bar
                VStack(spacing: 12) {
                    if !steps.isEmpty {
                        Text("\(passedCount)/\(steps.count) passed")
                            .font(.headline)
                            .foregroundStyle(passedCount == steps.count ? .green : .primary)
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await runAllTests() }
                        } label: {
                            HStack {
                                if isRunning {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isRunning ? "Running..." : "Run All Tests")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning)

                        Button {
                            exportReport()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(steps.isEmpty || isRunning)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("API Validation")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $shareItem) { item in
                ShareSheet(activityItems: [item.url])
            }
            .onAppear { buildSteps() }
        }
    }

    // MARK: - Build Test Steps

    private func buildSteps() {
        let api = APIService.shared
        var capturedUserProps: UserPropertiesResponse?
        var capturedExerciseCount: Int = 0

        let exerciseId = testExerciseId
        let liftSetId = testLiftSetId
        let e1rmId = testE1RMId
        let splitId = testSplitId
        let dayId = testDayId

        steps = [
            // 1
            TestStep(id: 1, name: "GET User Properties") {
                let response = try await api.getUserProperties()
                guard !response.userId.isEmpty else { throw ValidationError("userId is empty") }
                capturedUserProps = response
            },
            // 2
            TestStep(id: 2, name: "POST User Properties (set bodyweight)") {
                let request = UserPropertiesRequest(bodyweight: 185.0)
                let response = try await api.updateUserProperties(request)
                guard response.bodyweight == 185.0 else { throw ValidationError("bodyweight expected 185.0, got \(String(describing: response.bodyweight))") }
            },
            // 3
            TestStep(id: 3, name: "GET User Properties (verify bodyweight)") {
                let response = try await api.getUserProperties()
                guard response.bodyweight == 185.0 else { throw ValidationError("bodyweight expected 185.0, got \(String(describing: response.bodyweight))") }
            },
            // 4
            TestStep(id: 4, name: "POST User Properties (set change plates)") {
                let plates = [2.5, 5.0, 10.0, 25.0, 45.0]
                let request = UserPropertiesRequest(availableChangePlates: plates)
                let response = try await api.updateUserProperties(request)
                guard response.availableChangePlates == plates else { throw ValidationError("plates mismatch") }
            },
            // 5
            TestStep(id: 5, name: "GET User Properties (verify plates)") {
                let response = try await api.getUserProperties()
                guard response.availableChangePlates == [2.5, 5.0, 10.0, 25.0, 45.0] else { throw ValidationError("plates mismatch") }
            },
            // 6
            TestStep(id: 6, name: "POST User Properties (set rep ranges)") {
                let request = UserPropertiesRequest(minReps: 4, maxReps: 10)
                let response = try await api.updateUserProperties(request)
                guard response.minReps == 4 && response.maxReps == 10 else { throw ValidationError("rep ranges mismatch") }
            },
            // 7
            TestStep(id: 7, name: "POST User Properties (set effort rep ranges)") {
                let request = UserPropertiesRequest(
                    easyMinReps: 8, easyMaxReps: 12,
                    moderateMinReps: 6, moderateMaxReps: 10,
                    hardMinReps: 3, hardMaxReps: 6
                )
                let response = try await api.updateUserProperties(request)
                guard response.easyMinReps == 8 && response.easyMaxReps == 12 &&
                      response.moderateMinReps == 6 && response.moderateMaxReps == 10 &&
                      response.hardMinReps == 3 && response.hardMaxReps == 6
                else { throw ValidationError("effort rep ranges mismatch") }
            },
            // 8
            TestStep(id: 8, name: "GET User Properties (verify all)") {
                let response = try await api.getUserProperties()
                guard response.bodyweight == 185.0 else { throw ValidationError("bodyweight missing") }
                guard response.availableChangePlates == [2.5, 5.0, 10.0, 25.0, 45.0] else { throw ValidationError("plates missing") }
                guard response.minReps == 4 && response.maxReps == 10 else { throw ValidationError("rep ranges missing") }
                guard response.easyMinReps == 8 && response.hardMaxReps == 6 else { throw ValidationError("effort rep ranges missing") }
            },
            // 9
            TestStep(id: 9, name: "POST User Properties (clear bodyweight)") {
                var request = UserPropertiesRequest()
                request.clearBodyweight = true
                let response = try await api.updateUserProperties(request)
                guard response.bodyweight == nil else { throw ValidationError("bodyweight should be nil") }
            },
            // 10
            TestStep(id: 10, name: "GET User Properties (verify cleared)") {
                let response = try await api.getUserProperties()
                guard response.bodyweight == nil else { throw ValidationError("bodyweight should be nil") }
                guard response.availableChangePlates == [2.5, 5.0, 10.0, 25.0, 45.0] else { throw ValidationError("plates should still be present") }
            },
            // 11
            TestStep(id: 11, name: "GET Exercise (initial)") {
                let response = try await api.getExercises()
                capturedExerciseCount = response.exercises.count
            },
            // 12
            TestStep(id: 12, name: "POST Exercise (create test)") {
                let dto = ExerciseDTO(
                    exerciseItemId: exerciseId,
                    name: "API Validation Test Exercise",
                    isCustom: true,
                    loadType: "Barbell",
                    createdTimezone: TimeZone.current.identifier,
                    notes: nil,
                    createdDatetime: Date()
                )
                let response = try await api.upsertExercises([dto])
                guard response.created == 1 else { throw ValidationError("expected created == 1, got \(response.created)") }
                guard response.exercises.contains(where: { $0.exerciseItemId == exerciseId }) else { throw ValidationError("exercise not in response") }
            },
            // 13
            TestStep(id: 13, name: "GET Exercise (verify created)") {
                let response = try await api.getExercises()
                guard response.exercises.contains(where: { $0.exerciseItemId == exerciseId }) else { throw ValidationError("test exercise not found") }
            },
            // 14
            TestStep(id: 14, name: "POST Exercise (update name)") {
                let dto = ExerciseDTO(
                    exerciseItemId: exerciseId,
                    name: "API Validation Updated Exercise",
                    isCustom: true,
                    loadType: "Barbell",
                    createdTimezone: TimeZone.current.identifier,
                    notes: nil,
                    createdDatetime: Date()
                )
                let response = try await api.upsertExercises([dto])
                guard response.updated == 1 else { throw ValidationError("expected updated == 1, got \(response.updated)") }
            },
            // 15
            TestStep(id: 15, name: "GET Exercise (verify updated)") {
                let response = try await api.getExercises()
                guard let ex = response.exercises.first(where: { $0.exerciseItemId == exerciseId }) else { throw ValidationError("exercise not found") }
                guard ex.name == "API Validation Updated Exercise" else { throw ValidationError("name not updated: \(ex.name)") }
            },
            // 16
            TestStep(id: 16, name: "POST Lift Set") {
                let dto = LiftSetDTO(
                    liftSetId: liftSetId,
                    exerciseId: exerciseId,
                    reps: 5,
                    weight: 225.0,
                    createdTimezone: TimeZone.current.identifier,
                    createdDatetime: Date()
                )
                let response = try await api.createLiftSet([dto])
                guard response.created == 1 else { throw ValidationError("expected created == 1, got \(response.created)") }
                guard response.liftSets.contains(where: { $0.liftSetId == liftSetId }) else { throw ValidationError("lift set not in response") }
            },
            // 17
            TestStep(id: 17, name: "GET Lift Sets (verify created)") {
                let response = try await api.getLiftSet()
                guard response.liftSets.contains(where: { $0.liftSetId == liftSetId }) else { throw ValidationError("test lift set not found") }
            },
            // 18
            TestStep(id: 18, name: "POST Estimated 1RM") {
                let dto = Estimated1RMDTO(
                    estimated1RMId: e1rmId,
                    liftSetId: liftSetId,
                    exerciseId: exerciseId,
                    value: 275.0,
                    createdTimezone: TimeZone.current.identifier,
                    createdDatetime: Date()
                )
                let response = try await api.createEstimated1RM([dto])
                guard response.created == 1 else { throw ValidationError("expected created == 1, got \(response.created)") }
                guard response.estimated1RMs.contains(where: { $0.liftSetId == liftSetId }) else { throw ValidationError("e1rm not in response") }
            },
            // 19
            TestStep(id: 19, name: "GET Estimated 1RMs (verify)") {
                let response = try await api.getEstimated1RM()
                guard response.estimated1RMs.contains(where: { $0.liftSetId == liftSetId }) else { throw ValidationError("test e1rm not found") }
            },
            // 20
            TestStep(id: 20, name: "DELETE Estimated 1RM") {
                let response = try await api.deleteEstimated1RM(liftSetIds: [liftSetId])
                guard response.deletedEstimated1RM.contains(where: { $0.liftSetId == liftSetId }) else { throw ValidationError("deleted e1rm not in response") }
            },
            // 21
            TestStep(id: 21, name: "GET Estimated 1RMs (verify deleted)") {
                let response = try await api.getEstimated1RM()
                guard !response.estimated1RMs.contains(where: { $0.liftSetId == liftSetId }) else { throw ValidationError("test e1rm still present") }
            },
            // 22
            TestStep(id: 22, name: "DELETE Lift Set") {
                let response = try await api.deleteLiftSet([liftSetId])
                guard response.deletedLiftSet.contains(where: { $0.liftSetId == liftSetId }) else { throw ValidationError("deleted lift set not in response") }
            },
            // 23
            TestStep(id: 23, name: "GET Lift Sets (verify deleted)") {
                let response = try await api.getLiftSet()
                guard !response.liftSets.contains(where: { $0.liftSetId == liftSetId }) else { throw ValidationError("test lift set still present") }
            },
            // 24
            TestStep(id: 24, name: "POST Split (create)") {
                let dayDTO = SplitDayDTO(dayId: dayId, name: "Test Day", exerciseIds: [exerciseId])
                let dto = SplitDTO(
                    splitId: splitId,
                    name: "API Validation Test Split",
                    days: [dayDTO],
                    createdTimezone: TimeZone.current.identifier,
                    createdDatetime: Date()
                )
                let response = try await api.upsertSplits([dto])
                guard response.created == 1 else { throw ValidationError("expected created == 1, got \(String(describing: response.created))") }
            },
            // 25
            TestStep(id: 25, name: "GET Splits (verify)") {
                let response = try await api.getSplits()
                guard response.splits.contains(where: { $0.splitId == splitId }) else { throw ValidationError("test split not found") }
            },
            // 26
            TestStep(id: 26, name: "POST Split (update name)") {
                let dayDTO = SplitDayDTO(dayId: dayId, name: "Test Day", exerciseIds: [exerciseId])
                let dto = SplitDTO(
                    splitId: splitId,
                    name: "API Validation Updated Split",
                    days: [dayDTO],
                    createdTimezone: TimeZone.current.identifier,
                    createdDatetime: Date()
                )
                let response = try await api.upsertSplits([dto])
                guard response.updated == 1 else { throw ValidationError("expected updated == 1, got \(String(describing: response.updated))") }
            },
            // 27
            TestStep(id: 27, name: "GET Splits (verify update)") {
                let response = try await api.getSplits()
                guard let split = response.splits.first(where: { $0.splitId == splitId }) else { throw ValidationError("split not found") }
                guard split.name == "API Validation Updated Split" else { throw ValidationError("name not updated: \(split.name)") }
            },
            // 28
            TestStep(id: 28, name: "DELETE Split") {
                _ = try await api.deleteSplits([splitId])
            },
            // 29
            TestStep(id: 29, name: "GET Splits (verify deleted)") {
                let response = try await api.getSplits()
                guard !response.splits.contains(where: { $0.splitId == splitId }) else { throw ValidationError("test split still present") }
            },
            // 30
            TestStep(id: 30, name: "DELETE Exercise") {
                let response = try await api.deleteExercises([exerciseId])
                guard response.deletedExercises.contains(where: { $0.exerciseItemId == exerciseId }) else { throw ValidationError("deleted exercise not in response") }
            },
            // 31
            TestStep(id: 31, name: "GET Exercise (verify deleted)") {
                let response = try await api.getExercises()
                // Deleted exercises may still appear with deleted=true, or be removed entirely
                let activeExercises = response.exercises.filter { $0.deleted != true }
                guard !activeExercises.contains(where: { $0.exerciseItemId == exerciseId }) else { throw ValidationError("test exercise still active") }
            },
            // 32
            TestStep(id: 32, name: "GET Entitlement Status") {
                let response = try await EntitlementsService.shared.getStatus()
                guard !response.accountStatus.isEmpty else { throw ValidationError("accountStatus is empty") }
            },
        ]
    }

    // MARK: - Run Tests

    private func runAllTests() async {
        isRunning = true
        // Reset all steps
        for step in steps {
            step.status = .pending
        }

        for step in steps {
            step.status = .running
            do {
                try await step.run()
                step.status = .passed
            } catch {
                step.status = .failed(String(describing: error))
            }
        }
        isRunning = false
    }

    // MARK: - Export Report

    private func exportReport() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: Date())
        let environment = APIConfig.environment
        let userId = KeychainService.shared.getUserId() ?? "unknown"

        var report = """
        WeightApp API Validation Report
        ================================
        Date: \(dateString)
        Environment: \(environment)
        User ID: \(userId)

        Results: \(passedCount)/\(steps.count) passed\n\n
        """

        for step in steps {
            let statusLabel: String
            switch step.status {
            case .pending: statusLabel = "SKIP"
            case .running: statusLabel = "RUN "
            case .passed: statusLabel = "PASS"
            case .failed: statusLabel = "FAIL"
            }

            let line = String(format: "%2d. [%@] %@", step.id, statusLabel, step.name)
            report += line + "\n"

            if let error = step.errorDetail {
                report += "    Error: \(error)\n"
            }
        }

        let failedCount = steps.count - passedCount
        report += "\n================================\n"
        report += "Summary: \(passedCount)/\(steps.count) passed, \(failedCount) failed\n"

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("api-validation-report.txt")
        try? report.write(to: fileURL, atomically: true, encoding: .utf8)
        shareItem = ShareItem(url: fileURL)
    }
}

// MARK: - Test Step Row

struct TestStepRow: View {
    let step: TestStep
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("\(step.id)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)

                if case .running = step.status {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: step.statusIcon)
                        .foregroundStyle(step.statusColor)
                        .frame(width: 20, height: 20)
                }

                Text(step.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if step.errorDetail != nil {
                    withAnimation { isExpanded.toggle() }
                }
            }

            if isExpanded, let error = step.errorDetail {
                Text(error)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.leading, 54)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Share Sheet

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Validation Error

struct ValidationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
