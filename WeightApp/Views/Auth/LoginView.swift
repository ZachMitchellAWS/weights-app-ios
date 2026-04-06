//
//  LoginView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showRegister = false
    @State private var showForgotPassword = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        // Logo/Title
                        VStack(spacing: 12) {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(Color.appAccent)

                            Text("WeightApp")
                                .font(.bebasNeue(size: 38))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 60)

                        // Login Form
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
                                    .textContentType(.password)
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
                            }

                            // Forgot Password
                            Button {
                                showForgotPassword = true
                            } label: {
                                Text("Forgot Password?")
                                    .font(.inter(size: 14))
                                    .foregroundStyle(Color.appAccent)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)

                            // Error Message
                            if let error = authViewModel.errorMessage {
                                Text(error)
                                    .font(.inter(size: 12))
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }

                            // Login Button
                            Button {
                                Task {
                                    await authViewModel.login(email: email, password: password)
                                }
                            } label: {
                                HStack {
                                    if authViewModel.isLoading {
                                        ProgressView()
                                            .tint(.black)
                                    } else {
                                        Text("Login")
                                            .font(.interSemiBold(size: 17))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.appAccent)
                                .cornerRadius(12)
                                .foregroundStyle(.black)
                            }
                            .disabled(authViewModel.isLoading || email.isEmpty || password.isEmpty)
                            .opacity((authViewModel.isLoading || email.isEmpty || password.isEmpty) ? 0.6 : 1.0)

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

                            // Sign in with Apple
                            SignInWithAppleButton(.signIn) { request in
                                request.requestedScopes = [.fullName, .email]
                            } onCompletion: { result in
                                handleAppleSignIn(result)
                            }
                            .signInWithAppleButtonStyle(.white)
                            .frame(height: 50)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 32)

                        // Sign Up Link
                        HStack {
                            Text("Don't have an account?")
                                .foregroundStyle(.white.opacity(0.7))
                            Button {
                                showRegister = true
                            } label: {
                                Text("Sign Up")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                        .font(.inter(size: 14))

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationDestination(isPresented: $showRegister) {
                RegisterView(authViewModel: authViewModel)
            }
            .navigationDestination(isPresented: $showForgotPassword) {
                ForgotPasswordView(authViewModel: authViewModel)
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
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
