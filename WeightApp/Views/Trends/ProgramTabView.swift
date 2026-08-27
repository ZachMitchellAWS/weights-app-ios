//
//  ProgramTabView.swift
//  WeightApp
//
//  Top-level Session tab.
//
//  Hosts `ProgramMockView` — Smart Sessions. This tab was promoted from the old Weekly Progress
//  Narratives screen, which Smart Sessions replaced; that screen and its view model have since
//  been deleted, so there is no longer anything to revert to.
//

import SwiftUI

struct ProgramTabView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        ProgramMockView(selectedTab: $selectedTab)
    }
}
