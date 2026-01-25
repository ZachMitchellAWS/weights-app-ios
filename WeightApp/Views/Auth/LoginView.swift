//
//  LoginView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import SwiftUI

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
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 60)

                        // Login Form
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
                                    .textContentType(.password)
                                    .font(.body)

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
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appAccent)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)

                            // Error Message
                            if let error = authViewModel.errorMessage {
                                Text(error)
                                    .font(.caption)
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
                                            .font(.headline)
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
                        .font(.subheadline)

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
}
