//
//  PRTimelineWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI

struct PRTimelineWidget: View {
    let allSets: [LiftSet]

    private var prEvents: [TrendsCalculator.PREvent] {
        Array(TrendsCalculator.prTimeline(from: allSets).prefix(10))
    }

    private var daysSinceLastPR: Int? {
        guard let lastPR = prEvents.first else { return nil }
        return Calendar.current.dateComponents([.day], from: lastPR.date, to: Date()).day
    }

    var body: some View {
        WidgetCard(title: "Personal Records") {
            if prEvents.isEmpty {
                EmptyWidgetState(icon: "trophy.fill", message: "Set a PR to see your record history")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let days = daysSinceLastPR {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(days <= 7 ? Color.setPR : Color.white.opacity(0.4))

                            Text(days == 0 ? "PR today!" : "\(days) days since last PR")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(days <= 7 ? Color.setPR : .white.opacity(0.6))
                        }
                    }

                    ForEach(prEvents) { event in
                        PREventRow(event: event)
                    }
                }
            }
        }
    }
}

private struct PREventRow: View {
    let event: TrendsCalculator.PREvent

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: event.date)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Timeline dot
            Circle()
                .fill(Color.setPR)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))

                    Text("•")
                        .foregroundStyle(.white.opacity(0.3))

                    Text(event.exerciseName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                }

                HStack(spacing: 4) {
                    Text("\(Int(event.oldValue)) → \(Int(event.newValue)) lbs")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))

                    Text("(+\(String(format: "%.1f", event.percentageGain))%)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.setEasy)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
