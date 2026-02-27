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

struct PendingSequenceOperation: Codable, Equatable {
    let sequenceId: UUID
    let operationType: PendingOperationType
    var retryCount: Int
    let createdAt: Date

    init(sequenceId: UUID, operationType: PendingOperationType) {
        self.sequenceId = sequenceId
        self.operationType = operationType
        self.retryCount = 0
        self.createdAt = Date()
    }
}

struct PendingSplitOperation: Codable, Equatable {
    let splitId: UUID
    let operationType: PendingOperationType
    var retryCount: Int
    let createdAt: Date

    init(splitId: UUID, operationType: PendingOperationType) {
        self.splitId = splitId
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

struct PendingSetPlanTemplateOperation: Codable, Equatable {
    let templateId: UUID
    let operationType: PendingOperationType
    var retryCount: Int
    let createdAt: Date

    init(templateId: UUID, operationType: PendingOperationType) {
        self.templateId = templateId
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
    private let sequenceOperationsKey = "SyncRetryQueue.PendingSequenceOperations"
    private let splitOperationsKey = "SyncRetryQueue.PendingSplitOperations"
    private let templateOperationsKey = "SyncRetryQueue.PendingSetPlanTemplateOperations"
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
        UserDefaults.standard.removeObject(forKey: sequenceOperationsKey)
        UserDefaults.standard.removeObject(forKey: splitOperationsKey)
        UserDefaults.standard.removeObject(forKey: templateOperationsKey)
    }

    func hasPendingOperations() -> Bool {
        return !loadOperations().isEmpty || !loadLiftSetOperations().isEmpty || !loadEstimated1RMOperations().isEmpty || !loadSequenceOperations().isEmpty || !loadSplitOperations().isEmpty || !loadTemplateOperations().isEmpty
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

    // MARK: - Sequence Operations

    func addPendingSequenceUpsert(sequenceId: UUID) {
        SyncLogger.retry.debug("Queuing sequence upsert: \(sequenceId)")
        addSequenceOperation(PendingSequenceOperation(sequenceId: sequenceId, operationType: .upsert))
    }

    func addPendingSequenceDelete(sequenceId: UUID) {
        SyncLogger.retry.debug("Queuing sequence delete: \(sequenceId)")
        addSequenceOperation(PendingSequenceOperation(sequenceId: sequenceId, operationType: .delete))
    }

    func removePendingSequenceOperation(sequenceId: UUID) {
        SyncLogger.retry.debug("Removing sequence operation: \(sequenceId)")
        var operations = loadSequenceOperations()
        operations.removeAll { $0.sequenceId == sequenceId }
        saveSequenceOperations(operations)
    }

    func getPendingSequenceOperations() -> [PendingSequenceOperation] {
        return loadSequenceOperations()
    }

    func incrementSequenceRetryCount(for sequenceId: UUID) {
        var operations = loadSequenceOperations()
        if let index = operations.firstIndex(where: { $0.sequenceId == sequenceId }) {
            operations[index].retryCount += 1
            if operations[index].retryCount >= maxRetries {
                SyncLogger.retry.info("Sequence \(sequenceId) dropped after \(self.maxRetries) retries")
                operations.remove(at: index)
            }
        }
        saveSequenceOperations(operations)
    }

    func hasSequencePendingOperations() -> Bool {
        return !loadSequenceOperations().isEmpty
    }

    private func addSequenceOperation(_ operation: PendingSequenceOperation) {
        var operations = loadSequenceOperations()

        if let existingIndex = operations.firstIndex(where: { $0.sequenceId == operation.sequenceId }) {
            operations[existingIndex] = operation
        } else {
            operations.append(operation)
        }

        saveSequenceOperations(operations)
    }

    private func loadSequenceOperations() -> [PendingSequenceOperation] {
        guard let data = UserDefaults.standard.data(forKey: sequenceOperationsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PendingSequenceOperation].self, from: data)
        } catch {
            SyncLogger.retry.error("Failed to decode pending sequence operations: \(error)")
            return []
        }
    }

    private func saveSequenceOperations(_ operations: [PendingSequenceOperation]) {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: sequenceOperationsKey)
        } catch {
            SyncLogger.retry.error("Failed to encode pending sequence operations: \(error)")
        }
    }

    // MARK: - Split Operations

    func addPendingSplitUpsert(splitId: UUID) {
        SyncLogger.retry.debug("Queuing split upsert: \(splitId)")
        addSplitOperation(PendingSplitOperation(splitId: splitId, operationType: .upsert))
    }

    func addPendingSplitDelete(splitId: UUID) {
        SyncLogger.retry.debug("Queuing split delete: \(splitId)")
        addSplitOperation(PendingSplitOperation(splitId: splitId, operationType: .delete))
    }

    func removePendingSplitOperation(splitId: UUID) {
        SyncLogger.retry.debug("Removing split operation: \(splitId)")
        var operations = loadSplitOperations()
        operations.removeAll { $0.splitId == splitId }
        saveSplitOperations(operations)
    }

    func getPendingSplitOperations() -> [PendingSplitOperation] {
        return loadSplitOperations()
    }

    func incrementSplitRetryCount(for splitId: UUID) {
        var operations = loadSplitOperations()
        if let index = operations.firstIndex(where: { $0.splitId == splitId }) {
            operations[index].retryCount += 1
            if operations[index].retryCount >= maxRetries {
                SyncLogger.retry.info("Split \(splitId) dropped after \(self.maxRetries) retries")
                operations.remove(at: index)
            }
        }
        saveSplitOperations(operations)
    }

    func hasSplitPendingOperations() -> Bool {
        return !loadSplitOperations().isEmpty
    }

    private func addSplitOperation(_ operation: PendingSplitOperation) {
        var operations = loadSplitOperations()

        if let existingIndex = operations.firstIndex(where: { $0.splitId == operation.splitId }) {
            operations[existingIndex] = operation
        } else {
            operations.append(operation)
        }

        saveSplitOperations(operations)
    }

    private func loadSplitOperations() -> [PendingSplitOperation] {
        guard let data = UserDefaults.standard.data(forKey: splitOperationsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PendingSplitOperation].self, from: data)
        } catch {
            SyncLogger.retry.error("Failed to decode pending split operations: \(error)")
            return []
        }
    }

    private func saveSplitOperations(_ operations: [PendingSplitOperation]) {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: splitOperationsKey)
        } catch {
            SyncLogger.retry.error("Failed to encode pending split operations: \(error)")
        }
    }

    // MARK: - Set Plan Template Operations

    func addPendingTemplateUpsert(templateId: UUID) {
        SyncLogger.retry.debug("Queuing template upsert: \(templateId)")
        addTemplateOperation(PendingSetPlanTemplateOperation(templateId: templateId, operationType: .upsert))
    }

    func addPendingTemplateDelete(templateId: UUID) {
        SyncLogger.retry.debug("Queuing template delete: \(templateId)")
        addTemplateOperation(PendingSetPlanTemplateOperation(templateId: templateId, operationType: .delete))
    }

    func removePendingTemplateOperation(templateId: UUID) {
        SyncLogger.retry.debug("Removing template operation: \(templateId)")
        var operations = loadTemplateOperations()
        operations.removeAll { $0.templateId == templateId }
        saveTemplateOperations(operations)
    }

    func getPendingTemplateOperations() -> [PendingSetPlanTemplateOperation] {
        return loadTemplateOperations()
    }

    func incrementTemplateRetryCount(for templateId: UUID) {
        var operations = loadTemplateOperations()
        if let index = operations.firstIndex(where: { $0.templateId == templateId }) {
            operations[index].retryCount += 1
            if operations[index].retryCount >= maxRetries {
                SyncLogger.retry.info("Template \(templateId) dropped after \(self.maxRetries) retries")
                operations.remove(at: index)
            }
        }
        saveTemplateOperations(operations)
    }

    func hasTemplatePendingOperations() -> Bool {
        return !loadTemplateOperations().isEmpty
    }

    private func addTemplateOperation(_ operation: PendingSetPlanTemplateOperation) {
        var operations = loadTemplateOperations()

        if let existingIndex = operations.firstIndex(where: { $0.templateId == operation.templateId }) {
            operations[existingIndex] = operation
        } else {
            operations.append(operation)
        }

        saveTemplateOperations(operations)
    }

    private func loadTemplateOperations() -> [PendingSetPlanTemplateOperation] {
        guard let data = UserDefaults.standard.data(forKey: templateOperationsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PendingSetPlanTemplateOperation].self, from: data)
        } catch {
            SyncLogger.retry.error("Failed to decode pending template operations: \(error)")
            return []
        }
    }

    private func saveTemplateOperations(_ operations: [PendingSetPlanTemplateOperation]) {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: templateOperationsKey)
        } catch {
            SyncLogger.retry.error("Failed to encode pending template operations: \(error)")
        }
    }
}
