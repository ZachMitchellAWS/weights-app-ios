//
//  SyncRetryQueue.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/30/26.
//

import Foundation
import OSLog

enum PendingOperationType: String, Codable {
    case upsert
    case delete
}

struct PendingOperation: Codable, Equatable {
    let exerciseId: UUID
    let operationType: PendingOperationType
    var retryCount: Int
    let createdAt: Date

    init(exerciseId: UUID, operationType: PendingOperationType) {
        self.exerciseId = exerciseId
        self.operationType = operationType
        self.retryCount = 0
        self.createdAt = Date()
    }
}

struct PendingUserPropertiesSync: Codable {
    var retryCount: Int
    let createdAt: Date

    init() {
        self.retryCount = 0
        self.createdAt = Date()
    }
}

struct PendingLiftSetOperation: Codable, Equatable {
    let liftSetId: UUID
    let operationType: PendingOperationType
    var retryCount: Int
    let createdAt: Date

    init(liftSetId: UUID, operationType: PendingOperationType) {
        self.liftSetId = liftSetId
        self.operationType = operationType
        self.retryCount = 0
        self.createdAt = Date()
    }
}


struct PendingEstimated1RMOperation: Codable, Equatable {
    let estimated1RMId: UUID
    let liftSetId: UUID  // Used for delete operations (API uses liftSetId)
    let operationType: PendingOperationType
    var retryCount: Int
    let createdAt: Date

    init(estimated1RMId: UUID, liftSetId: UUID, operationType: PendingOperationType) {
        self.estimated1RMId = estimated1RMId
        self.liftSetId = liftSetId
        self.operationType = operationType
        self.retryCount = 0
        self.createdAt = Date()
    }
}

struct PendingSetPlanOperation: Codable, Equatable {
    let planId: UUID
    let operationType: PendingOperationType
    var retryCount: Int
    let createdAt: Date

    init(planId: UUID, operationType: PendingOperationType) {
        self.planId = planId
        self.operationType = operationType
        self.retryCount = 0
        self.createdAt = Date()
    }
}

struct PendingGroupOperation: Codable, Equatable {
    let groupId: UUID
    let operationType: PendingOperationType
    var retryCount: Int
    let createdAt: Date

    init(groupId: UUID, operationType: PendingOperationType) {
        self.groupId = groupId
        self.operationType = operationType
        self.retryCount = 0
        self.createdAt = Date()
    }
}

struct PendingAccessoryGoalCheckinOperation: Codable, Equatable {
    let checkinId: UUID
    let operationType: PendingOperationType
    var retryCount: Int
    let createdAt: Date

    init(checkinId: UUID, operationType: PendingOperationType) {
        self.checkinId = checkinId
        self.operationType = operationType
        self.retryCount = 0
        self.createdAt = Date()
    }
}

class SyncRetryQueue {
    static let shared = SyncRetryQueue()

    private let userDefaultsKey = "SyncRetryQueue.PendingOperations"
    private let userPropertiesKey = "SyncRetryQueue.PendingUserPropertiesSync"
    private let liftSetOperationsKey = "SyncRetryQueue.PendingLiftSetOperations"
    private let estimated1RMOperationsKey = "SyncRetryQueue.PendingEstimated1RMOperations"
    private let planOperationsKey = "SyncRetryQueue.PendingSetPlanOperations"
    private let groupOperationsKey = "SyncRetryQueue.PendingGroupOperations"
    private let accessoryGoalCheckinOperationsKey = "SyncRetryQueue.PendingAccessoryGoalCheckinOperations"
    private let maxRetries = 10

    private init() {}

    // MARK: - Public Methods

    func addPendingUpsert(exerciseId: UUID) {
        SyncLogger.retry.debug("Queuing exercise upsert: \(exerciseId)")
        addOperation(PendingOperation(exerciseId: exerciseId, operationType: .upsert))
    }

    func addPendingDelete(exerciseId: UUID) {
        SyncLogger.retry.debug("Queuing exercise delete: \(exerciseId)")
        addOperation(PendingOperation(exerciseId: exerciseId, operationType: .delete))
    }

