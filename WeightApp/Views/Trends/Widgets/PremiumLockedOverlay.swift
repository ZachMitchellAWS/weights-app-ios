//
//  PremiumLockedOverlay.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/13/26.
//

import SwiftUI

struct PremiumLockedOverlay: ViewModifier {
    let title: String
    let subtitle: String
    let ctaText: String
    let blurRadius: CGFloat
    @Binding var showUpsell: Bool

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: blurRadius)
                .allowsHitTesting(false)

            Color.black.opacity(0.3)

            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.appAccent)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                Text(ctaText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.appAccent, in: Capsule())
            }
            .padding(.horizontal, 16)
        }
        .contentShape(Rectangle())
        .onTapGesture { showUpsell = true }
    }
}

extension View {
    func premiumLocked(
        title: String,
        subtitle: String,
        ctaText: String = "Go Premium",
        blurRadius: CGFloat = 6,
        showUpsell: Binding<Bool>
    ) -> some View {
        modifier(PremiumLockedOverlay(
            title: title,
            subtitle: subtitle,
            ctaText: ctaText,
            blurRadius: blurRadius,
            showUpsell: showUpsell
        ))
    }
}
