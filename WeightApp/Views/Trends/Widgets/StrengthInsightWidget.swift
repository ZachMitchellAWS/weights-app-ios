//
//  StrengthInsightWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/26/26.
//

import SwiftUI

struct StrengthInsightWidget: View {
    var audioPlayer: AudioPlayerManager
    @Binding var showUpsell: Bool
    var isPremium: Bool = false
    @Binding var trendsTab: TrendsTab
    var currentOverallTier: StrengthTier = .none

    @State private var isExpanded = false
    @State private var showAttentionPulse = false
    @State private var audioAnimationPhase = false
    @State private var waitingForAudio = false
    private var latestTierUnlock: TierUnlockItem? {
        let unlocks = NarrativeBadgeService.shared.tierUnlocks
        guard let latest = unlocks.last,
              let generatedAt = latest.generatedAt,
              Self.isWithinThreeDays(generatedAt),
              latest.strengthTier == currentOverallTier else { return nil }
        return latest
    }

    private var hasAudio: Bool {
        latestTierUnlock?.hasValidAudio == true
    }

    private var tier: StrengthTier {
        latestTierUnlock?.strengthTier ?? .none
    }

    private var audioTitle: String { "Strength Insight — \(tier.title)" }

    private var isPlaying: Bool {
        audioPlayer.currentlyPlayingSectionTitle == audioTitle && audioPlayer.isPlaying
    }

    private var daysRemaining: Int? {
        guard let item = latestTierUnlock,
              let generatedAt = item.generatedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: generatedAt)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: generatedAt)
        }
        guard let generated = date else { return nil }
        let expiresAt = generated.addingTimeInterval(3 * 24 * 60 * 60)
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
        return max(0, remaining)
    }

    var body: some View {
        if let item = latestTierUnlock {
            VStack(spacing: 16) {
                Text("STRENGTH INSIGHT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .tracking(1.5)

                if hasAudio {
                    // Play button — large, centered, amber
                    Button {
                        guard let urlString = item.audioUrl,
                              let url = URL(string: urlString) else { return }
                        audioPlayer.toggle(url: url, sectionTitle: audioTitle)
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.appAccent)
                            .scaleEffect(showAttentionPulse ? 1.15 : 1.0)
                            .animation(.easeInOut(duration: 0.6).repeatCount(3, autoreverses: true), value: showAttentionPulse)
                    }
                    .buttonStyle(.plain)

                    if let days = daysRemaining {
                        Text("Expires in \(days) day\(days == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else if waitingForAudio {
                    // User tapped — show loading state
                    ProgressView()
                        .tint(Color.appAccent)
                        .scaleEffect(1.5)
                        .frame(width: 72, height: 72)
                        .fixedSize()
                } else {
                    // Ambient visual — shown before audio arrives or when URL expired
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            waitingForAudio = true
                        }
                        // Refresh tier unlocks to get fresh presigned URLs
                        Task { await NarrativeBadgeService.shared.fetchAndCacheTierUnlocks() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.appAccent.opacity(audioAnimationPhase ? 0.15 : 0.0))

                            Circle()
                                .stroke(Color.appAccent, lineWidth: audioAnimationPhase ? 2 : 0.5)
                                .padding(12)
                                .opacity(audioAnimationPhase ? 0.6 : 0.15)

                            Image(systemName: "waveform")
                                .font(.system(size: 25, weight: .medium))
                                .foregroundStyle(Color.appAccent)
                                .opacity(audioAnimationPhase ? 1.0 : 0.35)
                        }
                        .frame(width: 72, height: 72)
                        .fixedSize()
                        .drawingGroup()
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                            audioAnimationPhase = true
                        }
                    }
                }

                // "Full Insight" label + chevron dropdown
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text("FULL INSIGHT")
                            .font(.caption.weight(.semibold))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.7))

                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.4))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)

                // Expanded transcript
                if isExpanded {
                    VStack(spacing: 0) {
                        Text(item.body)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            if isPremium {
                                trendsTab = .narratives
                            } else {
                                showUpsell = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isPremium ? "chart.bar.doc.horizontal" : "sparkles")
                                Text(isPremium ? "See Progress Narratives" : "Unlock Progress Narratives")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.appAccent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 16)
                    }
                    .transition(.opacity)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onAppear {
                if NarrativeBadgeService.shared.hasUnviewedTierUnlock {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showAttentionPulse = true
                    }
                }
            }
        }
    }

    // MARK: - Date Check

    static func isWithinThreeDays(_ isoString: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoString) else { return false }
            return Date().timeIntervalSince(date) < 3 * 24 * 60 * 60
        }
        return Date().timeIntervalSince(date) < 3 * 24 * 60 * 60
    }
}
