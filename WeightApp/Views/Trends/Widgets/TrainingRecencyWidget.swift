//
//  TrainingRecencyWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/10/26.
//

import SwiftUI

struct TrainingRecencyWidget: View {
    let allSets: [LiftSets]
    var isPremium: Bool = true
    @Binding var showUpsell: Bool

    private var recencyData: [TrendsCalculator.ExerciseRecency] {
        TrendsCalculator.exerciseRecency(from: allSets)
    }

    var body: some View {
        if isPremium {
            WidgetCard(title: "Exercise Activity", subtitle: "Days since last session") {
                unlockedContent
            }
        } else {
            lockedContent
        }
    }

    // MARK: - Unlocked (Premium) Content

    @ViewBuilder
    private var unlockedContent: some View {
        if recencyData.isEmpty {
            EmptyWidgetState(icon: "clock", message: "Log sets to see exercise recency")
        } else {
            VStack(spacing: 6) {
                ForEach(recencyData) { item in
                    exerciseRow(name: item.exerciseName, days: item.daysSinceLastSet)
                }
                legend
            }
        }
    }

    // MARK: - Locked (Free) Content

    private var lockedContent: some View {
        ZStack {
            // Blurred fake content
            VStack(spacing: 6) {
                exerciseRow(name: "Bench Press", days: 1)
                exerciseRow(name: "Squat", days: 4)
                exerciseRow(name: "Deadlift", days: 8)
                exerciseRow(name: "Overhead Press", days: 14)
                exerciseRow(name: "Barbell Row", days: 22)
                exerciseRow(name: "Barbell Curl", days: 30)
                legend
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .blur(radius: 2)
            .allowsHitTesting(false)

            // Overlay
            Color.black.opacity(0.3)

            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.appAccent)

                Text("Unlock Exercise Activity")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Track how recently you trained each exercise")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                Text("Go Premium")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.appAccent, in: Capsule())
            }
            .padding(.horizontal, 16)
        }
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { showUpsell = true }
    }

    // MARK: - Shared Components

    private func exerciseRow(name: String, days: Int?) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(recencyColor(for: days))
                .frame(width: 24, height: 24)

            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            Text(daysLabel(for: days))
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less Recent")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.4))

            ForEach([31, 15, 9, 6, 3, 0] as [Int], id: \.self) { days in
                RoundedRectangle(cornerRadius: 2)
                    .fill(recencyColor(for: days <= 30 ? days : nil))
                    .frame(width: 10, height: 10)
            }

            Text("Recent")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.top, 10)
    }

    // MARK: - Helpers

    private func daysLabel(for days: Int?) -> String {
        guard let days = days else { return ">30d" }
        if days == 0 { return "Today" }
        if days < 7 { return "\(days)d ago" }
        if days < 14 { return "1w ago" }
        if days < 21 { return "2w ago" }
        if days < 28 { return "3w ago" }
        return "4w ago"
    }

    private func recencyColor(for days: Int?) -> Color {
        guard let days = days else {
            return Color(white: 0.2)
        }
        switch days {
        case 0...2:
            return Color.appAccent
        case 3...5:
            return Color.appAccent.opacity(0.65)
        case 6...8:
            return Color.appAccent.opacity(0.4)
        case 9...14:
            return Color.appAccent.opacity(0.22)
        default:
            return Color.appAccent.opacity(0.12)
        }
    }
}
