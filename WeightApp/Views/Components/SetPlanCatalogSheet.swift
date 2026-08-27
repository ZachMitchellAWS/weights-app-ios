//
//  SetPlanCatalogSheet.swift
//  WeightApp
//
//  The set-plan catalog as a standalone full-screen sheet.
//
//  It used to be the third tab of `HubView`, alongside Groups and Exercises. That was the
//  wrong home: the Hub sits above the exercise scroll row and is about WHICH LIFT you are
//  on, and a set plan is downstream of that choice — three things side by side that were
//  not peers.
//
//  `SetPlanCatalogView` was already self-contained (no parameters, paints its own
//  background), so all the Hub was really lending it was a Done button. That is what this
//  supplies, plus the presentation modifiers that used to live at the Hub's call site.
//

import SwiftUI

struct SetPlanCatalogSheet: View {
    /// Non-nil when opened for a lift in a live session — the selection then lands on that
    /// session item rather than on the user's global default. See `SetPlanCatalogView.apply`.
    var sessionExerciseId: UUID? = nil

    /// Shown above the catalog when scoped to one lift, so it is obvious the choice applies
    /// to that exercise and not to everything.
    var scopeName: String? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if let scopeName {
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Setting the plan for \(scopeName)")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(Color.appAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.appAccent.opacity(0.10))
            }

            SetPlanCatalogView(sessionExerciseId: sessionExerciseId)

            // Dismiss only. Tapping a plan already applies it — that is how this has always
            // behaved from the Lift tab, and changing it here would make the same catalog
            // commit differently depending on where it was opened from.
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(
            LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }
}
