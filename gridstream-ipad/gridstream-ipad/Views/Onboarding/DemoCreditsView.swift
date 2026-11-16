//
//  DemoCreditsView.swift
//  gridstream-ipad
//
//  The demo pack's CREDITS.md: the films the clips come from, their
//  authors and licenses (CC BY requires the attribution).
//

import SwiftUI

struct DemoCreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(Self.lines().enumerated()), id: \.offset) { _, line in
                        lineView(line)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Demo Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.hasPrefix("# ") {
            Text(String(line.dropFirst(2)))
                .font(.title2.weight(.semibold))
        } else if line.hasPrefix("## ") {
            Text(String(line.dropFirst(3)))
                .font(.headline)
                .padding(.top, 8)
        } else {
            // Inline Markdown, so the license URLs are links.
            Text((try? AttributedString(markdown: line)) ?? AttributedString(line))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private static func lines() -> [String] {
        guard let text = try? String(contentsOf: DemoPack.creditsURL, encoding: .utf8) else {
            return [String(localized: "The demo clips are excerpts of open movies by the Blender Foundation, licensed under Creative Commons Attribution.")]
        }
        return text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
