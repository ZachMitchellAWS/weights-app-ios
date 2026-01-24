//
//  AccountDetailView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import SwiftUI

struct AccountDetailView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showLogoutConfirmation = false

    private var email: String {
        KeychainService.shared.getEmail() ?? "Not available"
    }

    private var userId: String {
        KeychainService.shared.getUserId() ?? "Not available"
    }

    private var createdDate: String {
        guard let createdDatetimeString = KeychainService.shared.getCreatedDatetime() else {
            return "Not available"
        }

        // Parse ISO8601 datetime and format it
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: createdDatetimeString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .long
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }

        return createdDatetimeString
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                Form {
                    Section {
                        HStack {
                            Text("Email")
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Text(email)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.trailing)
                        }

                        HStack {
                            Text("User ID")
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Text(userId)
                                .foregroundStyle(.white)
                                .font(.system(.body, design: .monospaced))
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }

                        HStack {
                            Text("Created")
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Text(createdDate)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.trailing)
                        }
                    } header: {
                        Text("Account Information")
                    }

                    Section {
                        Button(role: .destructive) {
                            showLogoutConfirmation = true
                        } label: {
                            HStack {
                                Text("Logout")
                                Spacer()
                                if authViewModel.isLoading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.right.square")
                                }
                            }
                        }
                        .disabled(authViewModel.isLoading)
                    } footer: {
                        Text("Log out and return to the login screen.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .alert("Logout", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    Task {
                        await authViewModel.logout()
                    }
                }
            } message: {
                Text("Are you sure you want to logout?")
            }
        }
    }
}
