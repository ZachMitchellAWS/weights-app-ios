//
//  FeedbackView.swift
//  WeightApp
//

import SwiftUI

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private let maxLength = 2000

    var body: some View {
        VStack(spacing: 16) {
            Text("We'd love to hear from you! Whether it's a bug you've found, a feature idea, or just general thoughts, we're all ears.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.top, 8)

            TextEditor(text: $message)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.systemGray6))
                }
                .padding(.horizontal)
                .frame(minHeight: 150)

            HStack {
                Text("\(message.count)/\(maxLength)")
                    .font(.caption)
                    .foregroundStyle(message.count > maxLength ? .red : .secondary)
                Spacer()
            }
            .padding(.horizontal)

            Button {
                submitFeedback()
            } label: {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                } else {
                    Text("Submit")
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appAccent)
            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.count > maxLength || isSubmitting)
            .padding(.horizontal)

            Spacer()
        }
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .alert("Thanks!", isPresented: $showSuccessAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your feedback has been submitted. We appreciate you taking the time!")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func submitFeedback() {
        isSubmitting = true
        Task {
            do {
                let _ = try await APIService.shared.submitFeedback(message: message.trimmingCharacters(in: .whitespacesAndNewlines))
                await MainActor.run {
                    isSubmitting = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}
