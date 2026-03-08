//
//  AccessoryHistoryView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/6/26.
//

import SwiftUI

struct AccessoryHistoryView: View {
    let metricType: String
    let checkins: [AccessoryGoalCheckin]
    let onDelete: (AccessoryGoalCheckin) -> Void

    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch metricType {
        case "steps": return "Steps History"
        case "protein": return "Protein History"
        case "bodyweight": return "Weight History"
        default: return "History"
        }
    }

    private var unitLabel: String {
        switch metricType {
        case "steps": return "steps"
        case "protein": return "g"
        case "bodyweight": return "lbs"
        default: return ""
        }
    }

    private var activeCheckins: [AccessoryGoalCheckin] {
        checkins
            .filter { !$0.deleted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var groupedByDay: [(date: Date, checkins: [AccessoryGoalCheckin])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: activeCheckins) { checkin in
            calendar.startOfDay(for: checkin.createdAt)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, checkins: $0.value) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeCheckins.isEmpty {
                    ContentUnavailableView("No Entries", systemImage: "tray", description: Text("No entries yet"))
                } else {
                    List {
                        ForEach(groupedByDay, id: \.date) { group in
                            Section(header: Text(sectionHeader(for: group.date))) {
                                ForEach(group.checkins, id: \.id) { checkin in
                                    HStack {
                                        Text(formattedValue(checkin.value))
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text(checkin.createdAt.formatted(date: .omitted, time: .shortened))
                                            .font(.subheadline)
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            onDelete(checkin)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sectionHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private func formattedValue(_ value: Double) -> String {
        switch metricType {
        case "bodyweight":
            return String(format: "%.1f \(unitLabel)", value)
        case "steps":
            return "\(Int(value).formatted()) \(unitLabel)"
        case "protein":
            return "\(Int(value))\(unitLabel)"
        default:
            return "\(Int(value)) \(unitLabel)"
        }
    }
}