    func removePendingOperation(exerciseId: UUID) {
        SyncLogger.retry.debug("Removing exercise operation: \(exerciseId)")
        var operations = loadOperations()
        operations.removeAll { $0.exerciseId == exerciseId }
        saveOperations(operations)
    }

    func getPendingOperations() -> [PendingOperation] {
        return loadOperations()
    }

    func incrementRetryCount(for exerciseId: UUID) {
        var operations = loadOperations()
        if let index = operations.firstIndex(where: { $0.exerciseId == exerciseId }) {
            operations[index].retryCount += 1
            if operations[index].retryCount >= maxRetries {
                SyncLogger.retry.info("Exercise \(exerciseId) dropped after \(self.maxRetries) retries")
                operations.remove(at: index)
            }
        }
        saveOperations(operations)
    }

    func clearAll() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: userPropertiesKey)
        UserDefaults.standard.removeObject(forKey: liftSetOperationsKey)
        UserDefaults.standard.removeObject(forKey: estimated1RMOperationsKey)
        UserDefaults.standard.removeObject(forKey: planOperationsKey)
        UserDefaults.standard.removeObject(forKey: groupOperationsKey)
        UserDefaults.standard.removeObject(forKey: accessoryGoalCheckinOperationsKey)
    }

    func hasPendingOperations() -> Bool {
        return !loadOperations().isEmpty || !loadLiftSetOperations().isEmpty || !loadEstimated1RMOperations().isEmpty || !loadPlanOperations().isEmpty || !loadGroupOperations().isEmpty || !loadAccessoryGoalCheckinOperations().isEmpty
    }

    // MARK: - User Properties Sync Methods

    func addPendingUserPropertiesSync() {
        let pending = PendingUserPropertiesSync()
        saveUserPropertiesSync(pending)
    }

    func removePendingUserPropertiesSync() {
        UserDefaults.standard.removeObject(forKey: userPropertiesKey)
    }

    func getPendingUserPropertiesSync() -> PendingUserPropertiesSync? {
        guard let data = UserDefaults.standard.data(forKey: userPropertiesKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(PendingUserPropertiesSync.self, from: data)
        } catch {
            SyncLogger.retry.error("Failed to decode pending user properties sync: \(error)")
            return nil
        }
    }

    func incrementUserPropertiesRetryCount() {
        guard var pending = getPendingUserPropertiesSync() else { return }

        pending.retryCount += 1
        if pending.retryCount >= maxRetries {
            SyncLogger.retry.info("User properties sync dropped after \(self.maxRetries) retries")
            removePendingUserPropertiesSync()
        } else {
            saveUserPropertiesSync(pending)
        }
    }

    func hasUserPropertiesPending() -> Bool {
        return getPendingUserPropertiesSync() != nil
    }

    private func saveUserPropertiesSync(_ pending: PendingUserPropertiesSync) {
        do {
            let data = try JSONEncoder().encode(pending)
            UserDefaults.standard.set(data, forKey: userPropertiesKey)
        } catch {
            SyncLogger.retry.error("Failed to encode pending user properties sync: \(error)")
        }
    }

    // MARK: - Private Methods

    private func addOperation(_ operation: PendingOperation) {
        var operations = loadOperations()

        if let existingIndex = operations.firstIndex(where: { $0.exerciseId == operation.exerciseId }) {
            operations[existingIndex] = operation
        } else {
            operations.append(operation)
        }

        saveOperations(operations)
    }

    private func loadOperations() -> [PendingOperation] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PendingOperation].self, from: data)
        } catch {
            SyncLogger.retry.error("Failed to decode pending operations: \(error)")
            return []
        }
    }

    private func saveOperations(_ operations: [PendingOperation]) {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            SyncLogger.retry.error("Failed to encode pending operations: \(error)")
        }
    }

    // MARK: - Lift Set Operations

    func addPendingLiftSetCreate(liftSetId: UUID) {
        SyncLogger.retry.debug("Queuing lift set create: \(liftSetId)")
        addLiftSetOperation(PendingLiftSetOperation(liftSetId: liftSetId, operationType: .upsert))
    }

    func addPendingLiftSetDelete(liftSetId: UUID) {
        SyncLogger.retry.debug("Queuing lift set delete: \(liftSetId)")
        addLiftSetOperation(PendingLiftSetOperation(liftSetId: liftSetId, operationType: .delete))
    }

    func removePendingLiftSetOperation(liftSetId: UUID) {
        SyncLogger.retry.debug("Removing lift set operation: \(liftSetId)")
        var operations = loadLiftSetOperations()
        operations.removeAll { $0.liftSetId == liftSetId }
        saveLiftSetOperations(operations)
    }

    func getPendingLiftSetOperations() -> [PendingLiftSetOperation] {
        return loadLiftSetOperations()
    }

    func incrementLiftSetRetryCount(for liftSetId: UUID) {
        var operations = loadLiftSetOperations()
        if let index = operations.firstIndex(where: { $0.liftSetId == liftSetId }) {
            operations[index].retryCount += 1
            if operations[index].retryCount >= maxRetries {
                SyncLogger.retry.info("Lift set \(liftSetId) dropped after \(self.maxRetries) retries")
                operations.remove(at: index)
            }
        }
        saveLiftSetOperations(operations)
    }

    func hasLiftSetPendingOperations() -> Bool {
        return !loadLiftSetOperations().isEmpty
    }

    private func addLiftSetOperation(_ operation: PendingLiftSetOperation) {
        var operations = loadLiftSetOperations()

        if let existingIndex = operations.firstIndex(where: { $0.liftSetId == operation.liftSetId }) {
            operations[existingIndex] = operation
        } else {
            operations.append(operation)
        }

        saveLiftSetOperations(operations)
    }

    private func loadLiftSetOperations() -> [PendingLiftSetOperation] {
        guard let data = UserDefaults.standard.data(forKey: liftSetOperationsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PendingLiftSetOperation].self, from: data)
        } catch {
            SyncLogger.retry.error("Failed to decode pending lift set operations: \(error)")
            return []
        }
    }

    private func saveLiftSetOperations(_ operations: [PendingLiftSetOperation]) {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: liftSetOperationsKey)
        } catch {
            SyncLogger.retry.error("Failed to encode pending lift set operations: \(error)")
        }
    }

    // MARK: - Estimated 1RM Operations

    func addPendingEstimated1RMCreate(estimated1RMId: UUID, liftSetId: UUID) {
        SyncLogger.retry.debug("Queuing estimated 1RM create: \(estimated1RMId)")
        addEstimated1RMOperation(PendingEstimated1RMOperation(estimated1RMId: estimated1RMId, liftSetId: liftSetId, operationType: .upsert))
    }

    func addPendingEstimated1RMDelete(estimated1RMId: UUID, liftSetId: UUID) {
        SyncLogger.retry.debug("Queuing estimated 1RM delete: \(estimated1RMId)")
        addEstimated1RMOperation(PendingEstimated1RMOperation(estimated1RMId: estimated1RMId, liftSetId: liftSetId, operationType: .delete))
    }

    func removePendingEstimated1RMOperation(estimated1RMId: UUID) {
        SyncLogger.retry.debug("Removing estimated 1RM operation: \(estimated1RMId)")
        var operations = loadEstimated1RMOperations()
        operations.removeAll { $0.estimated1RMId == estimated1RMId }
        saveEstimated1RMOperations(operations)
    }

    func getPendingEstimated1RMOperations() -> [PendingEstimated1RMOperation] {
        return loadEstimated1RMOperations()
    }

    func incrementEstimated1RMRetryCount(for estimated1RMId: UUID) {
        var operations = loadEstimated1RMOperations()
        if let index = operations.firstIndex(where: { $0.estimated1RMId == estimated1RMId }) {
            operations[index].retryCount += 1
            if operations[index].retryCount >= maxRetries {
                SyncLogger.retry.info("Estimated 1RM \(estimated1RMId) dropped after \(self.maxRetries) retries")
                operations.remove(at: index)
            }
        }
        saveEstimated1RMOperations(operations)
    }

    func hasEstimated1RMPendingOperations() -> Bool {
        return !loadEstimated1RMOperations().isEmpty
    }

    private func addEstimated1RMOperation(_ operation: PendingEstimated1RMOperation) {
        var operations = loadEstimated1RMOperations()

        if let existingIndex = operations.firstIndex(where: { $0.estimated1RMId == operation.estimated1RMId }) {
            operations[existingIndex] = operation
        } else {
            operations.append(operation)
        }

        saveEstimated1RMOperations(operations)
    }

    private func loadEstimated1RMOperations() -> [PendingEstimated1RMOperation] {
        guard let data = UserDefaults.standard.data(forKey: estimated1RMOperationsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PendingEstimated1RMOperation].self, from: data)
        } catch {
            SyncLogger.retry.error("Failed to decode pending estimated 1RM operations: \(error)")
            return []
        }
    }

    private func saveEstimated1RMOperations(_ operations: [PendingEstimated1RMOperation]) {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: estimated1RMOperationsKey)
        } catch {
            SyncLogger.retry.error("Failed to encode pending estimated 1RM operations: \(error)")
        }
    }


    // MARK: - Set Plan Operations

    func addPendingPlanUpsert(planId: UUID) {
        SyncLogger.retry.debug("Queuing set plan upsert: \(planId)")
        addPlanOperation(PendingSetPlanOperation(planId: planId, operationType: .upsert))
    }

    func addPendingPlanDelete(planId: UUID) {
        SyncLogger.retry.debug("Queuing set plan delete: \(planId)")
        addPlanOperation(PendingSetPlanOperation(planId: planId, operationType: .delete))
    }

    func removePendingPlanOperation(planId: UUID) {
        SyncLogger.retry.debug("Removing set plan operation: \(planId)")
        var operations = loadPlanOperations()
        operations.removeAll { $0.planId == planId }
        savePlanOperations(operations)
    }

    func getPendingPlanOperations() -> [PendingSetPlanOperation] {
        return loadPlanOperations()
    }

    func incrementPlanRetryCount(for planId: UUID) {
        var operations = loadPlanOperations()
        if let index = operations.firstIndex(where: { $0.planId == planId }) {
            operations[index].retryCount += 1
            if operations[index].retryCount >= maxRetries {
                SyncLogger.retry.info("Set plan \(planId) dropped after \(self.maxRetries) retries")
                operations.remove(at: index)
            }
        }
        savePlanOperations(operations)
    }

    func hasPlanPendingOperations() -> Bool {
        return !loadPlanOperations().isEmpty
    }

    private func addPlanOperation(_ operation: PendingSetPlanOperation) {
        var operations = loadPlanOperations()

        if let existingIndex = operations.firstIndex(where: { $0.planId == operation.planId }) {
            operations[existingIndex] = operation
        } else {
            operations.append(operation)
        }

        savePlanOperations(operations)
    }

    private func loadPlanOperations() -> [PendingSetPlanOperation] {
        guard let data = UserDefaults.standard.data(forKey: planOperationsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PendingSetPlanOperation].self, from: data)
        } catch {
            SyncLogger.retry.error("Failed to decode pending set plan operations: \(error)")
            return []
        }
    }

    private func savePlanOperations(_ operations: [PendingSetPlanOperation]) {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: planOperationsKey)
        } catch {
            SyncLogger.retry.error("Failed to encode pending set plan operations: \(error)")
        }
    }

    // MARK: - Group Operations

    func addPendingGroupUpsert(groupId: UUID) {
        SyncLogger.retry.debug("Queuing group upsert: \(groupId)")
        addGroupOperation(PendingGroupOperation(groupId: groupId, operationType: .upsert))
    }

    func addPendingGroupDelete(groupId: UUID) {
        SyncLogger.retry.debug("Queuing group delete: \(groupId)")
        addGroupOperation(PendingGroupOperation(groupId: groupId, operationType: .delete))
    }

    func removePendingGroupOperation(groupId: UUID) {
        SyncLogger.retry.debug("Removing group operation: \(groupId)")
        var operations = loadGroupOperations()
        operations.removeAll { $0.groupId == groupId }
        saveGroupOperations(operations)
    }

    func getPendingGroupOperations() -> [PendingGroupOperation] {
        return loadGroupOperations()
    }

    func incrementGroupRetryCount(for groupId: UUID) {
        var operations = loadGroupOperations()
        if let index = operations.firstIndex(where: { $0.groupId == groupId }) {
            operations[index].retryCount += 1
            if operations[index].retryCount >= maxRetries {
                SyncLogger.retry.info("Group \(groupId) dropped after \(self.maxRetries) retries")
                operations.remove(at: index)
            }
        }
        saveGroupOperations(operations)
    }

    func hasGroupPendingOperations() -> Bool {
        return !loadGroupOperations().isEmpty
    }

    private func addGroupOperation(_ operation: PendingGroupOperation) {
        var operations = loadGroupOperations()

        if let existingIndex = operations.firstIndex(where: { $0.groupId == operation.groupId }) {
            operations[existingIndex] = operation
        } else {
            operations.append(operation)
        }

        saveGroupOperations(operations)
    }

    private func loadGroupOperations() -> [PendingGroupOperation] {
        guard let data = UserDefaults.standard.data(forKey: groupOperationsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PendingGroupOperation].self, from: data)
        } catch {
            SyncLogger.retry.error("Failed to decode pending group operations: \(error)")
            return []
        }
    }

    private func saveGroupOperations(_ operations: [PendingGroupOperation]) {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: groupOperationsKey)
        } catch {
            SyncLogger.retry.error("Failed to encode pending group operations: \(error)")
        }
    }

    // MARK: - Accessory Goal Checkin Operations

    func addPendingAccessoryGoalCheckinCreate(checkinId: UUID) {
        SyncLogger.retry.debug("Queuing accessory goal checkin create: \(checkinId)")
        addAccessoryGoalCheckinOperation(PendingAccessoryGoalCheckinOperation(checkinId: checkinId, operationType: .upsert))
    }

    func addPendingAccessoryGoalCheckinDelete(checkinId: UUID) {
        SyncLogger.retry.debug("Queuing accessory goal checkin delete: \(checkinId)")
        addAccessoryGoalCheckinOperation(PendingAccessoryGoalCheckinOperation(checkinId: checkinId, operationType: .delete))
    }

    func removePendingAccessoryGoalCheckinOperation(checkinId: UUID) {
        SyncLogger.retry.debug("Removing accessory goal checkin operation: \(checkinId)")
        var operations = loadAccessoryGoalCheckinOperations()
        operations.removeAll { $0.checkinId == checkinId }
        saveAccessoryGoalCheckinOperations(operations)
    }

    func getPendingAccessoryGoalCheckinOperations() -> [PendingAccessoryGoalCheckinOperation] {
        return loadAccessoryGoalCheckinOperations()
    }

    func incrementAccessoryGoalCheckinRetryCount(for checkinId: UUID) {
        var operations = loadAccessoryGoalCheckinOperations()
        if let index = operations.firstIndex(where: { $0.checkinId == checkinId }) {
            operations[index].retryCount += 1
            if operations[index].retryCount >= maxRetries {
                SyncLogger.retry.info("Accessory goal checkin \(checkinId) dropped after \(self.maxRetries) retries")
                operations.remove(at: index)
            }
        }
        saveAccessoryGoalCheckinOperations(operations)
    }

    func hasAccessoryGoalCheckinPendingOperations() -> Bool {
        return !loadAccessoryGoalCheckinOperations().isEmpty
    }

    private func addAccessoryGoalCheckinOperation(_ operation: PendingAccessoryGoalCheckinOperation) {
        var operations = loadAccessoryGoalCheckinOperations()

        if let existingIndex = operations.firstIndex(where: { $0.checkinId == operation.checkinId }) {
            operations[existingIndex] = operation
        } else {
            operations.append(operation)
        }

        saveAccessoryGoalCheckinOperations(operations)
    }

    private func loadAccessoryGoalCheckinOperations() -> [PendingAccessoryGoalCheckinOperation] {
        guard let data = UserDefaults.standard.data(forKey: accessoryGoalCheckinOperationsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PendingAccessoryGoalCheckinOperation].self, from: data)
        } catch {
            SyncLogger.retry.error("Failed to decode pending accessory goal checkin operations: \(error)")
            return []
        }
    }

    private func saveAccessoryGoalCheckinOperations(_ operations: [PendingAccessoryGoalCheckinOperation]) {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: accessoryGoalCheckinOperationsKey)
        } catch {
            SyncLogger.retry.error("Failed to encode pending accessory goal checkin operations: \(error)")
        }
    }

}
