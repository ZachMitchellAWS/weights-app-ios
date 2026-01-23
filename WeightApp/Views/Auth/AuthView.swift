//
//  AuthView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import SwiftUI

struct AuthView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var authMode: AuthMode = .signUp
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showForgotPassword = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var isKeyboardVisible = false
    @FocusState private var focusedField: Field?

    enum Field {
        case email
        case password
    }

    enum AuthMode {
        case signUp
        case login
    }

    private var isValidEmail: Bool {
        email.contains("@") && email.contains(".")
    }

    private var canSubmit: Bool {
        isValidEmail && password.count >= 8
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        // Logo/Title (hidden when keyboard is visible)
                        if !isKeyboardVisible {
                            VStack(spacing: 12) {
                                Image(systemName: "dumbbell.fill")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.cyan)

                                Text("WeightApp")
                                    .font(.largeTitle.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.top, 60)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            // Add minimal top padding when keyboard is visible
                            Spacer()
                                .frame(height: 20)
                        }

                        // Tab Selector
                        HStack(spacing: 0) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    authMode = .signUp
                                }
                            } label: {
                                Text("Sign Up")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(authMode == .signUp ? Color.cyan : Color.clear)
                                    .foregroundStyle(authMode == .signUp ? .black : .white.opacity(0.6))
                            }

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    authMode = .login
                                }
                            } label: {
                                Text("Login")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(authMode == .login ? Color.cyan : Color.clear)
                                    .foregroundStyle(authMode == .login ? .black : .white.opacity(0.6))
                            }
                        }
                        .background(Color(white: 0.12))
                        .cornerRadius(10)
                        .padding(.horizontal, 32)

                        // Auth Form
                        VStack(spacing: 20) {
                            // Email Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))

                                TextField("", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .font(.body)
                                    .padding(14)
                                    .background(Color(white: 0.12))
                                    .cornerRadius(10)
                                    .foregroundStyle(.white)
                                    .focused($focusedField, equals: .email)

                                if !email.isEmpty && !isValidEmail && focusedField != .email {
                                    Text("Please enter a valid email address")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            // Password Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))

                                HStack {
                                    Group {
                                        if showPassword {
                                            TextField("", text: $password)
                                        } else {
                                            SecureField("", text: $password)
                                        }
                                    }
                                    .textContentType(authMode == .signUp ? .newPassword : .password)
                                    .font(.body)
                                    .focused($focusedField, equals: .password)

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

                                if !password.isEmpty && password.count < 8 && focusedField != .password {
                                    Text("Password must be at least 8 characters")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            // Forgot Password (only in login mode)
                            if authMode == .login {
                                Button {
                                    showForgotPassword = true
                                } label: {
                                    Text("Forgot Password?")
                                        .font(.subheadline)
                                        .foregroundStyle(.cyan)
                                }
                                .frame(maxWidth: .infinity)
                            }

                            // Error Message
                            if let error = authViewModel.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }

                            // Submit Button
                            Button {
                                Task {
                                    await handleSubmit()
                                }
                            } label: {
                                HStack {
                                    if authViewModel.isLoading {
                                        ProgressView()
                                            .tint(.black)
                                    } else {
                                        Text(authMode == .signUp ? "Sign Up" : "Login")
                                            .font(.headline)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(.cyan)
                                .cornerRadius(12)
                                .foregroundStyle(.black)
                            }
                            .disabled(authViewModel.isLoading || !canSubmit)
                            .opacity((authViewModel.isLoading || !canSubmit) ? 0.6 : 1.0)
                        }
                        .padding(.horizontal, 32)

                        // Bottom Text
                        VStack(spacing: 8) {
                            Text(authMode == .signUp ? "Already have an account?" : "Don't have an account?")
                                .foregroundStyle(.white.opacity(0.7))

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    authMode = authMode == .signUp ? .login : .signUp
                                    authViewModel.errorMessage = nil
                                }
                            } label: {
                                Text(authMode == .signUp ? "Login" : "Sign Up")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.cyan)
                            }
                        }
                        .font(.subheadline)

                        Spacer(minLength: 40)
                    }
                }

                // Toast Notification
                if showToast {
                    VStack {
                        Spacer()
                        Text(toastMessage)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(20)
                            .background(Color(white: 0.15))
                            .cornerRadius(10)
                            .shadow(radius: 10)
                            .padding(.bottom, 50)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .navigationDestination(isPresented: $showForgotPassword) {
                ForgotPasswordView(authViewModel: authViewModel)
            }
            .onAppear {
                NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        isKeyboardVisible = true
                    }
                }
                NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        isKeyboardVisible = false
                    }
                }
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
                NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
            }
        }
    }

    private func handleSubmit() async {
        if authMode == .signUp {
            let result = await authViewModel.createUser(email: email, password: password)
            if result == .userAlreadyExists {
                // Show toast and switch to login
                toastMessage = "Try logging in instead"
                withAnimation(.easeInOut(duration: 0.3)) {
                    showToast = true
                }

                // Hide toast after 3.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showToast = false
                    }
                }

                // Switch to login mode after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        authMode = .login
                        authViewModel.errorMessage = nil
                    }
                }
            }
        } else {
            await authViewModel.login(email: email, password: password)
        }
    }
}
