//
//  SyncService.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/30/26.
//

import Foundation
import SwiftData
import Combine

@MainActor
class SyncService: ObservableObject {
    static let shared = SyncService()

    private var modelContext: ModelContext?
    private let retryQueue = SyncRetryQueue.shared

    // Sync state for UI indicators
    @Published var isSyncingLiftSets = false
    @Published var liftSetSyncProgress: String?
    @Published var isSyncingEstimated1RMs = false
    @Published var estimated1RMSyncProgress: String?

    private init() {}

    // MARK: - Configuration

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Initial Sync

    func performInitialSync(isNewUser: Bool) async {
        guard let context = modelContext else {
            print("SyncService: ModelContext not set")
            return
        }

        // Step 1: Sync user properties (non-blocking - failure doesn't stop exercise sync)
        await syncUserProperties()

        // Step 2: Sync exercises
        do {
            let response = try await APIService.shared.getExercises()

            if response.exercises.isEmpty {
                await createAndSyncDefaultExercises(context: context)
            } else {
                await importExercisesFromBackend(response.exercises, context: context)
            }

            await processRetryQueue()
        } catch {
            print("SyncService: Initial exercise sync failed: \(error.localizedDescription)")
        }

        // Step 3: Sync lift sets (runs after exercises so exercise references exist)
        await syncLiftSetsFromBackend()
        await processLiftSetRetryQueue()

        // Step 4: Sync estimated 1RMs (runs after lift sets so lift set references exist)
        await syncEstimated1RMsFromBackend()
        await processEstimated1RMRetryQueue()
    }

    // MARK: - User Properties Sync

    func syncUserProperties() async {
        guard let context = modelContext else { return }

        do {
            let response = try await APIService.shared.getUserProperties()

            // Update local UserProperties with backend data
            let userProperties = fetchOrCreateUserProperties(context: context)
            if let plates = response.availableChangePlates {
                userProperties.availableChangePlates = plates
            }
            if let bodyweight = response.bodyweight {
                userProperties.bodyweight = bodyweight
            }

            try? context.save()

            // Also save createdDatetime to keychain
            KeychainService.shared.saveUserProperties(createdDatetime: response.createdDatetime)
        } catch {
            print("SyncService: Failed to sync user properties: \(error.localizedDescription)")
            // Don't block exercise sync - user properties are not critical
        }
    }

    func updateChangePlates(_ plates: [Double]) async {
        do {
            _ = try await APIService.shared.updateUserProperties(availableChangePlates: plates)
            retryQueue.removePendingUserPropertiesSync()
        } catch {
            print("SyncService: Failed to update change plates: \(error.localizedDescription)")
            retryQueue.addPendingUserPropertiesSync()
        }
    }

    func processUserPropertiesRetryQueue() async {
        guard let context = modelContext else { return }
        guard retryQueue.hasUserPropertiesPending() else { return }

        let userProperties = fetchOrCreateUserProperties(context: context)

        do {
            _ = try await APIService.shared.updateUserProperties(
                availableChangePlates: userProperties.availableChangePlates
            )
            retryQueue.removePendingUserPropertiesSync()
        } catch {
            retryQueue.incrementUserPropertiesRetryCount()
        }
    }

    private func fetchOrCreateUserProperties(context: ModelContext) -> UserProperties {
        let descriptor = FetchDescriptor<UserProperties>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let props = UserProperties()
        context.insert(props)
        return props
    }

    // MARK: - Exercise CRUD Sync

    func syncExercise(_ exercise: Exercises) async {
        let dto = exercise.toDTO()

        do {
            _ = try await APIService.shared.upsertExercises([dto])
            retryQueue.removePendingOperation(exerciseId: exercise.id)
        } catch {
            print("SyncService: Failed to sync exercise \(exercise.id): \(error.localizedDescription)")
            retryQueue.addPendingUpsert(exerciseId: exercise.id)
        }
    }

    func deleteExercise(_ exerciseId: UUID) async {
        do {
            _ = try await APIService.shared.deleteExercises([exerciseId])
            retryQueue.removePendingOperation(exerciseId: exerciseId)
        } catch {
            print("SyncService: Failed to delete exercise \(exerciseId): \(error.localizedDescription)")
            retryQueue.addPendingDelete(exerciseId: exerciseId)
        }
    }

    // MARK: - Lift Set Sync

