//
//  WelcomeView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/17/26.
//

import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void
    var splashVisible: Bool = false

    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var featureOpacity: [Double] = [0, 0, 0]

    var body: some View {
        ZStack {
            // Full-screen gradient background
            LinearGradient(
                colors: [Color(white: 0.12), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo + Title
                VStack(spacing: 12) {
                    Image("LiftTheBullIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .foregroundStyle(Color.appLogoColor)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)

                    VStack(spacing: 4) {
                        Text("Lift the Bull")
                            .font(.bebasNeue(size: 38))
                            .foregroundStyle(.white)

                        Text("Strength Tracker")
                            .font(.inter(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .opacity(logoOpacity)
                }

                Spacer()
                    .frame(height: 48)

                // Feature highlights
                VStack(spacing: 24) {
                    FeatureRow(
                        icon: "dumbbell.fill",
                        text: "Track every set with intensity-based logging"
                    )
                    .opacity(featureOpacity[0])

                    FeatureRow(
                        icon: "chart.line.uptrend.xyaxis",
                        text: "Watch your estimated one-rep max grow over time"
                    )
                    .opacity(featureOpacity[1])

                    FeatureRow(
                        icon: "flame.fill",
                        text: "Follow smart suggestions to get stronger"
                    )
                    .opacity(featureOpacity[2])
                }
                .padding(.horizontal, 40)

                Spacer()

                // CTA Button
                Button {
                    onContinue()
                } label: {
                    Text("Get Started")
                        .font(.interSemiBold(size: 14))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.appAccent)
                        .foregroundStyle(.black)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
                .opacity(featureOpacity[2])
            }
        }
        .onAppear {
            if !splashVisible {
                startAnimations()
            }
        }
        .onChange(of: splashVisible) { _, visible in
            if !visible {
                startAnimations()
            }
        }
    }
    private func startAnimations() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }

        for index in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(index) * 0.15) {
                withAnimation(.easeOut(duration: 0.4)) {
                    featureOpacity[index] = 1.0
                }
            }
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.appAccent)
                .frame(width: 32, alignment: .center)

            Text(text)
                .font(.inter(size: 15))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
