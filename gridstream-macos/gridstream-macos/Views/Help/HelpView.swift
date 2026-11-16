//
//  HelpView.swift
//  gridstream-macos
//
//  The Help window: topics in a sidebar, the selected topic's items on the
//  right, and a search across all of them. Opened from the Help menu, the
//  menu bar menu and the help button of each settings pane.
//

import SwiftUI

/// Which topic the Help window shows, so other windows can open it on a
/// given topic.
@Observable
final class HelpRouter {
    static let shared = HelpRouter()

    var selectedTopicID: HelpTopic.ID? = HelpTopic.all.first?.id
    var query = ""

    func show(topicID: HelpTopic.ID) {
        query = ""
        selectedTopicID = topicID
    }
}

struct HelpView: View {
    @Bindable private var router = HelpRouter.shared

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.all, selection: $router.selectedTopicID) { topic in
                Label {
                    Text(topic.title)
                } icon: {
                    BrandSymbol(systemImage: topic.systemImage, size: 22)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            if router.query.isEmpty {
                if let topic = router.selectedTopicID.flatMap(HelpTopic.topic(id:)) {
                    HelpTopicView(topic: topic)
                } else {
                    ContentUnavailableView("Select a Topic", systemImage: "questionmark.circle")
                }
            } else {
                HelpSearchResults(query: router.query)
            }
        }
        .searchable(text: $router.query, placement: .toolbar, prompt: "Search Help")
        .navigationTitle("GridStream Help")
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 680, minHeight: 460)
    }
}

private struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    BrandSymbol(systemImage: topic.systemImage, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topic.title)
                            .font(.largeTitle.weight(.semibold))
                        Text(topic.summary)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(topic.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().padding(.leading, 52)
                        }
                        HelpItemRow(item: item)
                    }
                }
                .padding(.horizontal, 14)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HelpSearchResults: View {
    let query: String

    var body: some View {
        let results = HelpTopic.all.compactMap { topic -> (HelpTopic, [HelpItem])? in
            let items = topic.items.filter { $0.matches(query) }
            return items.isEmpty ? nil : (topic, items)
        }

        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(results, id: \.0.id) { topic, items in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                HelpRouter.shared.show(topicID: topic.id)
                            } label: {
                                Label {
                                    Text(topic.title)
                                } icon: {
                                    Image(systemName: topic.systemImage)
                                }
                                .font(.headline)
                            }
                            .buttonStyle(.link)

                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 {
                                        Divider().padding(.leading, 52)
                                    }
                                    HelpItemRow(item: item)
                                }
                            }
                            .padding(.horizontal, 14)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct HelpItemRow: View {
    let item: HelpItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BrandSymbol(systemImage: item.systemImage, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                Text(item.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HelpView()
        .frame(width: 820, height: 560)
}
