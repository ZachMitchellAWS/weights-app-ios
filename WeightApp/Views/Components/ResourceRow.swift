//
//  ResourceRow.swift
//  WeightApp
//
//  Single card row in the Resources list. YouTube-hosted thumbnail on the
//  left (9:16 crop), title + subtitle on the right, trailing chevron.
//

import SwiftUI

struct ResourceRow: View {
    let resource: Resource

    var body: some View {
        HStack(spacing: 14) {
            poster
            VStack(alignment: .leading, spacing: 4) {
                Text(resource.title)
                    .font(.interSemiBold(size: 17))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let subtitle = resource.subtitle {
                    Text(subtitle)
                        .font(.inter(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
                Text(resource.durationLabel)
                    .font(.interSemiBold(size: 12))
                    .foregroundStyle(Color.appAccent.opacity(0.85))
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var poster: some View {
        let width: CGFloat = 60
        let height: CGFloat = width * (16.0 / 9.0)

        AsyncImage(url: resource.posterURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty, .failure:
                ZStack {
                    Color.white.opacity(0.04)
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.appAccent.opacity(0.6))
                }
            @unknown default:
                Color.white.opacity(0.04)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}
