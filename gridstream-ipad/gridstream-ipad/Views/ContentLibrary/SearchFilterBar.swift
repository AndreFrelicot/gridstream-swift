//
//  SearchFilterBar.swift
//  gridstream-ipad
//

import SwiftUI
import Combine

/// A search bar component for the Content Library with debounced search input.
/// Provides a text field with search icon, clear button, and debounced updates
/// to avoid excessive API calls.
struct SearchFilterBar: View {
    @Binding var searchText: String
    var placeholder: LocalizedStringKey = "Search videos..."
    var onSearchCommit: (() -> Void)?

    @State private var localText: String = ""
    @State private var debounceTask: Task<Void, Never>?

    private let debounceDelay: Duration = .milliseconds(300)

    init(
        searchText: Binding<String>,
        placeholder: LocalizedStringKey = "Search videos...",
        onSearchCommit: (() -> Void)? = nil
    ) {
        self._searchText = searchText
        self.placeholder = placeholder
        self.onSearchCommit = onSearchCommit
        self._localText = State(initialValue: searchText.wrappedValue)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 16, weight: .medium))

            TextField(placeholder, text: $localText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    commitSearch()
                }
                .onChange(of: localText) { _, newValue in
                    debounceSearch(newValue)
                }

            if !localText.isEmpty {
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            localText = searchText
        }
        .onChange(of: searchText) { _, newValue in
            // Update local text if external binding changes
            if localText != newValue {
                localText = newValue
            }
        }
    }

    // MARK: - Private Methods

    private func debounceSearch(_ text: String) {
        debounceTask?.cancel()

        debounceTask = Task {
            try? await Task.sleep(for: debounceDelay)

            if !Task.isCancelled {
                await MainActor.run {
                    searchText = text
                }
            }
        }
    }

    private func clearSearch() {
        localText = ""
        searchText = ""
        debounceTask?.cancel()
    }

    private func commitSearch() {
        debounceTask?.cancel()
        searchText = localText
        onSearchCommit?()
    }
}

// MARK: - Search Filter Bar with Filters Button

// MARK: - Previews

#Preview("Empty Search") {
    struct PreviewWrapper: View {
        @State private var searchText = ""

        var body: some View {
            VStack(spacing: 20) {
                SearchFilterBar(searchText: $searchText)

                Text("Search text: '\(searchText)'")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    return PreviewWrapper()
}

#Preview("With Text") {
    struct PreviewWrapper: View {
        @State private var searchText = "vacation"

        var body: some View {
            VStack(spacing: 20) {
                SearchFilterBar(searchText: $searchText)

                Text("Search text: '\(searchText)'")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    return PreviewWrapper()
}