    /// Fetches all lift sets from backend using pagination and imports them locally
    func syncLiftSetsFromBackend() async {
        guard let context = modelContext else { return }

        isSyncingLiftSets = true
        liftSetSyncProgress = "Syncing..."

        var pageToken: String? = nil
        var totalFetched = 0

        do {
            repeat {
                let response = try await APIService.shared.getLiftSets(limit: 500, pageToken: pageToken)
                totalFetched += response.count

                await importLiftSetsFromBackend(response.liftSets, context: context)

                liftSetSyncProgress = "Synced \(totalFetched) sets..."
                pageToken = response.hasMore ? response.nextPageToken : nil

            } while pageToken != nil

            print("SyncService: Completed lift set sync, fetched \(totalFetched) total")
        } catch {
            print("SyncService: Failed to sync lift sets: \(error.localizedDescription)")
        }

        isSyncingLiftSets = false
        liftSetSyncProgress = nil
    }

    /// Syncs a single lift set to the backend (for new creations)
    func syncLiftSet(_ liftSet: LiftSet) async {
        let dto = liftSet.toDTO()

        do {
            _ = try await APIService.shared.createLiftSets([dto])
            retryQueue.removePendingLiftSetOperation(liftSetId: liftSet.id)
        } catch {
            print("SyncService: Failed to sync lift set \(liftSet.id): \(error.localizedDescription)")
            retryQueue.addPendingLiftSetCreate(liftSetId: liftSet.id)
        }
    }

    /// Syncs multiple lift sets to the backend (batch create)
    func syncLiftSets(_ liftSets: [LiftSet]) async {
        guard !liftSets.isEmpty else { return }

        let dtos = liftSets.map { $0.toDTO() }

        do {
            _ = try await APIService.shared.createLiftSets(dtos)
            for liftSet in liftSets {
                retryQueue.removePendingLiftSetOperation(liftSetId: liftSet.id)
            }
        } catch {
            print("SyncService: Failed to batch sync lift sets: \(error.localizedDescription)")
            for liftSet in liftSets {
                retryQueue.addPendingLiftSetCreate(liftSetId: liftSet.id)
            }
        }
    }

    /// Deletes a lift set from the backend
    func deleteLiftSet(_ liftSetId: UUID) async {
        do {
            _ = try await APIService.shared.deleteLiftSets([liftSetId])
            retryQueue.removePendingLiftSetOperation(liftSetId: liftSetId)
        } catch {
            print("SyncService: Failed to delete lift set \(liftSetId): \(error.localizedDescription)")
            retryQueue.addPendingLiftSetDelete(liftSetId: liftSetId)
        }
    }

    /// Deletes multiple lift sets from the backend (batch delete)
    func deleteLiftSets(_ liftSetIds: [UUID]) async {
        guard !liftSetIds.isEmpty else { return }

        do {
            _ = try await APIService.shared.deleteLiftSets(liftSetIds)
            for id in liftSetIds {
                retryQueue.removePendingLiftSetOperation(liftSetId: id)
            }
        } catch {
            print("SyncService: Failed to batch delete lift sets: \(error.localizedDescription)")
            for id in liftSetIds {
                retryQueue.addPendingLiftSetDelete(liftSetId: id)
            }
        }
    }

    /// Process pending lift set operations from retry queue
    func processLiftSetRetryQueue() async {
        guard let context = modelContext else { return }

        let pendingOperations = retryQueue.getPendingLiftSetOperations()

        for operation in pendingOperations {
            switch operation.operationType {
            case .upsert:
                if let liftSet = fetchLiftSet(by: operation.liftSetId, context: context) {
                    do {
                        _ = try await APIService.shared.createLiftSets([liftSet.toDTO()])
                        retryQueue.removePendingLiftSetOperation(liftSetId: operation.liftSetId)
                    } catch {
                        retryQueue.incrementLiftSetRetryCount(for: operation.liftSetId)
                    }
                } else {
                    // Lift set no longer exists locally, remove from queue
                    retryQueue.removePendingLiftSetOperation(liftSetId: operation.liftSetId)
                }

            case .delete:
                do {
                    _ = try await APIService.shared.deleteLiftSets([operation.liftSetId])
                    retryQueue.removePendingLiftSetOperation(liftSetId: operation.liftSetId)
                } catch {
                    retryQueue.incrementLiftSetRetryCount(for: operation.liftSetId)
                }
            }
        }
    }

