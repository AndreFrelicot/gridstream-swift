//
//  HistoryTabView.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

struct HistoryTabView: View {
    let serverURL: URL?
    let onVideoSelected: (VideoItem) -> Void

    @State private var videos: [VideoItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var totalCount = 0
    @State private var currentOffset = 0
    private let pageSize = 50

    private let contentLibraryService = ContentLibraryService()

    private var hasMore: Bool {
        videos.count < totalCount
    }

    var body: some View {
        Group {
            if isLoading && videos.isEmpty {
                ProgressView("Loading history...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, videos.isEmpty {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if videos.isEmpty {
                ContentUnavailableView(
                    "No Play History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Videos you play will appear here.")
                )
            } else {
                List {
                    ForEach(videos) { video in
                        Button {
                            onVideoSelected(video)
                        } label: {
                            HistoryRowView(video: video, serverURL: serverURL)
                        }
                        .buttonStyle(.plain)
                    }

                    if hasMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .onAppear {
                                    Task {
                                        await loadMore()
                                    }
                                }
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task {
            await loadHistory()
        }
    }

    private func loadHistory() async {
        guard let serverURL = serverURL else {
            errorMessage = String(localized: "Server not connected")
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        var filters = ContentLibraryFilters()
        filters.playedOnly = true

        do {
            let result = try await contentLibraryService.fetchVideos(
                from: serverURL,
                filters: filters,
                sortOption: .lastPlayedDesc,
                limit: pageSize,
                offset: 0
            )
            videos = result.videos
            totalCount = result.total
            currentOffset = 0
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadMore() async {
        guard let serverURL = serverURL else { return }
        guard !isLoading else { return }
        guard hasMore else { return }

        isLoading = true
        let nextOffset = currentOffset + pageSize

        var filters = ContentLibraryFilters()
        filters.playedOnly = true

        do {
            let result = try await contentLibraryService.fetchVideos(
                from: serverURL,
                filters: filters,
                sortOption: .lastPlayedDesc,
                limit: pageSize,
                offset: nextOffset
            )
            videos.append(contentsOf: result.videos)
            currentOffset = nextOffset
            isLoading = false
        } catch {
            isLoading = false
        }
    }
}
