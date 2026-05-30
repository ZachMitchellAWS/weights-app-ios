//
//  ResourcePlayerView.swift
//  WeightApp
//
//  Fullscreen YouTube embed via WKWebView. The iframe is hosted inside a tiny
//  HTML page loaded with baseURL `https://www.youtube.com`, which gives the
//  YouTube player a valid origin context — loading the embed URL directly trips
//  YouTube's embed-origin restriction (error 153). A single close X overlays
//  the player.
//

import SwiftUI
@preconcurrency import WebKit

struct ResourcePlayerView: View {
    let resource: Resource
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            YouTubeEmbedView(youtubeID: resource.youtubeID)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                    .padding(.top, 8)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
        }
        .statusBarHidden(true)
    }
}

// MARK: - WKWebView wrapper

private struct YouTubeEmbedView: UIViewRepresentable {
    let youtubeID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.backgroundColor = .black
        webView.isOpaque = false

        let videoID = youtubeID
        let html = """
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
        </head>
        <body style="margin:0;background:#000;">
          <iframe
            width="100%"
            height="100%"
            src="https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0"
            title="YouTube video player"
            frameborder="0"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowfullscreen>
          </iframe>
        </body>
        </html>
        """

        webView.loadHTMLString(
            html,
            baseURL: URL(string: "https://www.youtube-nocookie.com")
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // No-op: HTML is set once at load.
    }
}
