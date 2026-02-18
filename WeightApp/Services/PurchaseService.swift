//
//  PurchaseService.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/4/26.
//

import Foundation
import StoreKit
import Combine

/// StoreKit 2 purchase service
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
            print("[PurchaseService] Requesting product IDs: \(productIds)")
            products = try await Product.products(for: productIds)
            print("[PurchaseService] Loaded \(products.count) products: \(products.map { $0.id })")
            if products.isEmpty {
                print("[PurchaseService] No products returned — check App Store Connect or StoreKit config file")
            }
        } catch {
            print("[PurchaseService] Failed to load products: \(error)")
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
    /// - Parameters:
    ///   - product: The product to purchase
    ///   - userId: Optional user ID to attach as appAccountToken (links purchase to user for Apple webhooks)
    /// - Returns: The transaction if successful
    func purchase(_ product: Product, userId: String? = nil) async throws -> Transaction? {
        purchaseInProgress = true
        purchaseError = nil

        defer { purchaseInProgress = false }

        do {
            var options: Set<Product.PurchaseOption> = []
            if let userId, let token = UUID(uuidString: userId) {
                options.insert(.appAccountToken(token))
            }

            let result = try await product.purchase(options: options)

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
    /// Syncs entitlements with backend when renewals or other transaction updates arrive
    func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    let originalId = String(transaction.originalID)

                    // Sync with backend
                    do {
                        _ = try await EntitlementsService.shared.processTransactions(
                            originalTransactionIds: [originalId]
                        )
                        // Refresh local entitlement status from backend
                        await EntitlementsService.shared.syncEntitlementStatus()
                    } catch {
                        print("Failed to sync transaction with backend: \(error)")
                    }

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