    private func importLiftSetsFromBackend(_ dtos: [LiftSetDTO], context: ModelContext) async {
        let existingLiftSets = fetchAllLiftSets(context: context)
        let existingIds = Set(existingLiftSets.map { $0.id })

        for dto in dtos {
            if existingIds.contains(dto.liftSetId) {
                // Update existing lift set
                if let existing = existingLiftSets.first(where: { $0.id == dto.liftSetId }) {
                    existing.reps = dto.reps
                    existing.weight = dto.weight
                    existing.createdTimezone = dto.createdTimezone
                    if let createdDatetime = dto.createdDatetime {
                        existing.createdAt = createdDatetime
                    }
                }
            } else {
                // Create new lift set - need to find the exercise
                if let exercise = fetchExercise(by: dto.exerciseId, context: context) {
                    let liftSet = LiftSet(exercise: exercise, reps: dto.reps, weight: dto.weight)
                    // Override the auto-generated values with backend values
                    liftSet.id = dto.liftSetId
                    liftSet.createdTimezone = dto.createdTimezone
                    if let createdDatetime = dto.createdDatetime {
                        liftSet.createdAt = createdDatetime
                    }
                    context.insert(liftSet)
                } else {
                    print("SyncService: Skipping lift set \(dto.liftSetId) - exercise \(dto.exerciseId) not found")
                }
            }
        }

        try? context.save()
    }

