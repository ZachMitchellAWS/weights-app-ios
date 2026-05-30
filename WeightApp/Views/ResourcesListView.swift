//
//  ResourcesListView.swift
//  WeightApp
//
//  Scrollable list of tutorial videos under More → Resources.
//  Tapping a row opens a fullscreen vertical AVPlayer in `ResourcePlayerView`.
//

import SwiftUI

struct ResourcesListView: View {
    private let resources = ResourceCatalog.all
    @State private var selected: Resource?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if resources.isEmpty {
                    emptyState
                } else {
                    ForEach(resources) { resource in
                        Button {
                            selected = resource
                        } label: {
                            ResourceRow(resource: resource)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Resources")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selected) { resource in
            ResourcePlayerView(resource: resource)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 36))
                .foregroundStyle(Color.appAccent.opacity(0.5))
            Text("More tutorials coming soon.")
                .font(.inter(size: 15))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
