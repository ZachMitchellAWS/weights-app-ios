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

class SyncRetryQueue {
    static let shared = SyncRetryQueue()

    private let userDefaultsKey = "SyncRetryQueue.PendingOperations"
    private let maxRetries = 3

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
    }

    func hasPendingOperations() -> Bool {
        return !loadOperations().isEmpty
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
}
