//
//  WelcomeBackView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/29/26.
//

import SwiftUI

struct WelcomeBackView: View {
    let onComplete: () -> Void

    @State private var logoVisible = false
    @State private var textVisible = false
    @State private var isExiting = false

    var body: some View {
        ZStack {
            // Full-screen gradient background
            LinearGradient(
                colors: [Color(white: 0.12), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Logo
                Image("LiftTheBullIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .foregroundStyle(Color.appLogoColor)
                    .opacity(logoVisible ? 1 : 0)
                    .scaleEffect(logoVisible ? 1 : 0.8)

                // Text content
                VStack(spacing: 16) {
                    Text("Welcome Back")
                        .font(.bebasNeue(size: 42))
                        .foregroundStyle(.white)

                    Text("Let's keep making progress")
                        .font(.inter(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .opacity(textVisible ? 1 : 0)
                .offset(y: textVisible ? 0 : 20)

                Spacer()
                Spacer()
            }
            .opacity(isExiting ? 0 : 1)
            .scaleEffect(isExiting ? 0.95 : 1)
        }
        .onAppear {
            // Animate logo in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                logoVisible = true
            }

            // Animate text in with slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 0.4)) {
                    textVisible = true
                }
            }

            // Auto-dismiss after 2.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    isExiting = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onComplete()
                }
            }
        }
    }
}
