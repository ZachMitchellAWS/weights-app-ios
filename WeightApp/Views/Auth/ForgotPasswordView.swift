//
//  ForgotPasswordView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import SwiftUI

struct ForgotPasswordView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showNewPassword = false
    @State private var showConfirmPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showCodeEntry = false
    @State private var showPasswordReset = false

    private var passwordsMatch: Bool {
        newPassword == confirmPassword && !newPassword.isEmpty
    }

    private var canSubmitCode: Bool {
        code.count == 6 && code.allSatisfy { $0.isNumber }
    }

    private var canSubmitPassword: Bool {
        passwordsMatch && newPassword.count >= 8
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Title
                    VStack(spacing: 12) {
                        Image(systemName: "lock.rotation")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.appAccent)

                        Text("Reset Password")
                            .font(.bebasNeue(size: 38))
                            .foregroundStyle(.white)

                        if !showCodeEntry && !showPasswordReset {
                            Text("Enter your email to receive a reset code")
                                .font(.inter(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        } else if showCodeEntry && !showPasswordReset {
                            Text("Enter the 6-digit code sent to your email")
                                .font(.inter(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        } else {
                            Text("Create your new password")
                                .font(.inter(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                    .padding(.top, 60)

                    // Form Content
                    VStack(spacing: 20) {
                        if !showCodeEntry && !showPasswordReset {
                            // Email Entry Step
                            emailEntryStep
                        } else if showCodeEntry && !showPasswordReset {
                            // Code Entry Step
                            codeEntryStep
                        } else {
                            // Password Reset Step
                            passwordResetStep
                        }

                        // Error/Success Messages
                        if let error = errorMessage {
                            Text(error)
                                .font(.inter(size: 12))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        if let success = successMessage {
                            Text(success)
                                .font(.inter(size: 12))
                                .foregroundStyle(.green)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal, 32)

                    // Back to Login Link
                    Button {
                        dismiss()
                    } label: {
                        Text("Back to Login")
                            .font(.inter(size: 14))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appAccent)
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
    }

    // MARK: - Email Entry Step

    private var emailEntryStep: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Email")
                    .font(.interSemiBold(size: 14))
                    .foregroundStyle(.white.opacity(0.7))

                TextField("", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .font(.inter(size: 16))
                    .padding(12)
                    .background(Color(white: 0.12))
                    .cornerRadius(8)
                    .foregroundStyle(.white)
            }

            Button {
                Task {
                    await initiatePasswordReset()
                }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text("Send Reset Code")
                            .font(.interSemiBold(size: 14))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.appAccent)
                .cornerRadius(10)
                .foregroundStyle(.black)
            }
            .disabled(isLoading || email.isEmpty)
            .opacity((isLoading || email.isEmpty) ? 0.6 : 1.0)
        }
    }

    // MARK: - Code Entry Step

    private var codeEntryStep: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reset Code")
                    .font(.interSemiBold(size: 14))
                    .foregroundStyle(.white.opacity(0.7))

                TextField("", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .font(.bebasNeue(size: 22))
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(Color(white: 0.12))
                    .cornerRadius(8)
                    .foregroundStyle(.white)
                    .onChange(of: code) { _, newValue in
                        // Limit to 6 digits
                        if newValue.count > 6 {
                            code = String(newValue.prefix(6))
                        }
                        // Remove non-numeric characters
                        code = code.filter { $0.isNumber }
                    }
            }

            Button {
                showPasswordReset = true
                errorMessage = nil
            } label: {
                Text("Verify Code")
                    .font(.interSemiBold(size: 14))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appAccent)
                    .cornerRadius(10)
                    .foregroundStyle(.black)
            }
            .disabled(!canSubmitCode)
            .opacity(canSubmitCode ? 1.0 : 0.6)

            Button {
                Task {
                    await initiatePasswordReset()
                }
            } label: {
                Text("Resend Code")
                    .font(.inter(size: 14))
                    .foregroundStyle(Color.appAccent)
            }
            .disabled(isLoading)
        }
    }

    // MARK: - Password Reset Step

    private var passwordResetStep: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("New Password")
                    .font(.interSemiBold(size: 14))
                    .foregroundStyle(.white.opacity(0.7))

                HStack {
                    Group {
                        if showNewPassword {
                            TextField("", text: $newPassword)
                        } else {
                            SecureField("", text: $newPassword)
                        }
                    }
                    .textContentType(.newPassword)
                    .font(.inter(size: 16))

                    Button {
                        showNewPassword.toggle()
                    } label: {
                        Image(systemName: showNewPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(12)
                .background(Color(white: 0.12))
                .cornerRadius(8)
                .foregroundStyle(.white)

                if !newPassword.isEmpty && newPassword.count < 8 {
                    Text("Password must be at least 8 characters")
                        .font(.inter(size: 12))
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Confirm Password")
                    .font(.interSemiBold(size: 14))
                    .foregroundStyle(.white.opacity(0.7))

                HStack {
                    Group {
                        if showConfirmPassword {
                            TextField("", text: $confirmPassword)
                        } else {
                            SecureField("", text: $confirmPassword)
                        }
                    }
                    .textContentType(.newPassword)
                    .font(.inter(size: 16))

                    Button {
                        showConfirmPassword.toggle()
                    } label: {
                        Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(12)
                .background(Color(white: 0.12))
                .cornerRadius(8)
                .foregroundStyle(.white)

                if !confirmPassword.isEmpty && !passwordsMatch {
                    Text("Passwords do not match")
                        .font(.inter(size: 12))
                        .foregroundStyle(.red)
                }
            }

            Button {
                Task {
                    await confirmPasswordReset()
                }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text("Reset Password")
                            .font(.interSemiBold(size: 14))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.appAccent)
                .cornerRadius(10)
                .foregroundStyle(.black)
            }
            .disabled(isLoading || !canSubmitPassword)
            .opacity((isLoading || !canSubmitPassword) ? 0.6 : 1.0)
        }
    }

    // MARK: - API Calls

    private func initiatePasswordReset() async {
        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            let _ = try await APIService.shared.initiatePasswordReset(email: email)
            showCodeEntry = true
            successMessage = "Reset code sent to your email"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func confirmPasswordReset() async {
        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            let _ = try await APIService.shared.confirmPasswordReset(email: email, code: code, newPassword: newPassword)
            successMessage = "Password reset successfully! Redirecting to login..."
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
