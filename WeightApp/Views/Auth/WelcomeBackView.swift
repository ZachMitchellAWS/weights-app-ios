//
//  WelcomeBackView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/29/26.
//

import SwiftUI

struct WelcomeBackView: View {
    let onComplete: () -> Void

    @State private var buttonEnabled = true

    var body: some View {
        ZStack {
            // Background matching widget style
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                VStack(spacing: 16) {
                    Text("Welcome Back")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Ready to continue your progress?")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()

                // Continue button
                Button {
                    onComplete()
                } label: {
                    Text("Let's Go")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black.opacity(buttonEnabled ? 1 : 0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(buttonEnabled ? Color.appAccent : Color.gray)
                        .cornerRadius(12)
                        .animation(.easeInOut(duration: 0.3), value: buttonEnabled)
                }
                .buttonStyle(.plain)
                .disabled(!buttonEnabled)
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
        }
    }
}
