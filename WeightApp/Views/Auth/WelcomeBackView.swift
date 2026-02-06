//
//  WelcomeBackView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/29/26.
//

import SwiftUI

struct WelcomeBackView: View {
    let onComplete: () -> Void

    @State private var isVisible = false
    @State private var isExiting = false

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .opacity(isVisible && !isExiting ? 1 : 0)

            // Popup card
            VStack(spacing: 12) {
                Text("Welcome Back")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Text("Let's keep making progress")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.appAccent.opacity(0.3), lineWidth: 1)
                    )
            )
            .scaleEffect(isVisible && !isExiting ? 1 : 0.8)
            .opacity(isVisible && !isExiting ? 1 : 0)
        }
        .onAppear {
            // Animate in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                isVisible = true
            }

            // Auto-dismiss after 1.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.25)) {
                    isExiting = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onComplete()
                }
            }
        }
    }
}
