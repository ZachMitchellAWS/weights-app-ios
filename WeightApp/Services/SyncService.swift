//
//  SyncService.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/30/26.
//

import Foundation
import SwiftData
import Combine
import OSLog

@MainActor
class SyncService: ObservableObject {
    static let shared = SyncService()

    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    private let retryQueue = SyncRetryQueue.shared

    // Sync state for UI indicators
    @Published var isSyncingLiftSets = false
    @Published var liftSetSyncProgress: String?
    @Published var isSyncingEstimated1RMs = false
    @Published var estimated1RMSyncProgress: String?

    // MARK: - Persisted Sync State

    struct SyncState: Codable {
        var syncComplete: Bool = false

        // Per-step completion
        var userPropertiesComplete: Bool = false
        var exercisesComplete: Bool = false
        var sequencesComplete: Bool = false
        var splitsComplete: Bool = false
        var liftSetsComplete: Bool = false
        var estimated1RMsComplete: Bool = false

        // Pagination cursors (nil = start from beginning)
        var liftSetPageToken: String? = nil
        var estimated1RMPageToken: String? = nil

        // Running totals for progress display on resume
        var liftSetsFetched: Int = 0
        var estimated1RMsFetched: Int = 0
    }

    private static let syncStateKey = "SyncService.SyncState"

    var currentSyncState: SyncState { syncState }

