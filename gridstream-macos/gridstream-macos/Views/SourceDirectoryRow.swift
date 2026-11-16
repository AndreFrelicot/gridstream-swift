//
//  SourceDirectoryRow.swift
//  gridstream-macos
//
//  A row displaying a source directory with enable/disable toggle.
//

import AppKit
import SwiftUI

struct SourceDirectoryRow: View {
    let directory: SourceDirectory
    var isUnavailable: Bool = false
    var onToggle: () -> Void
    var onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isUnavailable ? "externaldrive.badge.exclamationmark" : "folder.fill")
                .font(.title2)
                .foregroundStyle(iconStyle)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text((directory.path as NSString).lastPathComponent)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(directory.isEnabled ? .primary : .secondary)

                Text((directory.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(directory.path)

                if isUnavailable {
                    Label("Unavailable — its videos are kept until the folder is reachable again", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let lastScanned = directory.lastScanned {
                    Text("Last scanned \(formattedDate(lastScanned))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Not yet scanned")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .help("Remove folder")

            Toggle("", isOn: Binding(
                get: { directory.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .help(directory.isEnabled ? "Turn off to hide its videos from clients. Their tags, ratings and other data are kept." : "Turn on")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Show in Finder") {
                showInFinder()
            }
            .disabled(isUnavailable)

            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(directory.path, forType: .string)
            }

            Divider()

            Button(directory.isEnabled ? "Turn Off" : "Turn On") {
                onToggle()
            }

            Button("Remove…") {
                onRemove()
            }
        }
    }

    private var iconStyle: AnyShapeStyle {
        if isUnavailable { return AnyShapeStyle(Color.orange) }
        return directory.isEnabled ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary)
    }

    /// Opens a Finder window with the folder selected.
    private func showInFinder() {
        let url = URL(fileURLWithPath: directory.path, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
