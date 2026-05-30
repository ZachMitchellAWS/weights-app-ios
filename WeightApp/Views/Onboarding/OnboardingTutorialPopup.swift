//
//  OnboardingTutorialPopup.swift
//  WeightApp
//
//  Compelling tutorial card shown once, immediately after the onboarding +
//  upsell flow completes (either path — subscribed or dismissed). Centered
//  card with the YouTube thumbnail, title, and a big amber Play CTA. Tapping
//  Play opens `ResourcePlayerView` fullscreen; closing the player auto-
//  dismisses the popup. Tapping X dismisses the popup without playing.
//

import SwiftUI

struct OnboardingTutorialPopup: View {
    let resource: Resource
    let onDismiss: () -> Void

    @State private var showPlayer = false
    @State private var cardScale: CGFloat = 0.92
    @State private var cardOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                poster
                    .padding(.top, 18)
                bodyCopy
                    .padding(.top, 16)
                playButton
                    .padding(.top, 22)
                skipButton
                    .padding(.top, 10)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 22)
            .frame(maxWidth: 360)
            .background(cardBackground)
            .overlay(closeButton, alignment: .topTrailing)
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
        .fullScreenCover(isPresented: $showPlayer) {
            ResourcePlayerView(resource: resource)
        }
        .onChange(of: showPlayer) { wasShowing, isShowing in
            // When the player dismisses (true → false), close the popup too
            // so the user lands cleanly on the main tab view.
            if wasShowing && !isShowing {
                onDismiss()
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 6) {
            Text("Quick Tour")
                .font(.interSemiBold(size: 11))
                .tracking(3)
                .textCase(.uppercase)
                .foregroundStyle(Color.appAccent)
            Text(resource.title)
                .font(.bebasNeue(size: 34))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private var poster: some View {
        Button {
            showPlayer = true
        } label: {
            posterContent
        }
        .buttonStyle(.plain)
    }

    private var posterContent: some View {
        AsyncImage(url: resource.posterURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty, .failure:
                ZStack {
                    Color.white.opacity(0.04)
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.appAccent.opacity(0.5))
                }
            @unknown default:
                Color.white.opacity(0.04)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .overlay(
            // Subtle amber play-disc cue on the poster itself
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 64, height: 64)
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.appAccent)
            }
            .allowsHitTesting(false)
        )
    }

    private var bodyCopy: some View {
        VStack(spacing: 6) {
            if let subtitle = resource.subtitle {
                Text(subtitle)
                    .font(.inter(size: 14))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
            Text("\(resource.durationLabel) · Watch the core loop")
                .font(.interSemiBold(size: 10))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.appAccent.opacity(0.75))
        }
    }

    private var playButton: some View {
        Button {
            showPlayer = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("Watch Now")
                    .font(.interSemiBold(size: 16))
                    .tracking(0.5)
            }
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

    private var skipButton: some View {
        Button {
            onDismiss()
        } label: {
            Text("Maybe later")
                .font(.inter(size: 13))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .padding(.trailing, 12)
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
