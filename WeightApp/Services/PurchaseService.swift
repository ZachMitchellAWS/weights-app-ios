//
//  PurchaseService.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/4/26.
//

import Foundation
import StoreKit
import Combine
import Sentry

/// StoreKit 2 purchase service
/// All product IDs, prices, and configuration come from SubscriptionConfig
@MainActor
class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    @Published var products: [Product] = []
    @Published var purchaseInProgress = false
    @Published var purchaseError: String?

    /// Transaction IDs already reported to Firebase Analytics this session.
    /// Prevents double-logging when both the foreground purchase() path and
    /// the Transaction.updates listener observe the same transaction.
    /// In-memory only — resets on app launch, which is fine because Firebase
    /// also dedupes by parameter set on its side.
    private var loggedTransactionIds = Set<UInt64>()

    private init() {}

    /// The paywall design on screen when a purchase was started, and how far the reader had
    /// scrolled through it.
    ///
    /// Lives here rather than on the view because `purchaseCompleted` is fired from
    /// `logPurchaseIfNew` below — a shared choke point that also catches renewals and
    /// foreground restores, where no paywall was involved. Those report nil, which is the
    /// honest answer rather than attributing a background renewal to whatever was last seen.
    ///
    /// Set when a variant paywall appears; cleared once a purchase has been attributed, so a
    /// renewal arriving later in the same session cannot inherit it.
    private(set) var activePaywallVariant: String?
    private(set) var activePaywallScrollDepth: Int?

    func setActivePaywall(variant: String?, scrollDepth: Int? = nil) {
        activePaywallVariant = variant
        activePaywallScrollDepth = scrollDepth
    }

    func clearActivePaywall() {
        activePaywallVariant = nil
        activePaywallScrollDepth = nil
    }

    /// Log a purchase if we haven't already logged this transaction this session.
    ///
    /// - Parameter userInitiated: true only for a transaction the user just completed at the
    ///   paywall. The `Transaction.updates` listener passes false.
    ///
    /// THE TWO DESTINATIONS DELIBERATELY DIFFER.
    ///
    /// Firebase fires ONLY when `userInitiated`. That event is wired to a Google Ads
    /// conversion action, and Ads cannot filter on an event parameter — so anything it
    /// receives counts. Renewals, restores and late-arriving approvals are all real
    /// transactions, but none of them is an acquisition, and letting them through inflates
    /// the conversion Ads is optimising against.
    ///
    /// Amplitude gets everything, because it CAN filter: `isRenewal` and `isFreeTrial` are on
    /// the event, so renewal behaviour stays analysable without corrupting ad spend.
    private func logPurchaseIfNew(transaction: Transaction, userInitiated: Bool) {
        guard loggedTransactionIds.insert(transaction.id).inserted else { return }
        let product = products.first(where: { $0.id == transaction.productID })
        if userInitiated {
            AnalyticsService.logPurchase(transaction: transaction, product: product)
        }

        // Mirror to Amplitude (single deduped choke point → covers foreground + renewal listener).
        let price = product.map { NSDecimalNumber(decimal: $0.price).doubleValue }
        let currency = product?.priceFormatStyle.currencyCode ?? "USD"
        AmplitudeService.shared.track(.purchaseCompleted(
            productId: transaction.productID,
            transactionId: String(transaction.id),
            isRenewal: transaction.originalID != transaction.id,
            isFreeTrial: transaction.offer?.paymentMode == .freeTrial,
            price: price,
            currency: currency,
            paywallVariant: activePaywallVariant,
            maxScrollDepthPct: activePaywallScrollDepth
        ))

        // Attribution is single-use. Leaving it set would tag the next renewal with a paywall
        // the user never saw.
        clearActivePaywall()
    }

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
            SentrySDK.capture(error: error)
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
                logPurchaseIfNew(transaction: transaction, userInitiated: true)
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
            SentrySDK.capture(error: error)
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
                    let environment: String? = transaction.environment == .sandbox ? "Sandbox" : nil

                    // Amplitude only — `userInitiated: false` keeps this off the Firebase
                    // conversion. Everything arriving here is either a renewal, a restore, a
                    // purchase made elsewhere, or an Ask-to-Buy approval landing after the
                    // fact; none is a paywall conversion. Still deduped against the
                    // foreground path, which replays the same transaction here. Hop to
                    // MainActor since the dedupe set + products array live there.
                    await self.logPurchaseIfNew(transaction: transaction, userInitiated: false)

                    // Sync with backend
                    do {
                        _ = try await EntitlementsService.shared.processTransactions(
                            originalTransactionIds: [originalId],
                            environment: environment
                        )
                        // Refresh local entitlement status from backend
                        await EntitlementsService.shared.syncEntitlementStatus()
                    } catch {
                        print("Failed to sync transaction with backend: \(error)")
                        SentrySDK.capture(error: error)
                    }

                    await transaction.finish()
                } catch {
                    print("Transaction verification failed: \(error)")
                    SentrySDK.capture(error: error)
                }
            }
        }
    }
}

// MARK: - Store Errors

enum StoreError: Error {
    case failedVerification
}
