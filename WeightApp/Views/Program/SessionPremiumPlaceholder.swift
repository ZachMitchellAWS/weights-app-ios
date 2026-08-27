//
//  SessionPremiumPlaceholder.swift
//  WeightApp
//
//  What a free user sees on the Session tab.
//
//  Deliberately NOT the blur-and-lock treatment used elsewhere. Blurring hides the one
//  thing that would sell this — a draft is a genuinely nice-looking object, and the
//  fastest way to explain Sessions is to let someone read one. So the sample is shown
//  fully legible, plainly marked as a sample, and the tab sells itself by demonstration
//  rather than by obstruction.
//
//  The sample uses the real draft card's vocabulary — same effort tiles, same per-lift
//  reasoning — so what a user gets after upgrading is recognisably the thing they were
//  shown. It deliberately omits the real card's "Built 9:41 AM" marker: that timestamp
//  earns its place by telling you a real draft is current, and inventing one here would
//  be a small fiction in service of nothing.
//
//  The screen is hero → sample → CTA, with nothing between. The sample is the argument;
//  feature bullets sitting under it only restated what it had already demonstrated, and
//  more weakly.
//

import SwiftUI

struct SessionPremiumPlaceholder: View {
    let onUpgrade: () -> Void

    @State private var shimmer = false

    var body: some View {
        VStack(spacing: 20) {
            hero
            SessionSampleCard()

            Button(action: onUpgrade) {
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Unlock Smart Sessions")
                        .font(.interSemiBold(size: 16))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.appAccent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Text("Logging your lifts is always free.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(0.10))
                    .frame(width: 64, height: 64)
                    .scaleEffect(shimmer ? 1.06 : 0.96)

                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }

            Text("Show up. We'll pick.")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            // "How hard to push them" is what the effort levels actually are — "how to
            // do them" implied form or technique coaching, which this does not do. The
            // credibility claim is the tail, and the sample below is what backs it up.
            //
            // Two authored lines rather than one wrapping string: the break belongs after
            // the comma, so the claim and its basis each get their own line instead of
            // breaking wherever the width happens to land.
            VStack(spacing: 2) {
                Text("Which lifts and how hard to push them,")
                Text("based on your recent training.")
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
        }
    }
}
