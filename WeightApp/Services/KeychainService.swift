//
//  KeychainService.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()

    private let accessTokenKey = "com.weightapp.accessToken"
    private let refreshTokenKey = "com.weightapp.refreshToken"
    private let userIdKey = "com.weightapp.userId"
    private let expiresAtKey = "com.weightapp.expiresAt"
    private let refreshTokenExpiresAtKey = "com.weightapp.refreshTokenExpiresAt"
    private let emailKey = "com.weightapp.email"
    private let createdDatetimeKey = "com.weightapp.createdDatetime"

    private init() {}

    // MARK: - Save Tokens

    func saveTokens(accessToken: String, refreshToken: String, userId: String, accessTokenExpiresIn: Int, refreshTokenExpiresIn: Int, email: String? = nil) {
        let expiresAt = Date().addingTimeInterval(TimeInterval(accessTokenExpiresIn))
        let refreshTokenExpiresAt = Date().addingTimeInterval(TimeInterval(refreshTokenExpiresIn))

        save(key: accessTokenKey, value: accessToken)
        save(key: refreshTokenKey, value: refreshToken)
        save(key: userIdKey, value: userId)
        save(key: expiresAtKey, value: ISO8601DateFormatter().string(from: expiresAt))
        save(key: refreshTokenExpiresAtKey, value: ISO8601DateFormatter().string(from: refreshTokenExpiresAt))

        if let email = email {
            save(key: emailKey, value: email)
        }
    }

    func updateAccessToken(accessToken: String, userId: String, accessTokenExpiresIn: Int) {
        let expiresAt = Date().addingTimeInterval(TimeInterval(accessTokenExpiresIn))

        save(key: accessTokenKey, value: accessToken)
        save(key: userIdKey, value: userId)
        save(key: expiresAtKey, value: ISO8601DateFormatter().string(from: expiresAt))
    }

    // MARK: - Get Tokens

    func getAccessToken() -> String? {
        return get(key: accessTokenKey)
    }

    func getRefreshToken() -> String? {
        return get(key: refreshTokenKey)
    }

    func getUserId() -> String? {
        return get(key: userIdKey)
    }

    func getEmail() -> String? {
        return get(key: emailKey)
    }

    func getCreatedDatetime() -> String? {
        return get(key: createdDatetimeKey)
    }

    func getTokenStorage() -> TokenStorage? {
        guard let accessToken = getAccessToken(),
              let refreshToken = getRefreshToken(),
              let userId = getUserId(),
              let expiresAtString = get(key: expiresAtKey),
              let expiresAt = ISO8601DateFormatter().date(from: expiresAtString) else {
            return nil
        }

        // Refresh token expiry is optional (backend may not provide it yet)
        var refreshTokenExpiresAt: Date? = nil
        if let refreshExpiresAtString = get(key: refreshTokenExpiresAtKey) {
            refreshTokenExpiresAt = ISO8601DateFormatter().date(from: refreshExpiresAtString)
        }

        return TokenStorage(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: userId,
            expiresAt: expiresAt,
            refreshTokenExpiresAt: refreshTokenExpiresAt
        )
    }

    func isAuthenticated() -> Bool {
        return getAccessToken() != nil && getRefreshToken() != nil
    }

    // MARK: - User Properties

    func saveUserProperties(createdDatetime: String) {
        save(key: createdDatetimeKey, value: createdDatetime)
    }

    // MARK: - Clear Tokens

    func clearTokens() {
        delete(key: accessTokenKey)
        delete(key: refreshTokenKey)
        delete(key: userIdKey)
        delete(key: expiresAtKey)
        delete(key: refreshTokenExpiresAtKey)
        delete(key: emailKey)
        delete(key: createdDatetimeKey)
    }

    // MARK: - Private Keychain Methods

    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        SecItemAdd(query as CFDictionary, nil)
    }

    private func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
