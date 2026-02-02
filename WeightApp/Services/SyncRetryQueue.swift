//
//  SyncRetryQueue.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/30/26.
//

import Foundation

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

class SyncRetryQueue {
    static let shared = SyncRetryQueue()

    private let userDefaultsKey = "SyncRetryQueue.PendingOperations"
    private let userPropertiesKey = "SyncRetryQueue.PendingUserPropertiesSync"
    private let liftSetOperationsKey = "SyncRetryQueue.PendingLiftSetOperations"
    private let estimated1RMOperationsKey = "SyncRetryQueue.PendingEstimated1RMOperations"
    private let maxRetries = 10

    private init() {}

    // MARK: - Public Methods

    func addPendingUpsert(exerciseId: UUID) {
        addOperation(PendingOperation(exerciseId: exerciseId, operationType: .upsert))
    }

    func addPendingDelete(exerciseId: UUID) {
        addOperation(PendingOperation(exerciseId: exerciseId, operationType: .delete))
    }

    func removePendingOperation(exerciseId: UUID) {
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
    }

    func hasPendingOperations() -> Bool {
        return !loadOperations().isEmpty || !loadLiftSetOperations().isEmpty || !loadEstimated1RMOperations().isEmpty
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
            print("SyncRetryQueue: Failed to decode pending user properties sync: \(error)")
            return nil
        }
    }

    func incrementUserPropertiesRetryCount() {
        guard var pending = getPendingUserPropertiesSync() else { return }

        pending.retryCount += 1
        if pending.retryCount >= maxRetries {
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
            print("SyncRetryQueue: Failed to encode pending user properties sync: \(error)")
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
            print("SyncRetryQueue: Failed to decode pending operations: \(error)")
            return []
        }
    }

    private func saveOperations(_ operations: [PendingOperation]) {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("SyncRetryQueue: Failed to encode pending operations: \(error)")
        }
    }

    // MARK: - Lift Set Operations

    func addPendingLiftSetCreate(liftSetId: UUID) {
        addLiftSetOperation(PendingLiftSetOperation(liftSetId: liftSetId, operationType: .upsert))
    }

    func addPendingLiftSetDelete(liftSetId: UUID) {
        addLiftSetOperation(PendingLiftSetOperation(liftSetId: liftSetId, operationType: .delete))
    }

    func removePendingLiftSetOperation(liftSetId: UUID) {
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
            print("SyncRetryQueue: Failed to decode pending lift set operations: \(error)")
            return []
        }
    }

    private func saveLiftSetOperations(_ operations: [PendingLiftSetOperation]) {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: liftSetOperationsKey)
        } catch {
            print("SyncRetryQueue: Failed to encode pending lift set operations: \(error)")
        }
    }

    // MARK: - Estimated 1RM Operations

    func addPendingEstimated1RMCreate(estimated1RMId: UUID, liftSetId: UUID) {
        addEstimated1RMOperation(PendingEstimated1RMOperation(estimated1RMId: estimated1RMId, liftSetId: liftSetId, operationType: .upsert))
    }

    func addPendingEstimated1RMDelete(estimated1RMId: UUID, liftSetId: UUID) {
        addEstimated1RMOperation(PendingEstimated1RMOperation(estimated1RMId: estimated1RMId, liftSetId: liftSetId, operationType: .delete))
    }

    func removePendingEstimated1RMOperation(estimated1RMId: UUID) {
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
            print("SyncRetryQueue: Failed to decode pending estimated 1RM operations: \(error)")
            return []
        }
    }

    private func saveEstimated1RMOperations(_ operations: [PendingEstimated1RMOperation]) {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: estimated1RMOperationsKey)
        } catch {
            print("SyncRetryQueue: Failed to encode pending estimated 1RM operations: \(error)")
        }
    }
}
