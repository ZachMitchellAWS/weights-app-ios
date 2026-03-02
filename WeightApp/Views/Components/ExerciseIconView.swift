//
//  ExerciseIconView.swift
//  WeightApp
//
//  Created by Claude on 2/6/26.
//

import SwiftUI

struct ExerciseIconView: View {
    let exercise: Exercise
    var size: CGFloat = 72

    var body: some View {
        exerciseIconContent
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var exerciseIconContent: some View {
        let icon = exercise.icon

        if icon.starts(with: "figure.") {
            // SF Symbol
            Image(systemName: icon)
                .font(.system(size: size * 0.8))
        } else if icon == "OverheadPressIcon" {
            // Custom asset with scale adjustment
            Image(icon)
                .resizable()
                .scaledToFit()
                .scaleEffect(1.2)
        } else {
            // Other custom assets (BenchPressIcon, PullUpIcon, etc.)
            Image(icon)
                .resizable()
                .scaledToFit()
        }
    }
}
