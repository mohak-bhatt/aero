//
//  DownloadsPopover.swift
//  Aero
//
//  Created by Mohak Bhatt on 23/10/26.
//


import SwiftUI

struct DownloadsPopover: View {
    @ObservedObject var manager: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                Button("Clear") { manager.clearFinished() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(manager.items.allSatisfy { $0.state == .running })
            }

            if manager.items.isEmpty {
                Text("No downloads yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(manager.items) { DownloadRow(item: $0, manager: manager) }
                    }
                }
                .frame(maxHeight: 260)
            }

            Divider()
            Button("Show in Finder") { manager.showInFinder() }
                .buttonStyle(.link)
        }
        .padding(14)
        .frame(width: 300)
    }
}

private struct DownloadRow: View {
    @ObservedObject var item: DownloadItem
    let manager: DownloadManager

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.destination.path))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename).lineLimit(1).truncationMode(.middle)
                switch item.state {
                case .running:
                    ProgressView(value: item.progress).controlSize(.small)
                case .finished:
                    Text("Done").font(.caption).foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(1)
                }
            }

            Button {
                if item.state == .running { item.cancel() } else { manager.showInFinder(item) }
            } label: {
                Image(systemName: item.state == .running ? "xmark.circle" : "magnifyingglass.circle")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(item.state == .running ? "Cancel" : "Show in Finder")
        }
    }
}
