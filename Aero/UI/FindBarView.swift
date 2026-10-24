//
//  FindBarView.swift
//  Aero
//
//  Created by Mohak Bhatt on 23/10/26.
//


import SwiftUI

/// Find on Page bar (⌘F), floating at the top-right of the page.
struct FindBarView: View {
    @ObservedObject var state: BrowserState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)

            TextField("Find on Page", text: $state.findText)
                .textFieldStyle(.plain)
                .focused($focused)
                .frame(width: 170)
                .onSubmit { state.find(backwards: false) }
                .onExitCommand { state.hideFind() }

            if state.findNotFound && !state.findText.isEmpty {
                Text("Not found").font(.caption).foregroundStyle(.secondary)
            }

            ChromeIconButton(symbol: "chevron.up", help: "Previous (⇧⌘G)") { state.find(backwards: true) }
            ChromeIconButton(symbol: "chevron.down", help: "Next (⌘G)") { state.find(backwards: false) }
            Button("Done") { state.hideFind() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .glass(in: Capsule())
        .onAppear { focused = true }
        .onReceive(state.$findFocusToken) { _ in focused = true }
        .onValueChange(of: state.findText) { _ in state.find(backwards: false) }
    }
}
