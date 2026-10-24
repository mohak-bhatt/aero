//
//  SuggestionsView.swift
//  Aero
//
//  Created by Mohak Bhatt on 24/10/26.
//


import SwiftUI

/// Address-bar suggestions: tabs, favourites, bookmarks, history and web search, in a glass list
/// the same width as the address pill.
struct SuggestionsView: View {
    @ObservedObject var state: BrowserState

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(state.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button { state.choose(suggestion) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.symbol).frame(width: 18).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.title).font(.system(size: 12.5)).lineLimit(1)
                            if let subtitle = suggestion.subtitle {
                                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: suggestion.subtitle == nil ? 28 : 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(state.suggestionIndex == index ? 0.14 : 0)))
                .onHover { if $0 { state.suggestionIndex = index } }
            }
        }
        .padding(6)
        .glass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }
}