    private var syncState: SyncState {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.syncStateKey) else {
                return SyncState()
            }
            return (try? JSONDecoder().decode(SyncState.self, from: data)) ?? SyncState()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.syncStateKey)
            }
        }
    }

    private init() {}

    // MARK: - Configuration

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
        self.modelContext = container.mainContext
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Initial Sync

    func performInitialSync(isNewUser: Bool) async {
        guard let context = modelContext else {
            SyncLogger.sync.error("ModelContext not set, cannot sync")
            return
        }

        var state = syncState

        // Already completed — nothing to do
        if state.syncComplete {
            SyncLogger.sync.debug("Sync already complete, skipping")
            return
        }

        SyncLogger.sync.info("Starting initial sync (isNewUser: \(isNewUser))")

        // Step 1: Sync user properties (non-blocking - failure doesn't stop exercise sync)
        if !state.userPropertiesComplete {
            SyncLogger.sync.info("Step 1: Syncing user properties")
            await syncUserProperties()
            state.userPropertiesComplete = true
            syncState = state
        } else {
            SyncLogger.sync.debug("Step 1: User properties already synced, skipping")
        }

        // Step 2: Sync exercises
        if !state.exercisesComplete {
            SyncLogger.sync.info("Step 2: Syncing exercises")
            do {
                let response = try await APIService.shared.getExercises()

                if response.exercises.isEmpty {
                    SyncLogger.sync.info("No exercises on backend, creating defaults")
                    await createAndSyncDefaultExercises(context: context)
                } else {
                    SyncLogger.sync.info("Importing \(response.exercises.count) exercises from backend")
                    await importExercisesFromBackend(response.exercises)
                }

                await processRetryQueue()
                state.exercisesComplete = true
                syncState = state
            } catch {
                SyncLogger.sync.error("Initial exercise sync failed: \(error.localizedDescription)")
            }
        } else {
            SyncLogger.sync.debug("Step 2: Exercises already synced, skipping")
        }

        // Assign default exercises to days now that exercises exist
        if let ctx = modelContext {
            WorkoutSequenceStore.assignDefaultExercisesToDays(context: ctx)
        }

        // Step 2.5: Sync sequences (references exerciseIds, so must run after exercises)
        if !state.sequencesComplete {
            SyncLogger.sync.info("Step 2.5: Syncing sequences")
            await syncSequencesFromBackend()
            await processSequenceRetryQueue()
            state.sequencesComplete = true
            syncState = state
        } else {
            SyncLogger.sync.debug("Step 2.5: Sequences already synced, skipping")
        }

        // Step 2.6: Sync splits (references dayIds which are sequence IDs, so must run after sequences)
        if !state.splitsComplete {
            SyncLogger.sync.info("Step 2.6: Syncing splits")
            await syncSplitsFromBackend()
            await processSplitRetryQueue()
            state.splitsComplete = true
            syncState = state
        } else {
            SyncLogger.sync.debug("Step 2.6: Splits already synced, skipping")
        }

        // Step 3: Sync lift sets and estimated 1RMs (interleaved, resumable)
        if !state.liftSetsComplete || !state.estimated1RMsComplete {
            SyncLogger.sync.info("Step 3: Syncing lift sets and estimated 1RMs")
            await syncLiftSetsAndEstimated1RMs(resumeState: &state)
        } else {
            SyncLogger.sync.debug("Step 3: Lift sets and E1RMs already synced, skipping")
        }

        await processLiftSetRetryQueue()
        await processEstimated1RMRetryQueue()

        // All done
        state.syncComplete = true
        syncState = state
        SyncLogger.sync.info("Initial sync complete")
    }

    /// Resumes an incomplete sync if one was interrupted (e.g. app killed mid-sync)
    func resumeSyncIfNeeded() async {
        let state = syncState
        guard !state.syncComplete else { return }
        SyncLogger.sync.info("Resuming incomplete sync (liftSets: \(state.liftSetsComplete), e1rms: \(state.estimated1RMsComplete))")
        await performInitialSync(isNewUser: false)
    }

    /// Force a complete re-sync by clearing persisted state and re-downloading everything
    func forceResync() async {
        SyncLogger.sync.info("Force resync requested, clearing sync state")
        UserDefaults.standard.removeObject(forKey: Self.syncStateKey)
        await performInitialSync(isNewUser: false)
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
            if let minReps = response.minReps {
                userProperties.minReps = minReps
            }
            if let maxReps = response.maxReps {
                userProperties.maxReps = maxReps
            }
            if let easyMinReps = response.easyMinReps {
                userProperties.easyMinReps = easyMinReps
            }
            if let easyMaxReps = response.easyMaxReps {
                userProperties.easyMaxReps = easyMaxReps
            }
            if let moderateMinReps = response.moderateMinReps {
                userProperties.moderateMinReps = moderateMinReps
            }
            if let moderateMaxReps = response.moderateMaxReps {
                userProperties.moderateMaxReps = moderateMaxReps
            }
            if let hardMinReps = response.hardMinReps {
                userProperties.hardMinReps = hardMinReps
            }
            if let hardMaxReps = response.hardMaxReps {
                userProperties.hardMaxReps = hardMaxReps
            }

            try? context.save()

            // Also save createdDatetime to keychain
            KeychainService.shared.saveUserProperties(createdDatetime: response.createdDatetime)
        } catch {
            SyncLogger.sync.error("Failed to sync user properties: \(error.localizedDescription)")
            // Don't block exercise sync - user properties are not critical
        }
    }

    func updateChangePlates(_ plates: [Double]) async {
        do {
            let request = UserPropertiesRequest(availableChangePlates: plates)
            _ = try await APIService.shared.updateUserProperties(request)
            retryQueue.removePendingUserPropertiesSync()
        } catch {
            SyncLogger.sync.error("Failed to update change plates: \(error.localizedDescription)")
            retryQueue.addPendingUserPropertiesSync()
        }
    }

    func updateBodyweight(_ bodyweight: Double?) async {
        do {
            var request = UserPropertiesRequest()
            if let bodyweight = bodyweight {
                request.bodyweight = bodyweight
            } else {
                request.clearBodyweight = true
            }
            _ = try await APIService.shared.updateUserProperties(request)
            retryQueue.removePendingUserPropertiesSync()
        } catch {
            SyncLogger.sync.error("Failed to update bodyweight: \(error.localizedDescription)")
            retryQueue.addPendingUserPropertiesSync()
        }
    }

    func updateRepRange(minReps: Int, maxReps: Int) async {
        do {
            let request = UserPropertiesRequest(minReps: minReps, maxReps: maxReps)
            _ = try await APIService.shared.updateUserProperties(request)
            retryQueue.removePendingUserPropertiesSync()
        } catch {
            SyncLogger.sync.error("Failed to update rep range: \(error.localizedDescription)")
            retryQueue.addPendingUserPropertiesSync()
        }
    }

    func updateEffortRepRange(easyMinReps: Int, easyMaxReps: Int, moderateMinReps: Int, moderateMaxReps: Int, hardMinReps: Int, hardMaxReps: Int) async {
        do {
            let request = UserPropertiesRequest(
                easyMinReps: easyMinReps,
                easyMaxReps: easyMaxReps,
                moderateMinReps: moderateMinReps,
                moderateMaxReps: moderateMaxReps,
                hardMinReps: hardMinReps,
                hardMaxReps: hardMaxReps
            )
            _ = try await APIService.shared.updateUserProperties(request)
            retryQueue.removePendingUserPropertiesSync()
        } catch {
            SyncLogger.sync.error("Failed to update effort rep ranges: \(error.localizedDescription)")
            retryQueue.addPendingUserPropertiesSync()
        }
    }

    func processUserPropertiesRetryQueue() async {
        guard let context = modelContext else { return }
        guard retryQueue.hasUserPropertiesPending() else { return }

        let userProperties = fetchOrCreateUserProperties(context: context)

        do {
            let request = UserPropertiesRequest(
                bodyweight: userProperties.bodyweight,
                availableChangePlates: userProperties.availableChangePlates,
                minReps: userProperties.minReps,
                maxReps: userProperties.maxReps,
                easyMinReps: userProperties.easyMinReps,
                easyMaxReps: userProperties.easyMaxReps,
                moderateMinReps: userProperties.moderateMinReps,
                moderateMaxReps: userProperties.moderateMaxReps,
                hardMinReps: userProperties.hardMinReps,
                hardMaxReps: userProperties.hardMaxReps
            )
            _ = try await APIService.shared.updateUserProperties(request)
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
            SyncLogger.sync.debug("Synced exercise \(exercise.id)")
        } catch {
            SyncLogger.sync.error("Failed to sync exercise \(exercise.id): \(error.localizedDescription)")
            retryQueue.addPendingUpsert(exerciseId: exercise.id)
        }
    }

    func deleteExercise(_ exerciseId: UUID) async {
        do {
            _ = try await APIService.shared.deleteExercises([exerciseId])
            retryQueue.removePendingOperation(exerciseId: exerciseId)
            SyncLogger.sync.debug("Deleted exercise \(exerciseId)")
        } catch {
            SyncLogger.sync.error("Failed to delete exercise \(exerciseId): \(error.localizedDescription)")
            retryQueue.addPendingDelete(exerciseId: exerciseId)
        }
    }

    // MARK: - Interleaved Lift Set & Estimated 1RM Sync

    /// Fetches lift sets and estimated 1RMs in interleaved pages for more even progress
    func syncLiftSetsAndEstimated1RMs() async {
        var state = syncState
        // Reset lift set / E1RM state for a fresh full sync
        state.liftSetsComplete = false
        state.estimated1RMsComplete = false
        state.liftSetPageToken = nil
        state.estimated1RMPageToken = nil
        state.liftSetsFetched = 0
        state.estimated1RMsFetched = 0
        await syncLiftSetsAndEstimated1RMs(resumeState: &state)
        state.syncComplete = true
        syncState = state
    }

    /// Resumable version that persists pagination state after each page.
    /// Runs all SwiftData work in a single background context to avoid repeated full-table scans
    /// and minimizes saves to reduce @Query-triggered UI refreshes.
    private func syncLiftSetsAndEstimated1RMs(resumeState state: inout SyncState) async {
        guard let container = modelContainer else { return }

        isSyncingLiftSets = true
        liftSetSyncProgress = "Syncing..."

        var totalLiftSets = state.liftSetsFetched
        var totalE1RMs = state.estimated1RMsFetched
        var liftSetsDone = state.liftSetsComplete
        var e1rmsDone = state.estimated1RMsComplete
        var liftSetPageToken = state.liftSetPageToken
        var e1rmPageToken = state.estimated1RMPageToken

        do {
            // Run the entire paginated sync in a single background context
            let (finalLiftSets, finalE1RMs, finalLSDone, finalE1RMDone, finalLSToken, finalE1RMToken) = try await Task.detached {
                let context = ModelContext(container)
                context.autosaveEnabled = false

                // Build dedup dictionaries once upfront
                let existingLiftSets = (try? context.fetch(FetchDescriptor<LiftSets>())) ?? []
                var liftSetById = Dictionary(uniqueKeysWithValues: existingLiftSets.map { ($0.id, $0) })

                let existingE1RMs = (try? context.fetch(FetchDescriptor<Estimated1RMs>())) ?? []
                var e1rmById = Dictionary(uniqueKeysWithValues: existingE1RMs.map { ($0.id, $0) })

                // Cache exercise lookup
                let allExercises = (try? context.fetch(FetchDescriptor<Exercises>())) ?? []
                let exerciseById = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })

                var tLS = totalLiftSets
                var tE1RM = totalE1RMs
                var lsDone = liftSetsDone
                var e1rmDone = e1rmsDone
                var lsToken = liftSetPageToken
                var e1rmToken = e1rmPageToken
                var pagesSinceSave = 0

                while !lsDone || !e1rmDone {
                    // Fetch one page of lift sets
                    if !lsDone {
                        let response = try await APIService.shared.getLiftSets(limit: 500, pageToken: lsToken)
                        tLS += response.count

                        for dto in response.liftSets {
                            if let existing = liftSetById[dto.liftSetId] {
                                existing.reps = dto.reps
                                existing.weight = dto.weight
                                existing.createdTimezone = dto.createdTimezone
                                existing.createdAt = dto.createdDatetime
                                existing.isBaselineSet = dto.isBaselineSet ?? false
                                existing.rir = dto.rir
                                existing.bodyweightUsed = dto.bodyweightUsed
                            } else if let exercise = exerciseById[dto.exerciseId] {
                                let liftSet = LiftSets(exercise: exercise, reps: dto.reps, weight: dto.weight)
                                liftSet.id = dto.liftSetId
                                liftSet.createdTimezone = dto.createdTimezone
                                liftSet.createdAt = dto.createdDatetime
                                liftSet.isBaselineSet = dto.isBaselineSet ?? false
                                liftSet.rir = dto.rir
                                liftSet.bodyweightUsed = dto.bodyweightUsed
                                context.insert(liftSet)
                                liftSetById[dto.liftSetId] = liftSet
                            }
                        }

                        lsToken = response.hasMore ? response.nextPageToken : nil
                        lsDone = !response.hasMore
                    }

                    // Fetch one page of estimated 1RMs
                    if !e1rmDone {
                        let response = try await APIService.shared.getEstimated1RMs(limit: 500, pageToken: e1rmToken)
                        tE1RM += response.count

                        for dto in response.estimated1RMs {
                            if let existing = e1rmById[dto.estimated1RMId] {
                                existing.value = dto.value
                                existing.setId = dto.liftSetId
                                existing.createdTimezone = dto.createdTimezone
                                existing.createdAt = dto.createdDatetime
                            } else if let exercise = exerciseById[dto.exerciseId] {
                                let estimated1RM = Estimated1RMs(exercise: exercise, value: dto.value, setId: dto.liftSetId)
                                estimated1RM.id = dto.estimated1RMId
                                estimated1RM.createdTimezone = dto.createdTimezone
                                estimated1RM.createdAt = dto.createdDatetime
                                context.insert(estimated1RM)
                                e1rmById[dto.estimated1RMId] = estimated1RM
                            }
                        }

                        e1rmToken = response.hasMore ? response.nextPageToken : nil
                        e1rmDone = !response.hasMore
                    }

                    pagesSinceSave += 1

                    // Save every 5 page-pairs for crash safety without excessive UI churn
                    if pagesSinceSave >= 5 || (lsDone && e1rmDone) {
                        try? context.save()
                        pagesSinceSave = 0

                        // Persist cursors so a crash can resume from here
                        await MainActor.run {
                            var s = self.syncState
                            s.liftSetPageToken = lsToken
                            s.estimated1RMPageToken = e1rmToken
                            s.liftSetsFetched = tLS
                            s.estimated1RMsFetched = tE1RM
                            s.liftSetsComplete = lsDone
                            s.estimated1RMsComplete = e1rmDone
                            self.syncState = s
                        }
                    }

                    // Update progress on main actor
                    await MainActor.run {
                        self.liftSetSyncProgress = "Synced \(tLS) sets, \(tE1RM) 1RMs..."
                    }
                }

                // Final save for any remaining unsaved changes
                try? context.save()

                return (tLS, tE1RM, lsDone, e1rmDone, lsToken, e1rmToken)
            }.value

            totalLiftSets = finalLiftSets
            totalE1RMs = finalE1RMs
            liftSetsDone = finalLSDone
            e1rmsDone = finalE1RMDone
            liftSetPageToken = finalLSToken
            e1rmPageToken = finalE1RMToken

            SyncLogger.sync.info("Completed interleaved sync: \(totalLiftSets) lift sets + \(totalE1RMs) estimated 1RMs")
        } catch {
            SyncLogger.sync.error("Failed during interleaved sync: \(error.localizedDescription)")
        }

        // Persist final state
        state.liftSetPageToken = liftSetPageToken
        state.estimated1RMPageToken = e1rmPageToken
        state.liftSetsFetched = totalLiftSets
        state.estimated1RMsFetched = totalE1RMs
        state.liftSetsComplete = liftSetsDone
        state.estimated1RMsComplete = e1rmsDone
        syncState = state

        isSyncingLiftSets = false
        liftSetSyncProgress = nil
    }

    // MARK: - Lift Set Sync

    /// Fetches all lift sets from backend using pagination and imports them locally
    func syncLiftSetsFromBackend() async {
        isSyncingLiftSets = true
        liftSetSyncProgress = "Syncing..."

        var pageToken: String? = nil
        var totalFetched = 0

        do {
            repeat {
                let response = try await APIService.shared.getLiftSets(limit: 500, pageToken: pageToken)
                totalFetched += response.count

                await importLiftSetsFromBackend(response.liftSets)

                liftSetSyncProgress = "Synced \(totalFetched) sets..."
                pageToken = response.hasMore ? response.nextPageToken : nil

            } while pageToken != nil

            SyncLogger.sync.info("Completed lift set sync, fetched \(totalFetched) total")
        } catch {
            SyncLogger.sync.error("Failed to sync lift sets: \(error.localizedDescription)")
        }

        isSyncingLiftSets = false
        liftSetSyncProgress = nil
    }

    /// Syncs a single lift set to the backend (for new creations)
    func syncLiftSet(_ liftSet: LiftSets) async {
        let dto = liftSet.toDTO()

        do {
            _ = try await APIService.shared.createLiftSets([dto])
            retryQueue.removePendingLiftSetOperation(liftSetId: liftSet.id)
            SyncLogger.sync.debug("Synced lift set \(liftSet.id)")
        } catch {
            SyncLogger.sync.error("Failed to sync lift set \(liftSet.id): \(error.localizedDescription)")
            retryQueue.addPendingLiftSetCreate(liftSetId: liftSet.id)
        }
    }

    /// Syncs multiple lift sets to the backend (batch create)
    func syncLiftSets(_ liftSets: [LiftSets]) async {
        guard !liftSets.isEmpty else { return }

        let dtos = liftSets.map { $0.toDTO() }

        do {
            _ = try await APIService.shared.createLiftSets(dtos)
            for liftSet in liftSets {
                retryQueue.removePendingLiftSetOperation(liftSetId: liftSet.id)
            }
        } catch {
            SyncLogger.sync.error("Failed to batch sync \(liftSets.count) lift sets: \(error.localizedDescription)")
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
            SyncLogger.sync.debug("Deleted lift set \(liftSetId)")
        } catch {
            SyncLogger.sync.error("Failed to delete lift set \(liftSetId): \(error.localizedDescription)")
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
            SyncLogger.sync.error("Failed to batch delete \(liftSetIds.count) lift sets: \(error.localizedDescription)")
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

    private func importLiftSetsFromBackend(_ dtos: [LiftSetDTO]) async {
        guard let container = modelContainer else { return }
        let sendableDtos = dtos
        await Task.detached {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let existingLiftSets = (try? context.fetch(FetchDescriptor<LiftSets>())) ?? []
            let existingById = Dictionary(uniqueKeysWithValues: existingLiftSets.map { ($0.id, $0) })

            for dto in sendableDtos {
                if let existing = existingById[dto.liftSetId] {
                    existing.reps = dto.reps
                    existing.weight = dto.weight
                    existing.createdTimezone = dto.createdTimezone
                    existing.createdAt = dto.createdDatetime
                    existing.isBaselineSet = dto.isBaselineSet ?? false
                    existing.rir = dto.rir
                    existing.bodyweightUsed = dto.bodyweightUsed
                } else {
                    let descriptor = FetchDescriptor<Exercises>(predicate: #Predicate { $0.id == dto.exerciseId })
                    if let exercise = try? context.fetch(descriptor).first {
                        let liftSet = LiftSets(exercise: exercise, reps: dto.reps, weight: dto.weight)
                        liftSet.id = dto.liftSetId
                        liftSet.createdTimezone = dto.createdTimezone
                        liftSet.createdAt = dto.createdDatetime
                        liftSet.isBaselineSet = dto.isBaselineSet ?? false
                        liftSet.rir = dto.rir
                        liftSet.bodyweightUsed = dto.bodyweightUsed
                        context.insert(liftSet)
                    } else {
                        SyncLogger.sync.debug("Skipping lift set \(dto.liftSetId) — exercise \(dto.exerciseId) not found")
                    }
                }
            }

            try? context.save()
        }.value
    }

    private func fetchLiftSet(by id: UUID, context: ModelContext) -> LiftSets? {
        let descriptor = FetchDescriptor<LiftSets>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Estimated 1RM Sync

    /// Fetches all estimated 1RMs from backend using pagination and imports them locally
    func syncEstimated1RMsFromBackend() async {
        isSyncingEstimated1RMs = true
        estimated1RMSyncProgress = "Syncing..."

        var pageToken: String? = nil
        var totalFetched = 0

        do {
            repeat {
                let response = try await APIService.shared.getEstimated1RMs(limit: 500, pageToken: pageToken)
                totalFetched += response.count

                await importEstimated1RMsFromBackend(response.estimated1RMs)

                estimated1RMSyncProgress = "Synced \(totalFetched) estimated 1RMs..."
                pageToken = response.hasMore ? response.nextPageToken : nil

            } while pageToken != nil

            SyncLogger.sync.info("Completed estimated 1RM sync, fetched \(totalFetched) total")
        } catch {
            SyncLogger.sync.error("Failed to sync estimated 1RMs: \(error.localizedDescription)")
        }

        isSyncingEstimated1RMs = false
        estimated1RMSyncProgress = nil
    }

    /// Syncs a single estimated 1RM to the backend (for new creations)
    func syncEstimated1RM(_ estimated1RM: Estimated1RMs) async {
        let dto = estimated1RM.toDTO()

        do {
            _ = try await APIService.shared.createEstimated1RMs([dto])
            retryQueue.removePendingEstimated1RMOperation(estimated1RMId: estimated1RM.id)
            SyncLogger.sync.debug("Synced estimated 1RM \(estimated1RM.id)")
        } catch {
            SyncLogger.sync.error("Failed to sync estimated 1RM \(estimated1RM.id): \(error.localizedDescription)")
            retryQueue.addPendingEstimated1RMCreate(estimated1RMId: estimated1RM.id, liftSetId: estimated1RM.setId)
        }
    }

    /// Syncs multiple estimated 1RMs to the backend (batch create)
    func syncEstimated1RMs(_ estimated1RMs: [Estimated1RMs]) async {
        guard !estimated1RMs.isEmpty else { return }

        let dtos = estimated1RMs.map { $0.toDTO() }

        do {
            _ = try await APIService.shared.createEstimated1RMs(dtos)
            for estimated1RM in estimated1RMs {
                retryQueue.removePendingEstimated1RMOperation(estimated1RMId: estimated1RM.id)
            }
        } catch {
            SyncLogger.sync.error("Failed to batch sync \(estimated1RMs.count) estimated 1RMs: \(error.localizedDescription)")
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
            SyncLogger.sync.debug("Deleted estimated 1RM \(estimated1RMId)")
        } catch {
            SyncLogger.sync.error("Failed to delete estimated 1RM \(estimated1RMId): \(error.localizedDescription)")
            retryQueue.addPendingEstimated1RMDelete(estimated1RMId: estimated1RMId, liftSetId: liftSetId)
        }
    }

    /// Deletes multiple estimated 1RMs from the backend (batch delete using liftSetIds)
    func deleteEstimated1RMs(liftSetIds: [UUID]) async {
        guard !liftSetIds.isEmpty else { return }

        do {
            _ = try await APIService.shared.deleteEstimated1RMs(liftSetIds: liftSetIds)
        } catch {
            SyncLogger.sync.error("Failed to batch delete estimated 1RMs: \(error.localizedDescription)")
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

    private func importEstimated1RMsFromBackend(_ dtos: [Estimated1RMDTO]) async {
        guard let container = modelContainer else { return }
        let sendableDtos = dtos
        await Task.detached {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let existingEstimated1RMs = (try? context.fetch(FetchDescriptor<Estimated1RMs>())) ?? []
            let existingById = Dictionary(uniqueKeysWithValues: existingEstimated1RMs.map { ($0.id, $0) })

            for dto in sendableDtos {
                if let existing = existingById[dto.estimated1RMId] {
                    existing.value = dto.value
                    existing.setId = dto.liftSetId
                    existing.createdTimezone = dto.createdTimezone
                    existing.createdAt = dto.createdDatetime
                } else {
                    let descriptor = FetchDescriptor<Exercises>(predicate: #Predicate { $0.id == dto.exerciseId })
                    if let exercise = try? context.fetch(descriptor).first {
                        let estimated1RM = Estimated1RMs(exercise: exercise, value: dto.value, setId: dto.liftSetId)
                        estimated1RM.id = dto.estimated1RMId
                        estimated1RM.createdTimezone = dto.createdTimezone
                        estimated1RM.createdAt = dto.createdDatetime
                        context.insert(estimated1RM)
                    } else {
                        SyncLogger.sync.debug("Skipping estimated 1RM \(dto.estimated1RMId) — exercise \(dto.exerciseId) not found")
                    }
                }
            }

            try? context.save()
        }.value
    }

    private func fetchEstimated1RM(by id: UUID, context: ModelContext) -> Estimated1RMs? {
        let descriptor = FetchDescriptor<Estimated1RMs>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Sequence Sync

    /// Fetches all sequences from backend and imports them locally, then pushes any local-only sequences
    func syncSequencesFromBackend() async {
        guard let context = modelContext else { return }

        do {
            let response = try await APIService.shared.getSequences()
            await importSequencesFromBackend(response.sequences)

            // Push any local-only sequences (e.g. from UserDefaults migration)
            let allLocal = fetchAllSequences(context: context)
            let backendIds = Set(response.sequences.map { $0.sequenceId })
            let localOnly = allLocal.filter { !$0.deleted && !backendIds.contains($0.id) }

            if !localOnly.isEmpty {
                let dtos = localOnly.map { $0.toDTO() }
                do {
                    _ = try await APIService.shared.upsertSequences(dtos)
                } catch {
                    SyncLogger.sync.error("Failed to push local sequences: \(error.localizedDescription)")
                    for seq in localOnly {
                        retryQueue.addPendingSequenceUpsert(sequenceId: seq.id)
                    }
                }
            }

            SyncLogger.sync.info("Completed sequence sync, fetched \(response.sequences.count) from backend")
        } catch {
            SyncLogger.sync.error("Failed to sync sequences: \(error.localizedDescription)")
        }
    }

    /// Syncs a single sequence to the backend
    func syncSequence(_ sequence: WorkoutSequence) async {
        let dto = sequence.toDTO()

        do {
            _ = try await APIService.shared.upsertSequences([dto])
            retryQueue.removePendingSequenceOperation(sequenceId: sequence.id)
            SyncLogger.sync.debug("Synced sequence \(sequence.id)")
        } catch {
            SyncLogger.sync.error("Failed to sync sequence \(sequence.id): \(error.localizedDescription)")
            retryQueue.addPendingSequenceUpsert(sequenceId: sequence.id)
        }
    }

    /// Deletes a sequence from the backend (soft delete)
    func deleteSequence(_ sequenceId: UUID) async {
        do {
            _ = try await APIService.shared.deleteSequences([sequenceId])
            retryQueue.removePendingSequenceOperation(sequenceId: sequenceId)
            SyncLogger.sync.debug("Deleted sequence \(sequenceId)")
        } catch {
            SyncLogger.sync.error("Failed to delete sequence \(sequenceId): \(error.localizedDescription)")
            retryQueue.addPendingSequenceDelete(sequenceId: sequenceId)
        }
    }

    /// Process pending sequence operations from retry queue
    func processSequenceRetryQueue() async {
        guard let context = modelContext else { return }

        let pendingOperations = retryQueue.getPendingSequenceOperations()

        for operation in pendingOperations {
            switch operation.operationType {
            case .upsert:
                if let sequence = fetchSequence(by: operation.sequenceId, context: context) {
                    do {
                        _ = try await APIService.shared.upsertSequences([sequence.toDTO()])
                        retryQueue.removePendingSequenceOperation(sequenceId: operation.sequenceId)
                    } catch {
                        retryQueue.incrementSequenceRetryCount(for: operation.sequenceId)
                    }
                } else {
                    retryQueue.removePendingSequenceOperation(sequenceId: operation.sequenceId)
                }

            case .delete:
                do {
                    _ = try await APIService.shared.deleteSequences([operation.sequenceId])
                    retryQueue.removePendingSequenceOperation(sequenceId: operation.sequenceId)
                } catch {
                    retryQueue.incrementSequenceRetryCount(for: operation.sequenceId)
                }
            }
        }
    }

    private func importSequencesFromBackend(_ dtos: [SequenceDTO]) async {
        guard let container = modelContainer else { return }
        let sendableDtos = dtos
        await Task.detached {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let existingSequences = (try? context.fetch(FetchDescriptor<WorkoutSequence>())) ?? []
            let existingById = Dictionary(uniqueKeysWithValues: existingSequences.map { ($0.id, $0) })

            for dto in sendableDtos {
                if dto.deleted == true {
                    if let existing = existingById[dto.sequenceId] {
                        existing.deleted = true
                    }
                    continue
                }

                if let existing = existingById[dto.sequenceId] {
                    existing.name = dto.name
                    existing.exerciseIds = dto.exerciseIds
                    existing.deleted = dto.deleted ?? false
                } else {
                    let sequence = WorkoutSequence(
                        id: dto.sequenceId,
                        name: dto.name,
                        exerciseIds: dto.exerciseIds,
                        createdAt: dto.createdDatetime ?? Date(),
                        createdTimezone: dto.createdTimezone,
                        deleted: dto.deleted ?? false
                    )
                    context.insert(sequence)
                }
            }

            try? context.save()
        }.value
    }

    private func fetchSequence(by id: UUID, context: ModelContext) -> WorkoutSequence? {
        let descriptor = FetchDescriptor<WorkoutSequence>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchAllSequences(context: ModelContext) -> [WorkoutSequence] {
        let descriptor = FetchDescriptor<WorkoutSequence>()
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Split Sync

    func syncSplitsFromBackend() async {
        guard let context = modelContext else { return }

        do {
            let response = try await APIService.shared.getSplits()
            await importSplitsFromBackend(response.splits)

            // Push any local-only splits
            let allLocal = fetchAllSplits(context: context)
            let backendIds = Set(response.splits.map { $0.splitId })
            let localOnly = allLocal.filter { !$0.deleted && !backendIds.contains($0.id) }

            if !localOnly.isEmpty {
                let dtos = localOnly.map { $0.toDTO() }
                do {
                    _ = try await APIService.shared.upsertSplits(dtos)
                } catch {
                    SyncLogger.sync.error("Failed to push local splits: \(error.localizedDescription)")
                    for split in localOnly {
                        retryQueue.addPendingSplitUpsert(splitId: split.id)
                    }
                }
            }

            SyncLogger.sync.info("Completed split sync, fetched \(response.splits.count) from backend")
        } catch {
            SyncLogger.sync.error("Failed to sync splits: \(error.localizedDescription)")
        }
    }

    func syncSplit(_ split: WorkoutSplit) async {
        let dto = split.toDTO()

        do {
            _ = try await APIService.shared.upsertSplits([dto])
            retryQueue.removePendingSplitOperation(splitId: split.id)
            SyncLogger.sync.debug("Synced split \(split.id)")
        } catch {
            SyncLogger.sync.error("Failed to sync split \(split.id): \(error.localizedDescription)")
            retryQueue.addPendingSplitUpsert(splitId: split.id)
        }
    }

    func deleteSplit(_ splitId: UUID) async {
        do {
            _ = try await APIService.shared.deleteSplits([splitId])
            retryQueue.removePendingSplitOperation(splitId: splitId)
            SyncLogger.sync.debug("Deleted split \(splitId)")
        } catch {
            SyncLogger.sync.error("Failed to delete split \(splitId): \(error.localizedDescription)")
            retryQueue.addPendingSplitDelete(splitId: splitId)
        }
    }

    func processSplitRetryQueue() async {
        guard let context = modelContext else { return }

        let pendingOperations = retryQueue.getPendingSplitOperations()

        for operation in pendingOperations {
            switch operation.operationType {
            case .upsert:
                if let split = fetchSplit(by: operation.splitId, context: context) {
                    do {
                        _ = try await APIService.shared.upsertSplits([split.toDTO()])
                        retryQueue.removePendingSplitOperation(splitId: operation.splitId)
                    } catch {
                        retryQueue.incrementSplitRetryCount(for: operation.splitId)
                    }
                } else {
                    retryQueue.removePendingSplitOperation(splitId: operation.splitId)
                }

            case .delete:
                do {
                    _ = try await APIService.shared.deleteSplits([operation.splitId])
                    retryQueue.removePendingSplitOperation(splitId: operation.splitId)
                } catch {
                    retryQueue.incrementSplitRetryCount(for: operation.splitId)
                }
            }
        }
    }

    private func importSplitsFromBackend(_ dtos: [SplitDTO]) async {
        guard let container = modelContainer else { return }
        let sendableDtos = dtos
        await Task.detached {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let existingSplits = (try? context.fetch(FetchDescriptor<WorkoutSplit>())) ?? []
            let existingById = Dictionary(uniqueKeysWithValues: existingSplits.map { ($0.id, $0) })

            for dto in sendableDtos {
                if dto.deleted == true {
                    if let existing = existingById[dto.splitId] {
                        existing.deleted = true
                    }
                    continue
                }

                if let existing = existingById[dto.splitId] {
                    existing.name = dto.name
                    existing.dayIds = dto.dayIds
                    existing.deleted = dto.deleted ?? false
                } else {
                    let split = WorkoutSplit(
                        id: dto.splitId,
                        name: dto.name,
                        dayIds: dto.dayIds,
                        createdAt: dto.createdDatetime ?? Date(),
                        createdTimezone: dto.createdTimezone,
                        deleted: dto.deleted ?? false
                    )
                    context.insert(split)
                }
            }

            try? context.save()
        }.value
    }

    private func fetchSplit(by id: UUID, context: ModelContext) -> WorkoutSplit? {
        let descriptor = FetchDescriptor<WorkoutSplit>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchAllSplits(context: ModelContext) -> [WorkoutSplit] {
        let descriptor = FetchDescriptor<WorkoutSplit>()
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
        for (name, loadType, movementType) in defaults {
            let icon = IconCarouselPicker.suggestedIcon(for: name)
            let exercise = Exercises(name: name, isCustom: false, loadType: loadType, movementType: movementType, icon: icon)
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
        do {
            let response = try await APIService.shared.getExercises()

            if response.exercises.isEmpty {
                return false
            } else {
                await importExercisesFromBackend(response.exercises)
                return true
            }
        } catch {
            SyncLogger.sync.error("Retry fetch exercises failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Helpers

    private func createAndSyncDefaultExercises(context: ModelContext) async {
        let defaults = getDefaultExercises()
        var exerciseDTOs: [ExerciseDTO] = []

        for (name, loadType, movementType) in defaults {
            let icon = IconCarouselPicker.suggestedIcon(for: name)
            let exercise = Exercises(name: name, isCustom: false, loadType: loadType, movementType: movementType, icon: icon)
            context.insert(exercise)
            exerciseDTOs.append(exercise.toDTO())
        }

        try? context.save()

        do {
            _ = try await APIService.shared.upsertExercises(exerciseDTOs)
        } catch {
            SyncLogger.sync.error("Failed to batch POST default exercises: \(error.localizedDescription)")
            for dto in exerciseDTOs {
                retryQueue.addPendingUpsert(exerciseId: dto.exerciseItemId)
            }
        }
    }

    private func importExercisesFromBackend(_ dtos: [ExerciseDTO]) async {
        guard let container = modelContainer else { return }
        let sendableDtos = dtos
        await Task.detached {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let existingExercises = (try? context.fetch(FetchDescriptor<Exercises>())) ?? []
            let existingById = Dictionary(uniqueKeysWithValues: existingExercises.map { ($0.id, $0) })

            for dto in sendableDtos {
                if dto.deleted == true {
                    if let existing = existingById[dto.exerciseItemId] {
                        existing.deleted = true
                    }
                    continue
                }

                if let existing = existingById[dto.exerciseItemId] {
                    existing.name = dto.name
                    existing.isCustom = dto.isCustom
                    existing.loadType = dto.loadType
                    existing.notes = dto.notes
                    existing.deleted = dto.deleted ?? false
                    existing.icon = dto.icon ?? "LiftTheBullIcon"
                    if let mt = dto.movementType {
                        existing.movementType = mt
                    }
                    if let seq = dto.setPlan {
                        existing.setPlan = seq
                    }
                } else {
                    let loadType = ExerciseLoadType(rawValue: dto.loadType) ?? .barbell
                    let movementType = ExerciseMovementType(rawValue: dto.movementType ?? "") ?? .other
                    let exercise = Exercises(
                        id: dto.exerciseItemId,
                        name: dto.name,
                        isCustom: dto.isCustom,
                        loadType: loadType,
                        movementType: movementType,
                        createdAt: dto.createdDatetime ?? Date(),
                        createdTimezone: dto.createdTimezone,
                        notes: dto.notes,
                        deleted: dto.deleted ?? false,
                        icon: dto.icon ?? "LiftTheBullIcon"
                    )
                    if let seq = dto.setPlan {
                        exercise.setPlan = seq
                    }
                    context.insert(exercise)
                }
            }

            try? context.save()
        }.value
    }

    private func getDefaultExercises() -> [(String, ExerciseLoadType, ExerciseMovementType)] {
        return [
            ("Deadlift", .barbell, .hinge),
            ("Squat", .barbell, .squat),
            ("Bench Press", .barbell, .push),
            ("Overhead Press", .barbell, .push),
            ("Barbell Row", .barbell, .pull),
            ("Pull Ups", .bodySingleLoad, .pull),
            ("Dips", .bodySingleLoad, .push),
            ("Barbell Curls", .barbell, .pull)
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
        SyncLogger.sync.info("Clearing sync state on logout")
        retryQueue.clearAll()
        UserDefaults.standard.removeObject(forKey: Self.syncStateKey)
    }
}
