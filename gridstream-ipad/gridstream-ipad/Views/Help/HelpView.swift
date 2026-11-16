//
//  HelpView.swift
//  gridstream-ipad
//
//  The Help screen, opened from the server menu: a list of topics, each
//  explaining the controls of one screen or feature, and a search across
//  all of them.
//

import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    ForEach(HelpTopic.all) { topic in
                        NavigationLink {
                            HelpTopicView(topic: topic)
                        } label: {
                            topicRow(topic)
                        }
                    }
                } else {
                    searchResults
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search help")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .pageSizedSheet()
    }

    private func topicRow(_ topic: HelpTopic) -> some View {
        HStack(spacing: 14) {
            HelpSymbol(systemImage: topic.systemImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(.headline)
                Text(topic.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = HelpTopic.all.compactMap { topic -> (HelpTopic, [HelpItem])? in
            let items = topic.items.filter { matches($0) }
            return items.isEmpty ? nil : (topic, items)
        }
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ForEach(results, id: \.0.id) { topic, items in
                Section {
                    ForEach(items) { HelpItemRow(item: $0) }
                } header: {
                    Text(topic.title)
                }
            }
        }
    }

    private func matches(_ item: HelpItem) -> Bool {
        String(localized: item.title).localizedStandardContains(query)
            || String(localized: item.detail).localizedStandardContains(query)
    }
}

private struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        List {
            Section {
                ForEach(topic.items) { HelpItemRow(item: $0) }
            } header: {
                Text(topic.summary)
                    .textCase(nil)
            }
        }
        .navigationTitle(Text(topic.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HelpItemRow: View {
    let item: HelpItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            HelpSymbol(systemImage: item.systemImage)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// An SF Symbol on a small tile in the icon's orange.
private struct HelpSymbol: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.96, green: 0.62, blue: 0.04), Color(red: 0.92, green: 0.35, blue: 0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

private extension View {
    /// A larger sheet than the default form sheet, where available.
    @ViewBuilder
    func pageSizedSheet() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }
}

#Preview {
    HelpView()
}
