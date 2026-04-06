//
//  AppleSignInService.swift
//  WeightApp
//
//  Created by Claude on 2/5/26.
//

import Foundation
import AuthenticationServices

class AppleSignInService: NSObject {
    static let shared = AppleSignInService()

    struct AppleSignInResult {
        let identityToken: String
        let authorizationCode: String
        let userId: String
        let email: String?
        let fullName: PersonNameComponents?
    }

    enum AppleSignInError: Error, LocalizedError {
        case invalidCredential
        case missingIdentityToken
        case missingAuthorizationCode
        case cancelled
        case unknown(Error)

        var errorDescription: String? {
            switch self {
            case .invalidCredential:
                return "Invalid Apple credential received"
            case .missingIdentityToken:
                return "Missing identity token from Apple"
            case .missingAuthorizationCode:
                return "Missing authorization code from Apple"
            case .cancelled:
                return "Sign in was cancelled"
            case .unknown(let error):
                return error.localizedDescription
            }
        }
    }

    private var continuation: CheckedContinuation<AppleSignInResult, Error>?

    private override init() {
        super.init()
    }

    func signIn() async throws -> AppleSignInResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.performRequests()
        }
    }

    func checkCredentialState(userId: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userId) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }

    func handleAuthorization(_ authorization: ASAuthorization) throws -> AppleSignInResult {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AppleSignInError.invalidCredential
        }

        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AppleSignInError.missingIdentityToken
        }

        guard let authorizationCodeData = credential.authorizationCode,
              let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
            throw AppleSignInError.missingAuthorizationCode
        }

        return AppleSignInResult(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            userId: credential.user,
            email: credential.email,
            fullName: credential.fullName
        )
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        do {
            let result = try handleAuthorization(authorization)
            continuation?.resume(returning: result)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let authError = error as? ASAuthorizationError
        if authError?.code == .canceled {
            continuation?.resume(throwing: AppleSignInError.cancelled)
        } else {
            continuation?.resume(throwing: AppleSignInError.unknown(error))
        }
        continuation = nil
    }
}