    private func fetchLiftSet(by id: UUID, context: ModelContext) -> LiftSet? {
        let descriptor = FetchDescriptor<LiftSet>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchAllLiftSets(context: ModelContext) -> [LiftSet] {
        let descriptor = FetchDescriptor<LiftSet>()
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Estimated 1RM Sync

    /// Fetches all estimated 1RMs from backend using pagination and imports them locally
    func syncEstimated1RMsFromBackend() async {
        guard let context = modelContext else { return }

        isSyncingEstimated1RMs = true
        estimated1RMSyncProgress = "Syncing..."

        var pageToken: String? = nil
        var totalFetched = 0

        do {
            repeat {
                let response = try await APIService.shared.getEstimated1RMs(limit: 500, pageToken: pageToken)
                totalFetched += response.count

                await importEstimated1RMsFromBackend(response.estimated1RMs, context: context)

                estimated1RMSyncProgress = "Synced \(totalFetched) estimated 1RMs..."
                pageToken = response.hasMore ? response.nextPageToken : nil

            } while pageToken != nil

            print("SyncService: Completed estimated 1RM sync, fetched \(totalFetched) total")
        } catch {
            print("SyncService: Failed to sync estimated 1RMs: \(error.localizedDescription)")
        }

        isSyncingEstimated1RMs = false
        estimated1RMSyncProgress = nil
    }

    /// Syncs a single estimated 1RM to the backend (for new creations)
    func syncEstimated1RM(_ estimated1RM: Estimated1RM) async {
        let dto = estimated1RM.toDTO()

        do {
            _ = try await APIService.shared.createEstimated1RMs([dto])
            retryQueue.removePendingEstimated1RMOperation(estimated1RMId: estimated1RM.id)
        } catch {
            print("SyncService: Failed to sync estimated 1RM \(estimated1RM.id): \(error.localizedDescription)")
            retryQueue.addPendingEstimated1RMCreate(estimated1RMId: estimated1RM.id, liftSetId: estimated1RM.setId)
        }
    }

    /// Syncs multiple estimated 1RMs to the backend (batch create)
    func syncEstimated1RMs(_ estimated1RMs: [Estimated1RM]) async {
        guard !estimated1RMs.isEmpty else { return }

        let dtos = estimated1RMs.map { $0.toDTO() }

        do {
            _ = try await APIService.shared.createEstimated1RMs(dtos)
            for estimated1RM in estimated1RMs {
                retryQueue.removePendingEstimated1RMOperation(estimated1RMId: estimated1RM.id)
            }
        } catch {
            print("SyncService: Failed to batch sync estimated 1RMs: \(error.localizedDescription)")
            for estimated1RM in estimated1RMs {
                retryQueue.addPendingEstimated1RMCreate(estimated1RMId: estimated1RM.id, liftSetId: estimated1RM.setId)
            }
        }
    }

    /// Deletes an estimated 1RM from the backend (API uses liftSetId)
    func deleteEstimated1RM(estimated1RMId: UUID, liftSetId: UUID) async {
        do {
            _ = try await APIService.shared.deleteEstimated1RMs(liftSetIds: [liftSetId])
            retryQueue.removePendingEstimated1RMOperation(estimated1RMId: estimated1RMId)
        } catch {
            print("SyncService: Failed to delete estimated 1RM \(estimated1RMId): \(error.localizedDescription)")
            retryQueue.addPendingEstimated1RMDelete(estimated1RMId: estimated1RMId, liftSetId: liftSetId)
        }
    }

    /// Deletes multiple estimated 1RMs from the backend (batch delete using liftSetIds)
    func deleteEstimated1RMs(liftSetIds: [UUID]) async {
        guard !liftSetIds.isEmpty else { return }

        do {
            _ = try await APIService.shared.deleteEstimated1RMs(liftSetIds: liftSetIds)
        } catch {
            print("SyncService: Failed to batch delete estimated 1RMs: \(error.localizedDescription)")
            // Note: For batch deletes, we don't have the estimated1RMIds, so we can't add to retry queue
            // The caller should handle this case by tracking individual operations
        }
    }

    /// Process pending estimated 1RM operations from retry queue
    func processEstimated1RMRetryQueue() async {
        guard let context = modelContext else { return }

        let pendingOperations = retryQueue.getPendingEstimated1RMOperations()

        for operation in pendingOperations {
            switch operation.operationType {
            case .upsert:
                if let estimated1RM = fetchEstimated1RM(by: operation.estimated1RMId, context: context) {
                    do {
                        _ = try await APIService.shared.createEstimated1RMs([estimated1RM.toDTO()])
                        retryQueue.removePendingEstimated1RMOperation(estimated1RMId: operation.estimated1RMId)
                    } catch {
                        retryQueue.incrementEstimated1RMRetryCount(for: operation.estimated1RMId)
                    }
                } else {
                    // Estimated 1RM no longer exists locally, remove from queue
                    retryQueue.removePendingEstimated1RMOperation(estimated1RMId: operation.estimated1RMId)
                }

            case .delete:
                do {
                    _ = try await APIService.shared.deleteEstimated1RMs(liftSetIds: [operation.liftSetId])
                    retryQueue.removePendingEstimated1RMOperation(estimated1RMId: operation.estimated1RMId)
                } catch {
                    retryQueue.incrementEstimated1RMRetryCount(for: operation.estimated1RMId)
                }
            }
        }
    }

    private func importEstimated1RMsFromBackend(_ dtos: [Estimated1RMDTO], context: ModelContext) async {
        let existingEstimated1RMs = fetchAllEstimated1RMs(context: context)
        let existingIds = Set(existingEstimated1RMs.map { $0.id })

        for dto in dtos {
            if existingIds.contains(dto.estimated1RMId) {
                // Update existing estimated 1RM
                if let existing = existingEstimated1RMs.first(where: { $0.id == dto.estimated1RMId }) {
                    existing.value = dto.value
                    existing.setId = dto.liftSetId
                    existing.createdTimezone = dto.createdTimezone
                    if let createdDatetime = dto.createdDatetime {
                        existing.createdAt = createdDatetime
                    }
                }
            } else {
                // Create new estimated 1RM - need to find the exercise
                if let exercise = fetchExercise(by: dto.exerciseId, context: context) {
                    let estimated1RM = Estimated1RM(exercise: exercise, value: dto.value, setId: dto.liftSetId)
                    // Override the auto-generated values with backend values
                    estimated1RM.id = dto.estimated1RMId
                    estimated1RM.createdTimezone = dto.createdTimezone
                    if let createdDatetime = dto.createdDatetime {
                        estimated1RM.createdAt = createdDatetime
                    }
                    context.insert(estimated1RM)
                } else {
                    print("SyncService: Skipping estimated 1RM \(dto.estimated1RMId) - exercise \(dto.exerciseId) not found")
                }
            }
        }

        try? context.save()
    }

    private func fetchEstimated1RM(by id: UUID, context: ModelContext) -> Estimated1RM? {
        let descriptor = FetchDescriptor<Estimated1RM>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchAllEstimated1RMs(context: ModelContext) -> [Estimated1RM] {
        let descriptor = FetchDescriptor<Estimated1RM>()
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Retry Queue Processing

    func processRetryQueue() async {
        guard let context = modelContext else { return }

        let pendingOperations = retryQueue.getPendingOperations()

        for operation in pendingOperations {
            switch operation.operationType {
            case .upsert:
                if let exercise = fetchExercise(by: operation.exerciseId, context: context) {
                    do {
                        _ = try await APIService.shared.upsertExercises([exercise.toDTO()])
                        retryQueue.removePendingOperation(exerciseId: operation.exerciseId)
                    } catch {
                        retryQueue.incrementRetryCount(for: operation.exerciseId)
                    }
                } else {
                    retryQueue.removePendingOperation(exerciseId: operation.exerciseId)
                }

            case .delete:
                do {
                    _ = try await APIService.shared.deleteExercises([operation.exerciseId])
                    retryQueue.removePendingOperation(exerciseId: operation.exerciseId)
                } catch {
                    retryQueue.incrementRetryCount(for: operation.exerciseId)
                }
            }
        }
    }

    // MARK: - Fallback: Create Default Exercises

    func createDefaultExercisesLocally() async {
        guard let context = modelContext else { return }

        let existingExercises = fetchAllExercises(context: context)
        guard existingExercises.isEmpty else { return }

        let defaults = getDefaultExercises()
        for (name, loadType) in defaults {
            let exercise = Exercises(name: name, isCustom: false, loadType: loadType)
            context.insert(exercise)
        }

        try? context.save()
    }

    func createDefaultExercisesAndSync() async {
        guard let context = modelContext else { return }

        let existingExercises = fetchAllExercises(context: context)
        guard existingExercises.isEmpty else { return }

        await createAndSyncDefaultExercises(context: context)
    }

    func retryFetchExercises() async -> Bool {
        guard let context = modelContext else { return false }

        do {
            let response = try await APIService.shared.getExercises()

            if response.exercises.isEmpty {
                return false
            } else {
                await importExercisesFromBackend(response.exercises, context: context)
                return true
            }
        } catch {
            print("SyncService: Retry fetch failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Helpers

    private func createAndSyncDefaultExercises(context: ModelContext) async {
        let defaults = getDefaultExercises()
        var exerciseDTOs: [ExerciseDTO] = []

        for (name, loadType) in defaults {
            let exercise = Exercises(name: name, isCustom: false, loadType: loadType)
            context.insert(exercise)
            exerciseDTOs.append(exercise.toDTO())
        }

        try? context.save()

        do {
            _ = try await APIService.shared.upsertExercises(exerciseDTOs)
        } catch {
            print("SyncService: Failed to batch POST default exercises: \(error.localizedDescription)")
            for dto in exerciseDTOs {
                retryQueue.addPendingUpsert(exerciseId: dto.exerciseItemId)
            }
        }
    }

    private func importExercisesFromBackend(_ dtos: [ExerciseDTO], context: ModelContext) async {
        let existingExercises = fetchAllExercises(context: context)
        let existingIds = Set(existingExercises.map { $0.id })

        for dto in dtos {
            // Skip deleted exercises from backend
            if dto.deleted == true {
                // If it exists locally, mark as deleted
                if let existing = existingExercises.first(where: { $0.id == dto.exerciseItemId }) {
                    existing.deleted = true
                }
                continue
            }

            if existingIds.contains(dto.exerciseItemId) {
                if let existing = existingExercises.first(where: { $0.id == dto.exerciseItemId }) {
                    existing.name = dto.name
                    existing.isCustom = dto.isCustom
                    existing.loadType = dto.loadType
                    existing.notes = dto.notes
                    existing.deleted = dto.deleted ?? false
                }
            } else {
                let loadType = ExerciseLoadType(rawValue: dto.loadType) ?? .barbell
                let exercise = Exercises(
                    id: dto.exerciseItemId,
                    name: dto.name,
                    isCustom: dto.isCustom,
                    loadType: loadType,
                    createdAt: dto.createdDatetime ?? Date(),
                    createdTimezone: dto.createdTimezone,
                    notes: dto.notes,
                    deleted: dto.deleted ?? false
                )
                context.insert(exercise)
            }
        }

        try? context.save()
    }

    private func getDefaultExercises() -> [(String, ExerciseLoadType)] {
        return [
            ("Deadlift", .barbell),
            ("Squat", .barbell),
            ("Bench Press", .barbell),
            ("Overhead Press", .barbell),
            ("Barbell Row", .barbell),
            ("Pull Ups", .singleLoad),
            ("Dips", .singleLoad)
        ]
    }

    private func fetchExercise(by id: UUID, context: ModelContext) -> Exercises? {
        let descriptor = FetchDescriptor<Exercises>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchAllExercises(context: ModelContext) -> [Exercises] {
        let descriptor = FetchDescriptor<Exercises>()
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Cleanup

    func clearOnLogout() {
        retryQueue.clearAll()
    }
}
