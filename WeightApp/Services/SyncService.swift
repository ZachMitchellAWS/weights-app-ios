//
//  SyncService.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/30/26.
//

import Foundation
import SwiftData

@MainActor
class SyncService {
    static let shared = SyncService()

    private var modelContext: ModelContext?
    private let retryQueue = SyncRetryQueue.shared

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

        do {
            let response = try await APIService.shared.getExercises()

            if response.exercises.isEmpty {
                await createAndSyncDefaultExercises(context: context)
            } else {
                await importExercisesFromBackend(response.exercises, context: context)
            }

            await processRetryQueue()
        } catch {
            print("SyncService: Initial sync failed: \(error.localizedDescription)")
        }
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
            if existingIds.contains(dto.exerciseItemId) {
                if let existing = existingExercises.first(where: { $0.id == dto.exerciseItemId }) {
                    existing.name = dto.name
                    existing.isCustom = dto.isCustom
                    existing.loadType = dto.loadType
                    existing.notes = dto.notes
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
                    notes: dto.notes
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
