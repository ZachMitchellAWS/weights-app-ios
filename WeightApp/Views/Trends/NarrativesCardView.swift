//
//  NarrativesCardView.swift
//  WeightApp
//
//  Static display card for the Weekly Progress Narratives visualization.
//  Exported as an image for the Go Premium upsell.
//

import SwiftUI

struct NarrativesCardView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Narrative sections
            VStack(spacing: 11) {
                narrativeSection(
                    icon: "chart.bar.fill",
                    title: "Training Volume",
                    color: Color(red: 0x21/255, green: 0xB7/255, blue: 0xC9/255),
                    body: "You logged 42 sets across 4 training days this week — up from 36 last week. Deadlifts and squats saw the biggest jump, with 8 and 7 sets respectively. Total volume hit 28.4k lbs, your highest in the last month. Your weekly average is now trending 12% above your 12-week baseline. This is your strongest volume week in the past six."
                )

                narrativeSection(
                    icon: "trophy.fill",
                    title: "Strength Highlights",
                    color: Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255),
                    body: "Two new estimated 1RM records this week — deadlifts moved from 385 to 405 lbs, and bench press crept up to 270. Your deadlift is now firmly in the Advanced tier at a 2.25× bodyweight ratio. Squats are holding steady at 335, just 15 lbs from the next milestone. That's 4 PRs in the last three weeks."
                )

                narrativeSection(
                    icon: "exclamationmark.triangle.fill",
                    title: "Areas to Watch",
                    color: Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255),
                    body: "Overhead press has been flat for three weeks at 175 lbs. Consider varying your rep ranges or adding paused reps to break through the plateau. Your push-to-pull ratio is also slightly uneven — adding a rowing variation could help balance things out."
                )

                narrativeSection(
                    icon: "target",
                    title: "Accessory Goals",
                    color: Color(red: 0x5B/255, green: 0x3B/255, blue: 0xE8/255),
                    body: "Barbell rows are trending well at 245 lbs — you're 15 lbs away from the Advanced tier threshold. Keep the momentum going with your current programming. Consider adding a heavier single set each session to push your estimated max higher."
                )

                narrativeSection(
                    icon: "arrow.right.circle.fill",
                    title: "Next Week",
                    color: Color.appAccent,
                    body: "Focus on overhead press with some intensity variation. Maintain your deadlift and squat volume — the progress there is working. Consider a lighter squat day mid-week for recovery. Your body is responding well to the current frequency. A deload week may be warranted in two weeks."
                )
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)

            // AI disclaimer
            Text("This analysis is AI-generated and may contain inaccuracies.")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.25))
                .padding(.bottom, 10)
        }
        .frame(width: 360, height: 780)
        .background(Color.black)
    }

    // MARK: - Narrative Section Card

    private func narrativeSection(icon: String, title: String, color: Color, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .background(color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                // Audio play button
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(color)
            }

            // Body text
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .lineSpacing(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(color)
                .frame(width: 3)
        }
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
