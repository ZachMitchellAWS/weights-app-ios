//
//  AuthView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import SwiftUI
import AuthenticationServices

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
    @State private var isSubmitting = false
    @Environment(\.openURL) private var openURL
    @FocusState private var focusedField: Field?
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)


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
                Color(white: 0.08)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        // Logo/Title (hidden when keyboard is visible or submitting)
                        if !isKeyboardVisible && !isSubmitting {
                            VStack(spacing: 12) {
                                Image("LiftTheBullIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
                                    .foregroundStyle(Color.appLogoColor)

                                VStack(spacing: 4) {
                                    Text("Lift the Bull")
                                        .font(.bebasNeue(size: 34))
                                        .foregroundStyle(.white)

                                    Text("Progressive Overload Tracker")
                                        .font(.inter(size: 14))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                            .padding(.top, 60)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            // Add minimal top padding when keyboard is visible or submitting
                            Spacer()
                                .frame(height: 20)
                        }

                        // Tab Selector - Segmented Picker Style
                        ZStack(alignment: .center) {
                            // Background
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(white: 0.1))
                                .frame(height: 40)

                            // Sliding indicator
                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.appAccent)
                                    .frame(width: geometry.size.width / 2 - 6, height: 34)
                                    .offset(x: authMode == .signUp ? 3 : geometry.size.width / 2 + 3, y: 3)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: authMode)
                            }
                            .frame(height: 40)

                            // Tab buttons
                            HStack(spacing: 0) {
                                Button {
                                    hapticFeedback.impactOccurred()
                                    authMode = .signUp
                                    authViewModel.errorMessage = nil
                                } label: {
                                    Text("Sign Up")
                                        .font(.interSemiBold(size: 14))
                                        .foregroundStyle(authMode == .signUp ? .black : .white.opacity(0.5))
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .frame(height: 40)

                                Button {
                                    hapticFeedback.impactOccurred()
                                    authMode = .login
                                    authViewModel.errorMessage = nil
                                } label: {
                                    Text("Login")
                                        .font(.interSemiBold(size: 14))
                                        .foregroundStyle(authMode == .login ? .black : .white.opacity(0.5))
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .frame(height: 40)
                            }
                        }
                        .frame(height: 40)
                        .padding(.horizontal, 32)

                        // Auth Form
                        VStack(spacing: 20) {
                            // Email Field
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Email")
                                    .font(.interSemiBold(size: 14))
                                    .foregroundStyle(.white.opacity(0.7))

                                TextField("", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .font(.inter(size: 16))
                                    .padding(.horizontal, 12)
                                    .frame(height: 40)
                                    .background(Color(white: 0.12))
                                    .cornerRadius(8)
                                    .foregroundStyle(.white)
                                    .focused($focusedField, equals: .email)

                                if !email.isEmpty && !isValidEmail && focusedField != .email {
                                    Text("Please enter a valid email address")
                                        .font(.inter(size: 12))
                                        .foregroundStyle(.red)
                                }
                            }

                            // Password Field
                            VStack(alignment: .leading, spacing: 6) {
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
                                    .textContentType(authMode == .signUp ? .newPassword : .password)
                                    .font(.inter(size: 16))
                                    .focused($focusedField, equals: .password)

                                    Button {
                                        showPassword.toggle()
                                    } label: {
                                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 40)
                                .background(Color(white: 0.12))
                                .cornerRadius(8)
                                .foregroundStyle(.white)

                                if !password.isEmpty && password.count < 8 && focusedField != .password {
                                    Text("Password must be at least 8 characters")
                                        .font(.inter(size: 12))
                                        .foregroundStyle(.red)
                                }
                            }

                            // Forgot Password (only in login mode) / Spacer for sign up
                            if authMode == .login {
                                Button {
                                    showForgotPassword = true
                                } label: {
                                    Text("Forgot Password?")
                                        .font(.inter(size: 14))
                                        .foregroundStyle(Color.appAccent)
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                // Invisible spacer to match login layout
                                Text(" ")
                                    .font(.inter(size: 14))
                                    .frame(maxWidth: .infinity)
                            }

                            // Error Message
                            if let error = authViewModel.errorMessage {
                                Text(error)
                                    .font(.inter(size: 12))
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }

                            // Submit Button
                            Button {
                                hapticFeedback.impactOccurred()
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
                                            .font(.interSemiBold(size: 14))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(Color.appAccent)
                                .cornerRadius(10)
                                .foregroundStyle(.black)
                            }
                            .disabled(authViewModel.isLoading || !canSubmit)
                            // .opacity((authViewModel.isLoading || !canSubmit) ? 0.6 : 1.0)

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
                            SignInWithAppleButton(authMode == .signUp ? .signUp : .signIn) { request in
                                request.requestedScopes = [.fullName, .email]
                            } onCompletion: { result in
                                handleAppleSignIn(result)
                            }
                            .signInWithAppleButtonStyle(.white)
                            .frame(height: 44)
                            .cornerRadius(10)
                            .id(authMode)

                            // Terms and Privacy footer
                            VStack(spacing: 4) {
                                Text("By signing up you agree to the")
                                    .font(.inter(size: 12))
                                    .foregroundStyle(.white.opacity(0.5))

                                HStack(spacing: 4) {
                                    Button {
                                        openURL(SubscriptionConfig.termsURL)
                                    } label: {
                                        Text("Terms and Conditions")
                                            .font(.inter(size: 12))
                                            .foregroundStyle(Color.appAccent)
                                    }

                                    Text("and")
                                        .font(.inter(size: 12))
                                        .foregroundStyle(.white.opacity(0.5))

                                    Button {
                                        openURL(SubscriptionConfig.privacyURL)
                                    } label: {
                                        Text("Privacy Policy")
                                            .font(.inter(size: 12))
                                            .foregroundStyle(Color.appAccent)
                                    }
                                }
                            }
                            .padding(.top, 16)
                        }
                        .padding(.horizontal, 32)

                        Spacer(minLength: 40)
                    }
                }

                // Toast Notification
                if showToast {
                    VStack {
                        Spacer()
                        Text(toastMessage)
                            .font(.inter(size: 14))
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
        // Freeze layout and dismiss keyboard before auth transition
        isSubmitting = true
        focusedField = nil

        if authMode == .signUp {
            let result = await authViewModel.createUser(email: email, password: password)
            if result != .success {
                // Reset layout freeze on failure
                isSubmitting = false
            }
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
            let result = await authViewModel.login(email: email, password: password)
            if result != .success {
                // Reset layout freeze on failure
                isSubmitting = false
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

