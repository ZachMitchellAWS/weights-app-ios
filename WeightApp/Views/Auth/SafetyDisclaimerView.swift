//
//  SafetyDisclaimerView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/1/26.
//

import SwiftUI

struct SafetyDisclaimerView: View {
    let onContinue: () -> Void

    @State private var titleOpacity: Double = 0
    @State private var itemOpacity: [Double] = [0, 0, 0, 0]
    @State private var footerOpacity: Double = 0

    private let safetyPoints: [(icon: String, label: String, description: String)] = [
        ("shield.checkered", "Consult Your Doctor",
         "This app is not a substitute for professional medical advice. Consult a physician before starting or modifying any exercise program."),
        ("figure.strengthtraining.traditional", "Know Your Limits",
         "You are solely responsible for selecting appropriate weights and exercises. Stop immediately if you experience pain or discomfort."),
        ("exclamationmark.triangle", "Risk of Injury",
         "Weightlifting carries inherent risk of injury. Always use proper form, appropriate equipment, and a spotter when needed."),
        ("info.circle", "Not Professional Guidance",
         "Suggestions and calculations provided by this app are estimates only and do not replace qualified coaching or training.")
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.12), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("Your Safety Comes First")
                    .font(.bebasNeue(size: 34))
                    .foregroundStyle(.white)
                    .opacity(titleOpacity)

                Spacer()
                    .frame(height: 36)

                VStack(spacing: 24) {
                    ForEach(Array(safetyPoints.enumerated()), id: \.offset) { index, point in
                        SafetyPointRow(
                            icon: point.icon,
                            label: point.label,
                            description: point.description
                        )
                        .opacity(itemOpacity[index])
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                Text("By continuing, you acknowledge that you use this app at your own risk.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
                    .opacity(footerOpacity)

                Button {
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(.interSemiBold(size: 14))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.appAccent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
                .opacity(footerOpacity)
            }
        }
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.4)) {
            titleOpacity = 1.0
        }

        for index in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(index) * 0.15) {
                withAnimation(.easeOut(duration: 0.4)) {
                    itemOpacity[index] = 1.0
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + 4 * 0.15) {
            withAnimation(.easeOut(duration: 0.4)) {
                footerOpacity = 1.0
            }
        }
    }
}

// MARK: - Safety Point Row

private struct SafetyPointRow: View {
    let icon: String
    let label: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.appAccent)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.interSemiBold(size: 15))
                    .foregroundStyle(.white)

                Text(description)
                    .font(.inter(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
