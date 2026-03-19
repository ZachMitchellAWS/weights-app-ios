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
    @Published var isSyncingLiftSet = false
    @Published var liftSetSyncProgress: String?
    @Published var isSyncingEstimated1RM = false
    @Published var estimated1RMSyncProgress: String?

    // MARK: - Persisted Sync State

    struct SyncState: Codable {
        var syncComplete: Bool = false

        // Per-step completion
        var userPropertiesComplete: Bool = false
        var exercisesComplete: Bool = false
        var templatesComplete: Bool = false
        var groupsComplete: Bool = false
        var liftSetsComplete: Bool = false
        var estimated1RMsComplete: Bool = false
        var accessoryGoalCheckinsComplete: Bool = false

        // Pagination cursors (nil = start from beginning)
        var liftSetPageToken: String? = nil
        var estimated1RMPageToken: String? = nil
        var accessoryGoalCheckinPageToken: String? = nil

        // Running totals for progress display on resume
        var liftSetsFetched: Int = 0
        var estimated1RMsFetched: Int = 0
        var accessoryGoalCheckinsFetched: Int = 0
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
                SyncLogger.sync.info("[DEBUG] getExercises returned \(response.exercises.count) exercise(s)")

                if response.exercises.isEmpty {
                    SyncLogger.sync.info("No exercises on backend, creating defaults")
                    await createAndSyncDefaultExercises(context: context)
                } else {
                    SyncLogger.sync.info("Importing \(response.exercises.count) exercises from backend")
                    let deletedCount = response.exercises.filter { $0.deleted == true }.count
                    if deletedCount > 0 {
                        SyncLogger.sync.info("[DEBUG] \(deletedCount) of \(response.exercises.count) exercises are marked deleted")
                    }
                    await importExercisesFromBackend(response.exercises)
                }

                await processRetryQueue()
                state.exercisesComplete = true
                syncState = state
            } catch {
                SyncLogger.sync.error("Initial exercise sync failed: \(error)")
            }
        } else {
            SyncLogger.sync.debug("Step 2: Exercise already synced, skipping")
        }


        // Step 2.7: Sync set plan templates
        if !state.templatesComplete {
            SyncLogger.sync.info("Step 2.7: Syncing set plan templates")
            let backendTemplateCount = await syncSetPlansFromBackend()
            await processTemplateRetryQueue()
            state.templatesComplete = true
            syncState = state

            // Seed only if backend had nothing (new user)
            if backendTemplateCount == 0, let ctx = modelContext {
                SyncLogger.sync.info("No set plans on backend, creating defaults")
                await createAndSyncDefaultSetPlans(context: ctx)
            }
        } else {
            SyncLogger.sync.debug("Step 2.7: Templates already synced, skipping")
        }

        // Step 2.8: Sync groups
        if !state.groupsComplete {
            SyncLogger.sync.info("Step 2.8: Syncing groups")
            let backendGroupCount = await syncGroupsFromBackend()
            await processGroupRetryQueue()
            state.groupsComplete = true
            syncState = state

            // Seed only if backend had nothing (new user)
            if backendGroupCount == 0, let ctx = modelContext {
                SyncLogger.sync.info("No groups on backend, creating defaults")
                await createAndSyncDefaultGroups(context: ctx)
            }
        } else {
            SyncLogger.sync.debug("Step 2.8: Groups already synced, skipping")
        }

        // Step 3: Sync lift sets and estimated 1RMs (interleaved, resumable)
        if !state.liftSetsComplete || !state.estimated1RMsComplete {
            SyncLogger.sync.info("Step 3: Syncing lift sets and estimated 1RMs")
            await syncLiftSetsAndEstimated1RM(resumeState: &state)
        } else {
            SyncLogger.sync.debug("Step 3: Lift sets and E1RMs already synced, skipping")
        }

        await processLiftSetRetryQueue()
        await processEstimated1RMRetryQueue()

        // Step 4: Sync accessory goal checkins
        if !state.accessoryGoalCheckinsComplete {
            SyncLogger.sync.info("Step 4: Syncing accessory goal checkins")
            await syncAccessoryGoalCheckinsFromBackend(resumeState: &state)
            state.accessoryGoalCheckinsComplete = true
            syncState = state
        } else {
            SyncLogger.sync.debug("Step 4: Accessory goal checkins already synced, skipping")
        }

        await processAccessoryGoalCheckinRetryQueue()

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
            if let activeSetPlanId = response.activeSetPlanId {
                userProperties.activeSetPlanId = UUID(uuidString: activeSetPlanId)
            }
            if let activeGroupId = response.activeGroupId {
                userProperties.activeGroupId = UUID(uuidString: activeGroupId)
            }
            if let stepsGoal = response.stepsGoal {
                userProperties.stepsGoal = stepsGoal
            }
            if let proteinGoal = response.proteinGoal {
                userProperties.proteinGoal = proteinGoal
            }
            if let bodyweightTarget = response.bodyweightTarget {
                userProperties.bodyweightTarget = bodyweightTarget
            }
            if let timezone = response.timezone {
                userProperties.timezoneIdentifier = timezone
            }
            userProperties.biologicalSex = response.biologicalSex

            try? context.save()

            // Also save createdDatetime to keychain
            KeychainService.shared.saveUserProperties(createdDatetime: response.createdDatetime)
        } catch {
            SyncLogger.sync.error("Failed to sync user properties: \(error.localizedDescription)")
            // Don't block exercise sync - user properties are not critical
        }
    }

    func syncTimezoneIfNeeded() async {
        guard let context = modelContext else {
            SyncLogger.sync.warning("syncTimezoneIfNeeded: no modelContext")
            return
        }
        let currentTz = TimeZone.current.identifier
        let userProperties = fetchOrCreateUserProperties(context: context)

        // Only send if different from what we have locally
        guard userProperties.timezoneIdentifier != currentTz else {
            SyncLogger.sync.debug("syncTimezoneIfNeeded: already up to date (\(currentTz))")
            return
        }

        SyncLogger.sync.info("syncTimezoneIfNeeded: updating \(userProperties.timezoneIdentifier ?? "nil") → \(currentTz)")
        do {
            let request = UserPropertiesRequest(timezone: currentTz)
            _ = try await APIService.shared.updateUserProperties(request)
            userProperties.timezoneIdentifier = currentTz
            try? context.save()
            SyncLogger.sync.info("syncTimezoneIfNeeded: success")
        } catch {
            SyncLogger.sync.error("Failed to sync timezone: \(error.localizedDescription)")
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

    func updateBiologicalSex(_ sex: String?) async {
        do {
            var request = UserPropertiesRequest()
            if let sex = sex {
                request.biologicalSex = sex
            } else {
                request.clearBiologicalSex = true
            }
            _ = try await APIService.shared.updateUserProperties(request)
            retryQueue.removePendingUserPropertiesSync()
        } catch {
            SyncLogger.sync.error("Failed to update biological sex: \(error.localizedDescription)")
            retryQueue.addPendingUserPropertiesSync()
        }
    }

    func updateAllRepRanges(minReps: Int, maxReps: Int, easyMinReps: Int, easyMaxReps: Int, moderateMinReps: Int, moderateMaxReps: Int, hardMinReps: Int, hardMaxReps: Int) async {
        do {
            let request = UserPropertiesRequest(
                minReps: minReps,
                maxReps: maxReps,
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
            SyncLogger.sync.error("Failed to update rep ranges: \(error.localizedDescription)")
            retryQueue.addPendingUserPropertiesSync()
        }
    }

    func updateActiveSetPlan(_ templateId: UUID?) async {
        do {
            var request = UserPropertiesRequest()
            if let templateId = templateId {
                request.activeSetPlanId = templateId.uuidString
            } else {
                request.clearActiveSetPlan = true
            }
            _ = try await APIService.shared.updateUserProperties(request)
            retryQueue.removePendingUserPropertiesSync()
        } catch {
            SyncLogger.sync.error("Failed to update active set plan template: \(error.localizedDescription)")
            retryQueue.addPendingUserPropertiesSync()
        }
    }

    func updateActiveGroup(_ groupId: UUID?) async {
        do {
            var request = UserPropertiesRequest()
            if let groupId = groupId {
                request.activeGroupId = groupId.uuidString
            } else {
                request.clearActiveGroupId = true
            }
            _ = try await APIService.shared.updateUserProperties(request)
            retryQueue.removePendingUserPropertiesSync()
        } catch {
            SyncLogger.sync.error("Failed to update active group: \(error.localizedDescription)")
            retryQueue.addPendingUserPropertiesSync()
        }
    }


    func processUserPropertiesRetryQueue() async {
        guard let context = modelContext else { return }
        guard retryQueue.hasUserPropertiesPending() else { return }

        let userProperties = fetchOrCreateUserProperties(context: context)

        do {
            var request = UserPropertiesRequest(
                bodyweight: userProperties.bodyweight,
                availableChangePlates: userProperties.availableChangePlates,
                minReps: userProperties.minReps,
                maxReps: userProperties.maxReps,
                easyMinReps: userProperties.easyMinReps,
                easyMaxReps: userProperties.easyMaxReps,
                moderateMinReps: userProperties.moderateMinReps,
                moderateMaxReps: userProperties.moderateMaxReps,
                hardMinReps: userProperties.hardMinReps,
                hardMaxReps: userProperties.hardMaxReps,
                timezone: userProperties.timezoneIdentifier
            )
            if let templateId = userProperties.activeSetPlanId {
                request.activeSetPlanId = templateId.uuidString
            } else {
                request.clearActiveSetPlan = true
            }
            if let groupId = userProperties.activeGroupId {
                request.activeGroupId = groupId.uuidString
            } else {
                request.clearActiveGroupId = true
            }
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

    func syncExercise(_ exercise: Exercise) async {
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
    func syncLiftSetsAndEstimated1RM() async {
        var state = syncState
        // Reset lift set / E1RM state for a fresh full sync
        state.liftSetsComplete = false
        state.estimated1RMsComplete = false
        state.liftSetPageToken = nil
        state.estimated1RMPageToken = nil
        state.liftSetsFetched = 0
        state.estimated1RMsFetched = 0
        await syncLiftSetsAndEstimated1RM(resumeState: &state)
        state.syncComplete = true
        syncState = state
    }

    /// Resumable version that persists pagination state after each page.
    /// Runs all SwiftData work in a single background context to avoid repeated full-table scans
    /// and minimizes saves to reduce @Query-triggered UI refreshes.
    private func syncLiftSetsAndEstimated1RM(resumeState state: inout SyncState) async {
        guard let container = modelContainer else { return }

        isSyncingLiftSet = true
        liftSetSyncProgress = "Syncing..."

        var totalLiftSet = state.liftSetsFetched
        var totalE1RMs = state.estimated1RMsFetched
        var liftSetsDone = state.liftSetsComplete
        var e1rmsDone = state.estimated1RMsComplete
        var liftSetPageToken = state.liftSetPageToken
        var e1rmPageToken = state.estimated1RMPageToken

        do {
            // Run the entire paginated sync in a single background context
            let (finalLiftSet, finalE1RMs, finalLSDone, finalE1RMDone, finalLSToken, finalE1RMToken) = try await Task.detached {
                let context = ModelContext(container)
                context.autosaveEnabled = false

                // Build dedup dictionaries once upfront
                let existingLiftSet = (try? context.fetch(FetchDescriptor<LiftSet>())) ?? []
                var liftSetById = Dictionary(uniqueKeysWithValues: existingLiftSet.map { ($0.id, $0) })

                let existingE1RMs = (try? context.fetch(FetchDescriptor<Estimated1RM>())) ?? []
                var e1rmById = Dictionary(uniqueKeysWithValues: existingE1RMs.map { ($0.id, $0) })

                // Cache exercise lookup
                let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
                let exerciseById = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })

                var tLS = totalLiftSet
                var tE1RM = totalE1RMs
                var lsDone = liftSetsDone
                var e1rmDone = e1rmsDone
                var lsToken = liftSetPageToken
                var e1rmToken = e1rmPageToken
                var pagesSinceSave = 0

                while !lsDone || !e1rmDone {
                    // Fetch one page of lift sets
                    if !lsDone {
                        let response = try await APIService.shared.getLiftSet(limit: 500, pageToken: lsToken)
                        tLS += response.count

                        for dto in response.liftSets {
                            if let existing = liftSetById[dto.liftSetId] {
                                existing.reps = dto.reps
                                existing.weight = dto.weight
                                existing.createdTimezone = dto.createdTimezone
                                existing.createdAt = dto.createdDatetime
                                existing.isBaselineSet = dto.isBaselineSet ?? false
                            } else if let exercise = exerciseById[dto.exerciseId] {
                                let liftSet = LiftSet(exercise: exercise, reps: dto.reps, weight: dto.weight)
                                liftSet.id = dto.liftSetId
                                liftSet.createdTimezone = dto.createdTimezone
                                liftSet.createdAt = dto.createdDatetime
                                liftSet.isBaselineSet = dto.isBaselineSet ?? false
                                context.insert(liftSet)
                                liftSetById[dto.liftSetId] = liftSet
                            }
                        }

                        lsToken = response.hasMore ? response.nextPageToken : nil
                        lsDone = !response.hasMore
                    }

                    // Fetch one page of estimated 1RMs
                    if !e1rmDone {
                        let response = try await APIService.shared.getEstimated1RM(limit: 500, pageToken: e1rmToken)
                        tE1RM += response.count

                        for dto in response.estimated1RMs {
                            if let existing = e1rmById[dto.estimated1RMId] {
                                existing.value = dto.value
                                existing.setId = dto.liftSetId
                                existing.createdTimezone = dto.createdTimezone
                                existing.createdAt = dto.createdDatetime
                            } else if let exercise = exerciseById[dto.exerciseId] {
                                let estimated1RM = Estimated1RM(exercise: exercise, value: dto.value, setId: dto.liftSetId)
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

            totalLiftSet = finalLiftSet
            totalE1RMs = finalE1RMs
            liftSetsDone = finalLSDone
            e1rmsDone = finalE1RMDone
            liftSetPageToken = finalLSToken
            e1rmPageToken = finalE1RMToken

            SyncLogger.sync.info("Completed interleaved sync: \(totalLiftSet) lift sets + \(totalE1RMs) estimated 1RMs")
        } catch {
            SyncLogger.sync.error("Failed during interleaved sync: \(error.localizedDescription)")
        }

        // Persist final state
        state.liftSetPageToken = liftSetPageToken
        state.estimated1RMPageToken = e1rmPageToken
        state.liftSetsFetched = totalLiftSet
        state.estimated1RMsFetched = totalE1RMs
        state.liftSetsComplete = liftSetsDone
        state.estimated1RMsComplete = e1rmsDone
        syncState = state

        isSyncingLiftSet = false
        liftSetSyncProgress = nil
    }

    // MARK: - Lift Set Sync

    /// Fetches all lift sets from backend using pagination and imports them locally
    func syncLiftSetsFromBackend() async {
        isSyncingLiftSet = true
        liftSetSyncProgress = "Syncing..."

        var pageToken: String? = nil
        var totalFetched = 0

        do {
            repeat {
                let response = try await APIService.shared.getLiftSet(limit: 500, pageToken: pageToken)
                totalFetched += response.count

                await importLiftSetsFromBackend(response.liftSets)

                liftSetSyncProgress = "Synced \(totalFetched) sets..."
                pageToken = response.hasMore ? response.nextPageToken : nil

            } while pageToken != nil

            SyncLogger.sync.info("Completed lift set sync, fetched \(totalFetched) total")
        } catch {
            SyncLogger.sync.error("Failed to sync lift sets: \(error.localizedDescription)")
        }

        isSyncingLiftSet = false
        liftSetSyncProgress = nil
    }

    /// Syncs a single lift set to the backend (for new creations)
    func syncLiftSet(_ liftSet: LiftSet, isPremiumOnClient: Bool = false) async {
        let dto = liftSet.toDTO()

        do {
            _ = try await APIService.shared.createLiftSet([dto], isPremiumOnClient: isPremiumOnClient)
            retryQueue.removePendingLiftSetOperation(liftSetId: liftSet.id)
            SyncLogger.sync.debug("Synced lift set \(liftSet.id)")
        } catch {
            SyncLogger.sync.error("Failed to sync lift set \(liftSet.id): \(error.localizedDescription)")
            retryQueue.addPendingLiftSetCreate(liftSetId: liftSet.id)
        }
    }

    /// Syncs multiple lift sets to the backend (batch create)
    func syncLiftSet(_ liftSets: [LiftSet], isPremiumOnClient: Bool = false) async {
        guard !liftSets.isEmpty else { return }

        let dtos = liftSets.map { $0.toDTO() }

        do {
            _ = try await APIService.shared.createLiftSet(dtos, isPremiumOnClient: isPremiumOnClient)
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
            _ = try await APIService.shared.deleteLiftSet([liftSetId])
            retryQueue.removePendingLiftSetOperation(liftSetId: liftSetId)
            SyncLogger.sync.debug("Deleted lift set \(liftSetId)")
        } catch {
            SyncLogger.sync.error("Failed to delete lift set \(liftSetId): \(error.localizedDescription)")
            retryQueue.addPendingLiftSetDelete(liftSetId: liftSetId)
        }
    }

    /// Deletes multiple lift sets from the backend (batch delete)
    func deleteLiftSet(_ liftSetIds: [UUID]) async {
        guard !liftSetIds.isEmpty else { return }

        do {
            _ = try await APIService.shared.deleteLiftSet(liftSetIds)
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
                        _ = try await APIService.shared.createLiftSet([liftSet.toDTO()])
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
                    _ = try await APIService.shared.deleteLiftSet([operation.liftSetId])
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

            let existingLiftSet = (try? context.fetch(FetchDescriptor<LiftSet>())) ?? []
            let existingById = Dictionary(uniqueKeysWithValues: existingLiftSet.map { ($0.id, $0) })

            for dto in sendableDtos {
                if let existing = existingById[dto.liftSetId] {
                    existing.reps = dto.reps
                    existing.weight = dto.weight
                    existing.createdTimezone = dto.createdTimezone
                    existing.createdAt = dto.createdDatetime
                    existing.isBaselineSet = dto.isBaselineSet ?? false
                } else {
                    let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == dto.exerciseId })
                    if let exercise = try? context.fetch(descriptor).first {
                        let liftSet = LiftSet(exercise: exercise, reps: dto.reps, weight: dto.weight)
                        liftSet.id = dto.liftSetId
                        liftSet.createdTimezone = dto.createdTimezone
                        liftSet.createdAt = dto.createdDatetime
                        liftSet.isBaselineSet = dto.isBaselineSet ?? false
                        context.insert(liftSet)
                    } else {
                        SyncLogger.sync.debug("Skipping lift set \(dto.liftSetId) — exercise \(dto.exerciseId) not found")
                    }
                }
            }

            try? context.save()
        }.value
    }

    private func fetchLiftSet(by id: UUID, context: ModelContext) -> LiftSet? {
        let descriptor = FetchDescriptor<LiftSet>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Estimated 1RM Sync

    /// Fetches all estimated 1RMs from backend using pagination and imports them locally
    func syncEstimated1RMFromBackend() async {
        isSyncingEstimated1RM = true
        estimated1RMSyncProgress = "Syncing..."

        var pageToken: String? = nil
        var totalFetched = 0

        do {
            repeat {
                let response = try await APIService.shared.getEstimated1RM(limit: 500, pageToken: pageToken)
                totalFetched += response.count

                await importEstimated1RMFromBackend(response.estimated1RMs)

                estimated1RMSyncProgress = "Synced \(totalFetched) estimated 1RMs..."
                pageToken = response.hasMore ? response.nextPageToken : nil

            } while pageToken != nil

            SyncLogger.sync.info("Completed estimated 1RM sync, fetched \(totalFetched) total")
        } catch {
            SyncLogger.sync.error("Failed to sync estimated 1RMs: \(error.localizedDescription)")
        }

        isSyncingEstimated1RM = false
        estimated1RMSyncProgress = nil
    }

    /// Syncs a single estimated 1RM to the backend (for new creations)
    func syncEstimated1RM(_ estimated1RM: Estimated1RM) async {
        let dto = estimated1RM.toDTO()

        do {
            _ = try await APIService.shared.createEstimated1RM([dto])
            retryQueue.removePendingEstimated1RMOperation(estimated1RMId: estimated1RM.id)
            SyncLogger.sync.debug("Synced estimated 1RM \(estimated1RM.id)")
        } catch {
            SyncLogger.sync.error("Failed to sync estimated 1RM \(estimated1RM.id): \(error.localizedDescription)")
            retryQueue.addPendingEstimated1RMCreate(estimated1RMId: estimated1RM.id, liftSetId: estimated1RM.setId)
        }
    }

    /// Syncs multiple estimated 1RMs to the backend (batch create)
    func syncEstimated1RM(_ estimated1RMs: [Estimated1RM]) async {
        guard !estimated1RMs.isEmpty else { return }

        let dtos = estimated1RMs.map { $0.toDTO() }

        do {
            _ = try await APIService.shared.createEstimated1RM(dtos)
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
            _ = try await APIService.shared.deleteEstimated1RM(liftSetIds: [liftSetId])
            retryQueue.removePendingEstimated1RMOperation(estimated1RMId: estimated1RMId)
            SyncLogger.sync.debug("Deleted estimated 1RM \(estimated1RMId)")
        } catch {
            SyncLogger.sync.error("Failed to delete estimated 1RM \(estimated1RMId): \(error.localizedDescription)")
            retryQueue.addPendingEstimated1RMDelete(estimated1RMId: estimated1RMId, liftSetId: liftSetId)
        }
    }

    /// Deletes multiple estimated 1RMs from the backend (batch delete using liftSetIds)
    func deleteEstimated1RM(liftSetIds: [UUID]) async {
        guard !liftSetIds.isEmpty else { return }

        do {
            _ = try await APIService.shared.deleteEstimated1RM(liftSetIds: liftSetIds)
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
                        _ = try await APIService.shared.createEstimated1RM([estimated1RM.toDTO()])
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
                    _ = try await APIService.shared.deleteEstimated1RM(liftSetIds: [operation.liftSetId])
                    retryQueue.removePendingEstimated1RMOperation(estimated1RMId: operation.estimated1RMId)
                } catch {
                    retryQueue.incrementEstimated1RMRetryCount(for: operation.estimated1RMId)
                }
            }
        }
    }

    private func importEstimated1RMFromBackend(_ dtos: [Estimated1RMDTO]) async {
        guard let container = modelContainer else { return }
        let sendableDtos = dtos
        await Task.detached {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let existingEstimated1RM = (try? context.fetch(FetchDescriptor<Estimated1RM>())) ?? []
            let existingById = Dictionary(uniqueKeysWithValues: existingEstimated1RM.map { ($0.id, $0) })

            for dto in sendableDtos {
                if let existing = existingById[dto.estimated1RMId] {
                    existing.value = dto.value
                    existing.setId = dto.liftSetId
                    existing.createdTimezone = dto.createdTimezone
                    existing.createdAt = dto.createdDatetime
                } else {
                    let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == dto.exerciseId })
                    if let exercise = try? context.fetch(descriptor).first {
                        let estimated1RM = Estimated1RM(exercise: exercise, value: dto.value, setId: dto.liftSetId)
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

    private func fetchEstimated1RM(by id: UUID, context: ModelContext) -> Estimated1RM? {
        let descriptor = FetchDescriptor<Estimated1RM>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }


    // MARK: - Set Plan Template Sync

    func syncSetPlansFromBackend() async -> Int {
        guard let context = modelContext else { return 0 }

        do {
            let response = try await APIService.shared.getSetPlans()
            await importSetPlansFromBackend(response.templates)

            // Push any local-only templates (including built-ins) to backend
            let allLocal = fetchAllTemplates(context: context)
            let backendIds = Set(response.templates.map { $0.templateId })
            let localOnly = allLocal.filter { !$0.deleted && !backendIds.contains($0.id) }

            if !localOnly.isEmpty {
                let dtos = localOnly.map { $0.toDTO() }
                do {
                    _ = try await APIService.shared.upsertSetPlans(dtos)
                } catch {
                    SyncLogger.sync.error("Failed to push local templates: \(error.localizedDescription)")
                    for template in localOnly {
                        retryQueue.addPendingTemplateUpsert(templateId: template.id)
                    }
                }
            }

            SyncLogger.sync.info("Completed template sync, fetched \(response.templates.count) from backend")
            return response.templates.count
        } catch {
            SyncLogger.sync.error("Failed to sync templates: \(error.localizedDescription)")
            return 0
        }
    }

    func syncSetPlan(_ template: SetPlan) async {
        let dto = template.toDTO()

        do {
            _ = try await APIService.shared.upsertSetPlans([dto])
            retryQueue.removePendingTemplateOperation(templateId: template.id)
            SyncLogger.sync.debug("Synced template \(template.id)")
        } catch {
            SyncLogger.sync.error("Failed to sync template \(template.id): \(error.localizedDescription)")
            retryQueue.addPendingTemplateUpsert(templateId: template.id)
        }
    }

    func deleteSetPlan(_ templateId: UUID) async {
        do {
            _ = try await APIService.shared.deleteSetPlans([templateId])
            retryQueue.removePendingTemplateOperation(templateId: templateId)
            SyncLogger.sync.debug("Deleted template \(templateId)")
        } catch {
            SyncLogger.sync.error("Failed to delete template \(templateId): \(error.localizedDescription)")
            retryQueue.addPendingTemplateDelete(templateId: templateId)
        }
    }

    func processTemplateRetryQueue() async {
        guard let context = modelContext else { return }

        let pendingOperations = retryQueue.getPendingTemplateOperations()

        for operation in pendingOperations {
            switch operation.operationType {
            case .upsert:
                if let template = fetchTemplate(by: operation.templateId, context: context) {
                    do {
                        _ = try await APIService.shared.upsertSetPlans([template.toDTO()])
                        retryQueue.removePendingTemplateOperation(templateId: operation.templateId)
                    } catch {
                        retryQueue.incrementTemplateRetryCount(for: operation.templateId)
                    }
                } else {
                    retryQueue.removePendingTemplateOperation(templateId: operation.templateId)
                }

            case .delete:
                do {
                    _ = try await APIService.shared.deleteSetPlans([operation.templateId])
                    retryQueue.removePendingTemplateOperation(templateId: operation.templateId)
                } catch {
                    retryQueue.incrementTemplateRetryCount(for: operation.templateId)
                }
            }
        }
    }

    private func importSetPlansFromBackend(_ dtos: [SetPlanDTO]) async {
        guard let container = modelContainer else { return }
        let sendableDtos = dtos
        await Task.detached {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let existingTemplates = (try? context.fetch(FetchDescriptor<SetPlan>())) ?? []
            let existingById = Dictionary(uniqueKeysWithValues: existingTemplates.map { ($0.id, $0) })

            for dto in sendableDtos {
                if dto.deleted == true {
                    if let existing = existingById[dto.templateId] {
                        existing.deleted = true
                    }
                    continue
                }

                if let existing = existingById[dto.templateId] {
                    existing.name = dto.name
                    existing.effortSequence = dto.effortSequence
                    existing.isCustom = dto.isCustom
                    existing.templateDescription = dto.templateDescription
                    existing.deleted = dto.deleted ?? false
                } else {
                    let template = SetPlan(
                        id: dto.templateId,
                        name: dto.name,
                        effortSequence: dto.effortSequence,
                        isCustom: dto.isCustom,
                        templateDescription: dto.templateDescription,
                        createdAt: dto.createdDatetime ?? Date(),
                        createdTimezone: dto.createdTimezone,
                        deleted: dto.deleted ?? false
                    )
                    context.insert(template)
                }
            }

            try? context.save()
        }.value
    }

    private func fetchTemplate(by id: UUID, context: ModelContext) -> SetPlan? {
        let descriptor = FetchDescriptor<SetPlan>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchAllTemplates(context: ModelContext) -> [SetPlan] {
        let descriptor = FetchDescriptor<SetPlan>()
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Groups Sync

    func syncGroupsFromBackend() async -> Int {
        guard let context = modelContext else { return 0 }

        do {
            let response = try await APIService.shared.getGroups()
            await importGroupsFromBackend(response.groups)

            // Push any local-only groups to backend
            let allLocal = fetchAllGroups(context: context)
            let backendIds = Set(response.groups.map { $0.groupId })
            let localOnly = allLocal.filter { !$0.deleted && !backendIds.contains($0.groupId) }

            if !localOnly.isEmpty {
                let dtos = localOnly.map { $0.toDTO() }
                do {
                    _ = try await APIService.shared.upsertGroups(dtos)
                } catch {
                    SyncLogger.sync.error("Failed to push local groups: \(error.localizedDescription)")
                    for group in localOnly {
                        retryQueue.addPendingGroupUpsert(groupId: group.groupId)
                    }
                }
            }

            SyncLogger.sync.info("Completed group sync, fetched \(response.groups.count) from backend")
            return response.groups.count
        } catch {
            SyncLogger.sync.error("Failed to sync groups: \(error.localizedDescription)")
            return 0
        }
    }

    func syncGroup(_ group: ExerciseGroup) async {
        let dto = group.toDTO()

        do {
            _ = try await APIService.shared.upsertGroups([dto])
            retryQueue.removePendingGroupOperation(groupId: group.groupId)
            SyncLogger.sync.debug("Synced group \(group.groupId)")
        } catch {
            SyncLogger.sync.error("Failed to sync group \(group.groupId): \(error.localizedDescription)")
            retryQueue.addPendingGroupUpsert(groupId: group.groupId)
        }
    }

    func deleteGroup(_ groupId: UUID) async {
        do {
            _ = try await APIService.shared.deleteGroups([groupId])
            retryQueue.removePendingGroupOperation(groupId: groupId)
            SyncLogger.sync.debug("Deleted group \(groupId)")
        } catch {
            SyncLogger.sync.error("Failed to delete group \(groupId): \(error.localizedDescription)")
            retryQueue.addPendingGroupDelete(groupId: groupId)
        }
    }

    func processGroupRetryQueue() async {
        guard let context = modelContext else { return }

        let pendingOperations = retryQueue.getPendingGroupOperations()

        for operation in pendingOperations {
            switch operation.operationType {
            case .upsert:
                if let group = fetchGroup(by: operation.groupId, context: context) {
                    do {
                        _ = try await APIService.shared.upsertGroups([group.toDTO()])
                        retryQueue.removePendingGroupOperation(groupId: operation.groupId)
                    } catch {
                        retryQueue.incrementGroupRetryCount(for: operation.groupId)
                    }
                } else {
                    retryQueue.removePendingGroupOperation(groupId: operation.groupId)
                }

            case .delete:
                do {
                    _ = try await APIService.shared.deleteGroups([operation.groupId])
                    retryQueue.removePendingGroupOperation(groupId: operation.groupId)
                } catch {
                    retryQueue.incrementGroupRetryCount(for: operation.groupId)
                }
            }
        }
    }

    private func importGroupsFromBackend(_ dtos: [GroupDTO]) async {
        guard let container = modelContainer else { return }
        let sendableDtos = dtos
        await Task.detached {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let existingGroups = (try? context.fetch(FetchDescriptor<ExerciseGroup>())) ?? []
            let existingById = Dictionary(uniqueKeysWithValues: existingGroups.map { ($0.groupId, $0) })

            for dto in sendableDtos {
                if dto.deleted == true {
                    if let existing = existingById[dto.groupId] {
                        existing.deleted = true
                    }
                    continue
                }

                if let existing = existingById[dto.groupId] {
                    existing.name = dto.name
                    existing.exerciseIds = dto.exerciseIds
                    existing.isCustom = dto.isCustom
                    existing.sortOrder = dto.sortOrder
                    existing.deleted = dto.deleted ?? false
                    if let lastModified = dto.lastModifiedDatetime {
                        existing.lastModifiedDatetime = lastModified
                    }
                } else {
                    let group = ExerciseGroup(
                        groupId: dto.groupId,
                        name: dto.name,
                        exerciseIds: dto.exerciseIds,
                        sortOrder: dto.sortOrder,
                        isCustom: dto.isCustom,
                        createdAt: dto.createdDatetime ?? Date(),
                        createdTimezone: dto.createdTimezone,
                        lastModifiedDatetime: dto.lastModifiedDatetime ?? Date(),
                        deleted: dto.deleted ?? false
                    )
                    context.insert(group)
                }
            }

            try? context.save()
        }.value
    }

    private func fetchGroup(by id: UUID, context: ModelContext) -> ExerciseGroup? {
        let descriptor = FetchDescriptor<ExerciseGroup>(predicate: #Predicate { $0.groupId == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchAllGroups(context: ModelContext) -> [ExerciseGroup] {
        let descriptor = FetchDescriptor<ExerciseGroup>()
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    private func createAndSyncDefaultGroups(context: ModelContext) async {
        SeedService.seedGroups(context: context)
        let allGroups = fetchAllGroups(context: context)
        let dtos = allGroups.filter { !$0.deleted }.map { $0.toDTO() }
        if !dtos.isEmpty {
            do {
                _ = try await APIService.shared.upsertGroups(dtos)
            } catch {
                SyncLogger.sync.error("Failed to push default groups: \(error.localizedDescription)")
                for group in allGroups where !group.deleted {
                    retryQueue.addPendingGroupUpsert(groupId: group.groupId)
                }
            }
        }
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

    // MARK: - Fallback: Create Default Exercise

    func createDefaultExercisesLocally() async {
        guard let context = modelContext else { return }
        _ = SeedService.seedExercises(context: context)
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
        var exerciseDTOs: [ExerciseDTO] = []

        for def in Exercise.builtInTemplates {
            let exercise = Exercise(
                id: def.id,
                name: def.name,
                isCustom: false,
                loadType: def.loadType,
                movementType: def.movementType,
                icon: def.icon
            )
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


    private func createAndSyncDefaultSetPlans(context: ModelContext) async {
        var dtos: [SetPlanDTO] = []
        for def in SetPlan.builtInTemplates {
            let template = SetPlan(
                id: def.id,
                name: def.name,
                effortSequence: def.sequence,
                isCustom: false,
                templateDescription: def.description
            )
            context.insert(template)
            dtos.append(template.toDTO())
        }
        try? context.save()

        // Set default active set plan if none
        if let userProps = try? context.fetch(FetchDescriptor<UserProperties>()).first,
           userProps.activeSetPlanId == nil {
            userProps.activeSetPlanId = SetPlan.standardId
            try? context.save()
            Task { await SyncService.shared.updateActiveSetPlan(SetPlan.standardId) }
        }

        // Push to backend
        do {
            _ = try await APIService.shared.upsertSetPlans(dtos)
        } catch {
            SyncLogger.sync.error("Failed to batch POST default set plans: \(error.localizedDescription)")
            for dto in dtos {
                retryQueue.addPendingTemplateUpsert(templateId: dto.templateId)
            }
        }
    }


    // MARK: - Fallback: Set Plans

    func retryFetchSetPlans() async -> Bool {
        do {
            let response = try await APIService.shared.getSetPlans()
            if response.templates.isEmpty {
                return false
            } else {
                await importSetPlansFromBackend(response.templates)
                return true
            }
        } catch {
            SyncLogger.sync.error("Retry fetch set plans failed: \(error.localizedDescription)")
            return false
        }
    }

    func createDefaultSetPlansAndSync() async {
        guard let context = modelContext else { return }
        let existingPlans = fetchAllTemplates(context: context).filter { !$0.deleted }
        guard existingPlans.isEmpty else { return }
        await createAndSyncDefaultSetPlans(context: context)
    }

    private func importExercisesFromBackend(_ dtos: [ExerciseDTO]) async {
        guard let container = modelContainer else { return }
        let sendableDtos = dtos
        await Task.detached {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let existingExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
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
                    existing.weightIncrement = dto.weightIncrement
                    existing.barbellWeight = dto.barbellWeight
                } else {
                    let loadType = ExerciseLoadType(rawValue: dto.loadType) ?? .barbell
                    let movementType = ExerciseMovementType(rawValue: dto.movementType ?? "") ?? .other
                    let exercise = Exercise(
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
                    context.insert(exercise)
                    exercise.weightIncrement = dto.weightIncrement
                    exercise.barbellWeight = dto.barbellWeight
                }
            }

            try? context.save()
        }.value
    }


    private func fetchExercise(by id: UUID, context: ModelContext) -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchAllExercises(context: ModelContext) -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>()
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Accessory Goal Checkin Sync

    /// Fetches all accessory goal checkins from backend using pagination and imports them locally
    private func syncAccessoryGoalCheckinsFromBackend(resumeState state: inout SyncState) async {
        var pageToken = state.accessoryGoalCheckinPageToken
        var totalFetched = state.accessoryGoalCheckinsFetched

        do {
            repeat {
                let response = try await APIService.shared.getAccessoryGoalCheckins(limit: 500, pageToken: pageToken)
                totalFetched += response.count

                await importAccessoryGoalCheckinsFromBackend(response.checkins)

                state.accessoryGoalCheckinsFetched = totalFetched
                pageToken = response.hasMore ? response.nextPageToken : nil
                state.accessoryGoalCheckinPageToken = pageToken
                syncState = state

            } while pageToken != nil

            SyncLogger.sync.info("Completed accessory goal checkin sync, fetched \(totalFetched) total")
        } catch {
            SyncLogger.sync.error("Failed to sync accessory goal checkins: \(error.localizedDescription)")
        }
    }

    /// Syncs a single accessory goal checkin to the backend (for new creations)
    func syncAccessoryGoalCheckin(_ checkin: AccessoryGoalCheckin) async {
        let dto = checkin.toDTO()

        do {
            _ = try await APIService.shared.createAccessoryGoalCheckins([dto])
            retryQueue.removePendingAccessoryGoalCheckinOperation(checkinId: checkin.id)
            SyncLogger.sync.debug("Synced accessory goal checkin \(checkin.id)")
        } catch {
            SyncLogger.sync.error("Failed to sync accessory goal checkin \(checkin.id): \(error.localizedDescription)")
            retryQueue.addPendingAccessoryGoalCheckinCreate(checkinId: checkin.id)
        }
    }

    /// Deletes an accessory goal checkin from the backend
    func deleteAccessoryGoalCheckin(_ checkinId: UUID) async {
        do {
            _ = try await APIService.shared.deleteAccessoryGoalCheckins([checkinId])
            retryQueue.removePendingAccessoryGoalCheckinOperation(checkinId: checkinId)
            SyncLogger.sync.debug("Deleted accessory goal checkin \(checkinId)")
        } catch {
            SyncLogger.sync.error("Failed to delete accessory goal checkin \(checkinId): \(error.localizedDescription)")
            retryQueue.addPendingAccessoryGoalCheckinDelete(checkinId: checkinId)
        }
    }

    /// Process pending accessory goal checkin operations from retry queue
    func processAccessoryGoalCheckinRetryQueue() async {
        guard let context = modelContext else { return }

        let pendingOperations = retryQueue.getPendingAccessoryGoalCheckinOperations()

        for operation in pendingOperations {
            switch operation.operationType {
            case .upsert:
                if let checkin = fetchAccessoryGoalCheckin(by: operation.checkinId, context: context) {
                    do {
                        _ = try await APIService.shared.createAccessoryGoalCheckins([checkin.toDTO()])
                        retryQueue.removePendingAccessoryGoalCheckinOperation(checkinId: operation.checkinId)
                    } catch {
                        retryQueue.incrementAccessoryGoalCheckinRetryCount(for: operation.checkinId)
                    }
                } else {
                    retryQueue.removePendingAccessoryGoalCheckinOperation(checkinId: operation.checkinId)
                }

            case .delete:
                do {
                    _ = try await APIService.shared.deleteAccessoryGoalCheckins([operation.checkinId])
                    retryQueue.removePendingAccessoryGoalCheckinOperation(checkinId: operation.checkinId)
                } catch {
                    retryQueue.incrementAccessoryGoalCheckinRetryCount(for: operation.checkinId)
                }
            }
        }
    }

    private func importAccessoryGoalCheckinsFromBackend(_ dtos: [AccessoryGoalCheckinDTO]) async {
        guard let container = modelContainer else { return }
        let sendableDtos = dtos
        await Task.detached {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let existingCheckins = (try? context.fetch(FetchDescriptor<AccessoryGoalCheckin>())) ?? []
            let existingById = Dictionary(uniqueKeysWithValues: existingCheckins.map { ($0.id, $0) })

            for dto in sendableDtos {
                if let existing = existingById[dto.checkinId] {
                    existing.metricType = dto.metricType
                    existing.value = dto.value
                    existing.createdTimezone = dto.createdTimezone
                    existing.createdAt = dto.createdDatetime
                } else {
                    let checkin = AccessoryGoalCheckin(metricType: dto.metricType, value: dto.value)
                    checkin.id = dto.checkinId
                    checkin.createdTimezone = dto.createdTimezone
                    checkin.createdAt = dto.createdDatetime
                    context.insert(checkin)
                }
            }

            try? context.save()
        }.value
    }

    private func fetchAccessoryGoalCheckin(by id: UUID, context: ModelContext) -> AccessoryGoalCheckin? {
        let descriptor = FetchDescriptor<AccessoryGoalCheckin>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Cleanup

    func clearOnLogout() {
        SyncLogger.sync.info("Clearing sync state on logout")
        retryQueue.clearAll()
        UserDefaults.standard.removeObject(forKey: Self.syncStateKey)
        UserDefaults.standard.removeObject(forKey: "insights_cached_response")
        UserDefaults.standard.removeObject(forKey: "insights_last_fetched_at")
        UserDefaults.standard.removeObject(forKey: "insights_last_viewed_week")
    }
}
