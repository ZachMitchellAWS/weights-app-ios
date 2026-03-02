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
        // Hard delete all LiftSet
        let allLiftSet = (try? modelContext.fetch(FetchDescriptor<LiftSet>())) ?? []
        for liftSet in allLiftSet {
            modelContext.delete(liftSet)
        }

        // Hard delete all Estimated1RM
        let allEstimated1RM = (try? modelContext.fetch(FetchDescriptor<Estimated1RM>())) ?? []
        for estimated in allEstimated1RM {
            modelContext.delete(estimated)
        }

        // Hard delete all Exercise (both custom and built-in since they're synced)
        let allExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        for exercise in allExercises {
            modelContext.delete(exercise)
        }

        // Hard delete UserProperties
        let allUserProperties = (try? modelContext.fetch(FetchDescriptor<UserProperties>())) ?? []
        for properties in allUserProperties {
            modelContext.delete(properties)
        }

        // Hard delete all WorkoutSplits
        let allSplits = (try? modelContext.fetch(FetchDescriptor<WorkoutSplit>())) ?? []
        for split in allSplits {
            modelContext.delete(split)
        }

        // Hard delete EntitlementGrants
        let allEntitlements = (try? modelContext.fetch(FetchDescriptor<EntitlementGrant>())) ?? []
        for grant in allEntitlements {
            modelContext.delete(grant)
        }

        // Clear active day/split preferences and seed flags
        WorkoutSplitStore.setActiveDayId(nil)
        WorkoutSplitStore.setActiveSplitId(nil)
        UserDefaults.standard.removeObject(forKey: "workoutSplitsSeeded")

        try? modelContext.save()
    }
}
