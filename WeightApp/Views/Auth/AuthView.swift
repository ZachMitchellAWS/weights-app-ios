//
//  AuthView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import SwiftUI
import SafariServices

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
    @State private var showTermsOfService = false
    @State private var showPrivacyPolicy = false
    @FocusState private var focusedField: Field?
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    private let termsOfServiceURL = URL(string: "https://example.com/terms")!
    private let privacyPolicyURL = URL(string: "https://example.com/privacy")!

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
                                        .font(.largeTitle.weight(.bold))
                                        .foregroundStyle(.white)

                                    Text("Progressive Overload Tracker")
                                        .font(.subheadline)
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
                                        .font(.subheadline.weight(.semibold))
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
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(authMode == .login ? .black : .white.opacity(0.5))
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .frame(height: 40)
                            }
                        }
                        .frame(height: 40)
                        .padding(.horizontal, 40)

                        // Auth Form
                        VStack(spacing: 20) {
                            // Email Field
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Email")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))

                                TextField("", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .font(.body)
                                    .padding(12)
                                    .background(Color(white: 0.12))
                                    .cornerRadius(8)
                                    .foregroundStyle(.white)
                                    .focused($focusedField, equals: .email)

                                if !email.isEmpty && !isValidEmail && focusedField != .email {
                                    Text("Please enter a valid email address")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            // Password Field
                            VStack(alignment: .leading, spacing: 6) {
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
                                .padding(12)
                                .background(Color(white: 0.12))
                                .cornerRadius(8)
                                .foregroundStyle(.white)

                                if !password.isEmpty && password.count < 8 && focusedField != .password {
                                    Text("Password must be at least 8 characters")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            // Forgot Password (only in login mode) / Spacer for sign up
                            if authMode == .login {
                                Button {
                                    showForgotPassword = true
                                } label: {
                                    Text("Forgot Password?")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.appAccent)
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                // Invisible spacer to match login layout
                                Text(" ")
                                    .font(.subheadline)
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
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.appAccent)
                                .cornerRadius(10)
                                .foregroundStyle(.black)
                            }
                            .disabled(authViewModel.isLoading || !canSubmit)
                            .opacity((authViewModel.isLoading || !canSubmit) ? 0.6 : 1.0)

                            // Terms and Privacy footer
                            VStack(spacing: 4) {
                                Text("By signing up you agree to the")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))

                                HStack(spacing: 4) {
                                    Button {
                                        showTermsOfService = true
                                    } label: {
                                        Text("Terms of Service")
                                            .font(.caption)
                                            .foregroundStyle(Color.appAccent)
                                    }

                                    Text("and")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.5))

                                    Button {
                                        showPrivacyPolicy = true
                                    } label: {
                                        Text("Privacy Policy")
                                            .font(.caption)
                                            .foregroundStyle(Color.appAccent)
                                    }
                                }
                            }
                            .padding(.top, 16)
                        }
                        .padding(.horizontal, 40)

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
            .sheet(isPresented: $showTermsOfService) {
                SafariView(url: termsOfServiceURL)
            }
            .sheet(isPresented: $showPrivacyPolicy) {
                SafariView(url: privacyPolicyURL)
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
}

// MARK: - Safari View

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
