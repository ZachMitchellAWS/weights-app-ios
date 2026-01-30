//
//  APIConfig.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import Foundation

enum APIEnvironment {
    case staging
    case production

    var baseURL: String {
        switch self {
        case .staging:
            return "https://h49ho1pn62.execute-api.us-west-1.amazonaws.com/staging"
        case .production:
            return "" // TODO: Add production URL when available
        }
    }

    var apiKey: String {
        switch self {
        case .staging:
            return "VedgMnwCCw6gSxybUQxLi1aTpHVEUz5t2u1NC9K3"
        case .production:
            return "" // TODO: Add production API key when available
        }
    }
}

struct APIConfig {
    static var current: APIEnvironment = .staging

    static var baseURL: String {
        current.baseURL
    }

    static var apiKey: String {
        current.apiKey
    }

    static var commonHeaders: [String: String] {
        [
            "x-api-key": apiKey,
            "Content-Type": "application/json"
        ]
    }

    static func authorizedHeaders(token: String) -> [String: String] {
        var headers = commonHeaders
        headers["Authorization"] = "Bearer \(token)"
        return headers
    }
}
