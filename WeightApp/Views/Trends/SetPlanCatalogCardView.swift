//
//  SetPlanCatalogCardView.swift
//  WeightApp
//
//  Static display card for the Set Plan Catalog visualization.
//  Exported as an image for the Go Premium upsell.
//

import SwiftUI

struct SetPlanCatalogCardView: View {
    // Compact descriptions for export (some shortened to fit single row)
    private let presets: [(name: String, description: String, sequence: [String])] = [
        ("Top Set + Backoff",  "Work up to max, drop intensity",    ["easy", "moderate", "hard", "pr", "moderate", "moderate"]),
        ("Reverse Pyramid",    "Heaviest set first, then reduce",   ["hard", "pr", "hard", "moderate", "moderate", "easy"]),
        ("Wave Loading",       "Ascending waves of intensity",      ["moderate", "hard", "pr", "moderate", "hard", "pr"]),
        ("Cluster Sets",       "Heavy singles with short rest",     ["hard", "hard", "hard", "hard", "hard"]),
        ("Rest-Pause",         "Near failure, brief rest, repeat",  ["hard", "pr", "hard", "hard"]),
        ("Drop Sets",          "Reduce weight, rep to failure",     ["pr", "hard", "moderate", "easy"]),
        ("Ladders",            "Ascending rep ladder pattern",      ["easy", "easy", "moderate", "moderate", "hard", "moderate", "hard", "pr"]),
        ("Pause Reps",         "Build positional strength",         ["moderate", "moderate", "hard", "hard"]),
        ("Speed / Dynamic",    "Submaximal weight, max velocity",   ["easy", "easy", "easy", "easy", "easy", "easy", "easy", "easy"]),
        ("EMOM",               "Every minute on the minute",        ["moderate", "moderate", "moderate", "moderate", "moderate", "moderate"]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                ForEach(presets.indices, id: \.self) { i in
                    presetCard(name: presets[i].name, description: presets[i].description, sequence: presets[i].sequence)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .frame(width: 360, height: 780)
        .background(Color.black)
    }

    // MARK: - Preset Card

    private func presetCard(name: String, description: String, sequence: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // Title + description on same row
            HStack {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            // Effort squares
            HStack(spacing: 4) {
                ForEach(Array(sequence.enumerated()), id: \.offset) { _, effort in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(effortColor(effort).opacity(0.3))
                        .frame(width: 30, height: 30)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(effortColor(effort), lineWidth: 1.5)
                        )
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func effortColor(_ effort: String) -> Color {
        switch effort {
        case "easy": return .setEasy
        case "moderate": return .setModerate
        case "hard": return .setHard
        case "redline": return .setNearMax
        case "pr": return .setPR
        default: return .setEasy
        }
    }
}
