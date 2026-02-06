//
//  ExerciseIconView.swift
//  WeightApp
//
//  Created by Claude on 2/6/26.
//

import SwiftUI

struct ExerciseIconView: View {
    let exercise: Exercises
    var size: CGFloat = 72

    var body: some View {
        exerciseIconContent
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var exerciseIconContent: some View {
        let name = exercise.name.lowercased()
        if name.contains("press") && name.contains("overhead") {
            Image("OverheadPressIcon")
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: sfSymbolName)
                .font(.system(size: size * 0.8))
        }
    }

    private var sfSymbolName: String {
        switch exercise.name.lowercased() {
        case let name where name.contains("bench"):
            return "figure.strengthtraining.traditional"
        case let name where name.contains("squat"):
            return "figure.squat"
        case let name where name.contains("deadlift"):
            return "figure.cooldown"
        case let name where name.contains("row"):
            return "figure.rowing"
        case let name where name.contains("pull"):
            return "figure.climbing"
        case let name where name.contains("dip"):
            return "figure.core.training"
        default:
            return "dumbbell.fill"
        }
    }
}
