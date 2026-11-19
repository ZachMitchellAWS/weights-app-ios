//
//  PricingDebugView.swift
//  WeightApp
//
//  Developer menu. What StoreKit actually returned, and what `IntroOfferService` made of it.
//
//  WHY THIS EXISTS. With two yearly SKUs, a 72-hour window and a legacy fallback, a paywall
//  showing "$39.99" has at least four possible causes: the new products are still Missing
//  Metadata, the StoreKit configuration file is or is not attached, the offer window has
//  elapsed, or an override is set. The screen itself cannot tell you which — by design, since
//  the fallback's whole job is to look like a working paywall. This is the only place that
//  distinguishes them.
//
//  It is also the fastest way to confirm an App Store Connect change landed: if a product id
//  appears here with the right price, the app can see it, and nothing else needs checking.
//

import SwiftUI
import StoreKit

struct PricingDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var purchaseService = PurchaseService.shared

    @State private var pricing: PricingContext?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Resolved state") {
                    if isLoading {
                        HStack { ProgressView(); Text("Asking StoreKit…") }
                    } else {
                        row("Offer", offerText)
                        row("Trial", pricing?.trial == .available ? "available" : "used")
                        row("Promotional chrome", (pricing?.showsPromotion ?? false) ? "shown" : "hidden")
                        // The one line that explains a surprising price. True means neither new
                        // yearly SKU resolved and the paywall is selling the old product.
                        row("Legacy fallback",
                            (pricing?.isLegacyFallback ?? false) ? "YES — new SKUs missing" : "no")
                        row("Selling", pricing?.yearly?.id ?? "—")
                        row("Yearly shown", pricing?.yearlyPriceText ?? "—")
                        row("Struck price", pricing?.strikePrice ?? "none")
                        row("Monthly shown", pricing?.monthlyPriceText ?? "—")
                    }
                }

                Section("Overrides") {
                    row("Offer State", IntroOfferStateOverride.value.label)
                    row("Trial State", TrialStateOverride.value.label)
                    Text("Set these in Developer → Entitlements. They win over the real clock.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Loaded products (\(purchaseService.products.count) of \(SubscriptionConfig.allProductIds.count))") {
                    if purchaseService.products.isEmpty {
                        Text("None. Either no StoreKit configuration is attached and the SKUs are "
                             + "not yet Ready to Submit, or the device has no App Store connection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(purchaseService.products, id: \.id) { product in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.id).font(.system(size: 12, design: .monospaced))
                            Text("\(product.displayPrice)  ·  \(product.subscription?.subscriptionPeriod.debugLabel ?? "—")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Anything listed here was requested and NOT returned. In sandbox that almost
                // always means the product is still "Missing Metadata" in App Store Connect —
                // incomplete products are omitted silently rather than reported as an error,
                // which is indistinguishable from them not existing.
                Section("Requested but missing") {
                    let loaded = Set(purchaseService.products.map(\.id))
                    let missing = SubscriptionConfig.allProductIds.filter { !loaded.contains($0) }
                    if missing.isEmpty {
                        Text("None — all five resolved.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(missing, id: \.self) { id in
                        Text(id)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Pricing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await purchaseService.loadProducts()
                pricing = await IntroOfferService.shared.pricingContext(purchaseService: purchaseService)
                isLoading = false
            }
        }
    }

    private var offerText: String {
        switch pricing?.offer {
        case .active(let deadline):
            let remaining = max(0, deadline.timeIntervalSinceNow)
            return "active · \(OfferCountdownBadge.formatted(remaining)) left"
        case .expired:
            return "expired"
        case nil:
            return "—"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 14))
    }
}

private extension Product.SubscriptionPeriod {
    /// "1 year" / "1 month", for confirming a SKU was created with the duration intended.
    var debugLabel: String {
        let n = value
        let unit: String
        switch self.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "?"
        }
        return "\(n) \(unit)\(n == 1 ? "" : "s")"
    }
}
