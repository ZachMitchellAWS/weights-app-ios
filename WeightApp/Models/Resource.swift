//
//  Resource.swift
//  WeightApp
//
//  A tutorial / educational YouTube video shown in More → Resources.
//  Videos are hosted on YouTube; we embed them via `youtube.com/embed/{id}`
//  inside a fullscreen WKWebView. To add a new entry: append a `Resource(...)`
//  below with the YouTube video ID (the `EPCrGPgbYSQ` part of a
//  `youtube.com/shorts/EPCrGPgbYSQ` or `youtu.be/EPCrGPgbYSQ` URL).
//

import Foundation

struct Resource: Identifiable, Hashable {
    let id: String              // reuses youtubeID as the row identity
    let youtubeID: String
    let title: String
    let subtitle: String?
    let durationSeconds: Int

    init(youtubeID: String, title: String, subtitle: String? = nil, durationSeconds: Int) {
        self.id = youtubeID
        self.youtubeID = youtubeID
        self.title = title
        self.subtitle = subtitle
        self.durationSeconds = durationSeconds
    }

    var durationLabel: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var posterURL: URL {
        URL(string: "https://img.youtube.com/vi/\(youtubeID)/maxresdefault.jpg")!
    }
}

enum ResourceCatalog {
    static let all: [Resource] = [
        Resource(
            youtubeID: "O9ashjGdP20",
            title: "How It Works",
            subtitle: "A complete walkthrough",
            durationSeconds: 338
        )
    ]
}
