//
//  PremiumBadge.swift
//  WeightApp
//
//  Marks a widget as a premium feature, for users who already have it.
//
//  Not a lock. `premiumLocked` and `SessionPremiumPlaceholder` are what a NON-subscriber
//  sees, and they obstruct or substitute. This is the opposite case: the feature is
//  working and in front of a paying user, and the badge quietly names what they are
//  getting for their money. So there is no lock glyph, no scrim, and no tap target.
//
//  Shape and vocabulary deliberately echo `StrengthSampleBadge` — outlined rounded
//  rectangle, uppercase, tracked — so the app's card-level labels read as one family.
//  It sits thinner and more widely tracked, because it is a standing mark on a card the
//  user will see repeatedly rather than a one-time notice about the content below it.
//

import SwiftUI

struct PremiumBadge: View {
    private static let title = "PREMIUM"

    /// The system face, matching the card titles it sits above ("Ready to train?"), rather
    /// than the Bebas display face — an earlier pass used Bebas and read as a separate
    /// piece of branding stuck onto the card instead of part of it. Set in caps as a
    /// literal, not via `.uppercased()`, so what is written is what renders.
    private static let font: Font = .system(size: 11, weight: .bold)

    /// Wide enough to read as deliberate letterspacing rather than a rendering accident,
    /// short of where the word stops reading as one unit.
    private static let tracking: CGFloat = 4.0

    var body: some View {
        Text(Self.title)
            .font(Self.font)
            .tracking(Self.tracking)
            // Tracking appends a full space AFTER the last glyph, which drags centred
            // text visually left by that amount. Matching padding on the leading side
            // puts the word back in the optical centre of its own frame.
            .padding(.leading, Self.tracking)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            // Black, not the card's own surface: the badge reads as a cut-out in the card
            // rather than a panel resting on it, which is what keeps a plain outlined
            // rectangle from looking like an unstyled placeholder.
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.white, lineWidth: 1)
            )
            // Decoration, not a control — never take a tap that belongs to the card.
            .allowsHitTesting(false)
            .accessibilityLabel("Premium feature")
    }
}

#Preview {
    VStack(spacing: 20) {
        PremiumBadge()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(white: 0.14))
}
