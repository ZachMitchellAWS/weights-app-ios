//
//  PurchaseService.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/4/26.
//

import Foundation
import StoreKit
import Combine

/// Placeholder service for StoreKit 2 integration
/// All product IDs, prices, and configuration come from SubscriptionConfig
@MainActor
class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    @Published var products: [Product] = []
    @Published var purchaseInProgress = false
    @Published var purchaseError: String?

    private init() {}

    // MARK: - Product Loading

    /// Load available products from the App Store
    func loadProducts() async {
        do {
            let productIds = [
                SubscriptionConfig.monthlyProductId,
                SubscriptionConfig.yearlyProductId
            ]
            products = try await Product.products(for: productIds)
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    /// Get the monthly subscription product
    var monthlyProduct: Product? {
        products.first { $0.id == SubscriptionConfig.monthlyProductId }
    }

    /// Get the yearly subscription product
    var yearlyProduct: Product? {
        products.first { $0.id == SubscriptionConfig.yearlyProductId }
    }

    // MARK: - Purchasing

    /// Purchase a subscription product
    /// - Parameter product: The product to purchase
    /// - Returns: The transaction if successful
    func purchase(_ product: Product) async throws -> Transaction? {
        purchaseInProgress = true
        purchaseError = nil

        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                return transaction

            case .userCancelled:
                return nil

            case .pending:
                purchaseError = "Purchase is pending approval"
                return nil

            @unknown default:
                purchaseError = "Unknown purchase result"
                return nil
            }
        } catch {
            purchaseError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Restore Purchases

    /// Restore previous purchases
    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            print("Failed to restore purchases: \(error)")
        }
    }

    // MARK: - Transaction Verification

    /// Check if a verification result is verified
    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Transaction Listening

    /// Listen for transaction updates (call on app launch)
    func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    // TODO: Update entitlement based on transaction
                    await transaction.finish()
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }
}

// MARK: - Store Errors

enum StoreError: Error {
    case failedVerification
}
