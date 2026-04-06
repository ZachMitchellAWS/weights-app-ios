//
//  RegisterView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import SwiftUI
import AuthenticationServices

struct RegisterView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false

    private var passwordsMatch: Bool {
        password == confirmPassword && !password.isEmpty
    }

    private var isValidEmail: Bool {
        email.contains("@") && email.contains(".")
    }

    private var canSubmit: Bool {
        isValidEmail && passwordsMatch && password.count >= 8
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Title
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.appAccent)

                        Text("Create Account")
                            .font(.bebasNeue(size: 38))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 60)

                    // Register Form
                    VStack(spacing: 20) {
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.interSemiBold(size: 14))
                                .foregroundStyle(.white.opacity(0.7))

                            TextField("", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .font(.inter(size: 16))
                                .padding(14)
                                .background(Color(white: 0.12))
                                .cornerRadius(10)
                                .foregroundStyle(.white)

                            if !email.isEmpty && !isValidEmail {
                                Text("Please enter a valid email address")
                                    .font(.inter(size: 12))
                                    .foregroundStyle(.red)
                            }
                        }

                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.interSemiBold(size: 14))
                                .foregroundStyle(.white.opacity(0.7))

                            HStack {
                                Group {
                                    if showPassword {
                                        TextField("", text: $password)
                                    } else {
                                        SecureField("", text: $password)
                                    }
                                }
                                .textContentType(.newPassword)
                                .font(.inter(size: 16))

                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            .padding(14)
                            .background(Color(white: 0.12))
                            .cornerRadius(10)
                            .foregroundStyle(.white)

                            if !password.isEmpty && password.count < 8 {
                                Text("Password must be at least 8 characters")
                                    .font(.inter(size: 12))
                                    .foregroundStyle(.red)
                            }
                        }

                        // Confirm Password Field
                        VStack(alignment: .leading, spacing: 8) {
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
                            .padding(14)
                            .background(Color(white: 0.12))
                            .cornerRadius(10)
                            .foregroundStyle(.white)

                            if !confirmPassword.isEmpty && !passwordsMatch {
                                Text("Passwords do not match")
                                    .font(.inter(size: 12))
                                    .foregroundStyle(.red)
                            }
                        }

                        // Error Message
                        if let error = authViewModel.errorMessage {
                            Text(error)
                                .font(.inter(size: 12))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Create Account Button
                        Button {
                            Task {
                                await authViewModel.createUser(email: email, password: password)
                            }
                        } label: {
                            HStack {
                                if authViewModel.isLoading {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Text("Create Account")
                                        .font(.interSemiBold(size: 17))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.appAccent)
                            .cornerRadius(12)
                            .foregroundStyle(.black)
                        }
                        .disabled(authViewModel.isLoading || !canSubmit)
                        .opacity((authViewModel.isLoading || !canSubmit) ? 0.6 : 1.0)

                        // Divider with "or" text
                        HStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 1)
                            Text("or")
                                .font(.inter(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 1)
                        }
                        .padding(.top, 8)

                        // Sign up with Apple
                        SignInWithAppleButton(.signUp) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleAppleSignUp(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 50)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 32)

                    // Back to Login Link
                    HStack {
                        Text("Already have an account?")
                            .foregroundStyle(.white.opacity(0.7))
                        Button {
                            dismiss()
                        } label: {
                            Text("Login")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appAccent)
                        }
                    }
                    .font(.inter(size: 14))

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

    private func handleAppleSignUp(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            Task {
                _ = await authViewModel.handleAppleAuthorization(authorization)
            }
        case .failure(let error):
            let authError = error as? ASAuthorizationError
            if authError?.code != .canceled {
                authViewModel.errorMessage = error.localizedDescription
            }
        }
    }
}
