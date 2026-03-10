//
//  InsightsView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/8/26.
//

import SwiftUI

struct InsightsView: View {
    private let sections: [(title: String, body: String)] = [
        ("Training Volume",
         "You performed 3 sessions this week and hit your full Push / Pull / Legs split once through, using the Standard set plan. Total volume was 54 logged sets, which is a solid week: 18 Push, 24 Pull, 12 Legs. Nice balanced coverage, and it gives you a clean baseline to build from."),
        ("Strength Highlights",
         "There were a lot of good jumps. Your top e1RMs this week were Deadlift 222 lb, Squat 222 lb, Bench 215.8 lb, Barbell Row 203.5 lb, Romanian Deadlift 180 lb, and Overhead Press 128.3 lb. Biggest movers were Bench (+89.2 lb from first logged set to best set), Deadlift (+89 lb), Squat (+89 lb), Barbell Row (+83.2 lb), and RDL (+75 lb). Since this is your first real logged week, those are also your current all-time PR marks in the app."),
        ("Areas to Watch",
         "No major regressions showed up, which is what you want in week one. The one lift that looked the flattest was Overhead Press — it topped out at 128.3 lb e1RM, and most earlier sets clustered lower without much middle-ground buildup. That is not a red flag, just the clearest candidate for a tweak. Everything else trended up well across the session."),
        ("Accessory Goals",
         "Bodyweight averaged about 242.7 lb, which is 22.7 lb above your 220 lb target, and the trend moved up from 240 to 248 lb. Protein totaled 800 g for the week, about 114 g/day on average, which is well under your 240 g/day goal. Steps totaled 22,550 for the week, about 3,221/day, also under your 5,000/day target."),
        ("Next Week",
         "Keep the split the same, but try switching Overhead Press from Standard to Pyramid for one week so you get to the top set sooner while still keeping back-off work. Everything else is moving — bring protein up first, and your lifting progress should keep stacking fast.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.title)
                        .foregroundStyle(Color.appAccent)
                        .shadow(color: Color.appAccent.opacity(0.5), radius: 8)

                    Text("Weekly Insights")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Mar 2 – Mar 8, 2026")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Narrative cards
                ForEach(sections, id: \.title) { section in
                    WidgetCard(title: section.title) {
                        Text(section.body)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineSpacing(4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }
}
