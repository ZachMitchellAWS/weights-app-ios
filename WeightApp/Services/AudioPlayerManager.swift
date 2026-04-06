//
//  AudioPlayerManager.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/17/26.
//

import AVFoundation
import Observation

@Observable
final class AudioPlayerManager {
    private(set) var currentlyPlayingSectionTitle: String?
    private(set) var isPlaying: Bool = false

    private var player: AVPlayer?
    private var playerObserver: Any?

    func toggle(url: URL, sectionTitle: String) {
        if currentlyPlayingSectionTitle == sectionTitle && isPlaying {
            pause()
        } else {
            play(url: url, sectionTitle: sectionTitle)
        }
    }

    func play(url: URL, sectionTitle: String) {
        // Stop any current playback
        stop()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        currentlyPlayingSectionTitle = sectionTitle
        isPlaying = true
        player?.play()

        // Observe when playback finishes
        playerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        currentlyPlayingSectionTitle = nil

        if let observer = playerObserver {
            NotificationCenter.default.removeObserver(observer)
            playerObserver = nil
        }
    }

    deinit {
        if let observer = playerObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
