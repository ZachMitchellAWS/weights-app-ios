//
//  WidgetCard.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI

struct WidgetCard<Content: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Spacer()

                trailing()
            }

            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.4), lineWidth: 1.5))
    }
}

extension WidgetCard where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.trailing = { EmptyView() }
    }
}

struct EmptyWidgetState: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.appAccent.opacity(0.5))

            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
