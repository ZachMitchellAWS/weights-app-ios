//
//  ResourcesHintPopup.swift
//  WeightApp
//
//  Shown once, immediately after the lift-tutorial popup is dismissed (whether
//  the user watched the tour or skipped it). A small acknowledgment card that
//  tells them the tour can be re-watched anytime from More → Resources. A poster
//  thumbnail makes it clear at a glance this is the tutorial. Tapping "Got it" or
//  the background dismisses it. Styled to match OnboardingTutorialPopup.
//

import SwiftUI

struct ResourcesHintPopup: View {
    let resource: Resource?
    let onAcknowledge: () -> Void

    @State private var cardScale: CGFloat = 0.92
    @State private var cardOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture { onAcknowledge() }

            VStack(spacing: 0) {
                thumbnail
                title
                    .padding(.top, 16)
                bodyCopy
                    .padding(.top, 6)
                pathChip
                    .padding(.top, 16)
                okButton
                    .padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 22)
            .frame(maxWidth: 320)
            .background(cardBackground)
            .scaleEffect(cardScale)
            .opacity(cardOpacity)
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.28)) {
                cardScale = 1.0
                cardOpacity = 1.0
            }
        }
    }

    // MARK: - Sections

    /// A small poster of the tour so it's obvious at a glance which video this is.
    private var thumbnail: some View {
        AsyncImage(url: resource?.posterURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty, .failure:
                ZStack {
                    Color.white.opacity(0.05)
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.appAccent.opacity(0.5))
                }
            @unknown default:
                Color.white.opacity(0.05)
            }
        }
        .frame(width: 170, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .overlay(
            ZStack {
                Circle().fill(Color.black.opacity(0.55)).frame(width: 44, height: 44)
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.appAccent)
            }
            .allowsHitTesting(false)
        )
    }

    private var title: some View {
        VStack(spacing: 6) {
            Text("Quick Tour")
                .font(.interSemiBold(size: 11))
                .tracking(3)
                .textCase(.uppercase)
                .foregroundStyle(Color.appAccent)
            Text("Rewatch Anytime")
                .font(.bebasNeue(size: 32))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(.white)
        }
    }

    private var bodyCopy: some View {
        Text("You'll find it here whenever you want a refresher.")
            .font(.inter(size: 14))
            .foregroundStyle(.white.opacity(0.72))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A visual "More → Resources" breadcrumb using the real tab + row icons.
    private var pathChip: some View {
        HStack(spacing: 8) {
            chipItem(icon: "arrow.forward.square", label: "More")
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
            chipItem(icon: "play.rectangle.on.rectangle", label: "Resources")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func chipItem(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appAccent)
            Text(label)
                .font(.interSemiBold(size: 13))
                .foregroundStyle(.white)
        }
    }

    private var okButton: some View {
        Button {
            onAcknowledge()
        } label: {
            Text("Got it")
                .font(.interSemiBold(size: 16))
                .tracking(0.5)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.appAccent)
                )
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(white: 0.09))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 28, x: 0, y: 14)
    }
}
