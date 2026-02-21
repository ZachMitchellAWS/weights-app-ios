//
//  AccountDetailView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }
            .alert("Logout", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    Task {
                        await authViewModel.logout {
                            hardDeleteAllData()
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to logout? All local data will be deleted.")
            }
        }
    }

    private func hardDeleteAllData() {
        // Hard delete all LiftSets
        let allLiftSets = (try? modelContext.fetch(FetchDescriptor<LiftSets>())) ?? []
        for liftSet in allLiftSets {
            modelContext.delete(liftSet)
        }

        // Hard delete all Estimated1RMs
        let allEstimated1RMs = (try? modelContext.fetch(FetchDescriptor<Estimated1RMs>())) ?? []
        for estimated in allEstimated1RMs {
            modelContext.delete(estimated)
        }

        // Hard delete all Exercises (both custom and built-in since they're synced)
        let allExercises = (try? modelContext.fetch(FetchDescriptor<Exercises>())) ?? []
        for exercise in allExercises {
            modelContext.delete(exercise)
        }

        // Hard delete UserProperties
        let allUserProperties = (try? modelContext.fetch(FetchDescriptor<UserProperties>())) ?? []
        for properties in allUserProperties {
            modelContext.delete(properties)
        }

        // Hard delete all WorkoutSequences
        let allSequences = (try? modelContext.fetch(FetchDescriptor<WorkoutSequence>())) ?? []
        for sequence in allSequences {
            modelContext.delete(sequence)
        }

        // Hard delete Entitlements
        let allEntitlements = (try? modelContext.fetch(FetchDescriptor<Entitlements>())) ?? []
        for entitlement in allEntitlements {
            modelContext.delete(entitlement)
        }

        // Clear active sequence preference
        WorkoutSequenceStore.setActiveSequenceId(nil)

        try? modelContext.save()
    }
}
