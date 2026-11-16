//
//  TagManagementContentView.swift
//  gridstream-ipad
//

import OSLog
import SwiftUI

/// Embedded view for tag management that works within a tabbed container.
/// Provides tag list with CRUD operations without its own NavigationStack.
/// Shows Smart List usage warnings when deleting tags.
/// Supports applying tags to the current video when videoId is provided.
///
/// Note: Create/update are handled directly by TagFormSheetView to avoid callback chain corruption.
struct TagManagementContentView: View {
    @Binding var tags: [TagInfo]
    let smartLists: [SmartListInfo]
    let serverURL: URL?

    let currentVideoId: String?
    let appliedTagIds: Set<UUID>
    let onDeleteTag: (UUID) async throws -> Void
    let onTagAppliedToVideo: ((TagInfo) -> Void)?
    let onTagsChanged: (() -> Void)?

    @State private var isShowingCreateForm = false
    @State private var tagToEdit: TagInfo?
    @State private var tagToDelete: TagInfo?
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var showDeleteError = false
    @State private var applyingTagId: UUID?
    @State private var localAppliedTagIds: Set<UUID> = []

    private let contentLibraryService = ContentLibraryService()
    private let maxTagCount = 30

    init(
        tags: Binding<[TagInfo]>,
        smartLists: [SmartListInfo],
        serverURL: URL?,
        currentVideoId: String? = nil,
        appliedTagIds: Set<UUID> = [],
        onDeleteTag: @escaping (UUID) async throws -> Void,
        onTagAppliedToVideo: ((TagInfo) -> Void)? = nil,
        onTagsChanged: (() -> Void)? = nil
    ) {
        self._tags = tags
        self.smartLists = smartLists
        self.serverURL = serverURL
        self.currentVideoId = currentVideoId
        self.appliedTagIds = appliedTagIds
        self.onDeleteTag = onDeleteTag
        self.onTagAppliedToVideo = onTagAppliedToVideo
        self.onTagsChanged = onTagsChanged
    }

    var body: some View {
        Group {
            if tags.isEmpty {
                emptyStateView
            } else {
                tagListView
            }
        }
        .onAppear {
            localAppliedTagIds = appliedTagIds
            AppLogger.video.info("TagManagementContentView.onAppear: appliedTagIds=\(appliedTagIds.map { $0.uuidString }), currentVideoId=\(String(describing: currentVideoId))")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingCreateForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(tags.count >= maxTagCount)
            }
        }
        .sheet(isPresented: $isShowingCreateForm) {
            TagFormSheetView(
                mode: .create,
                existingTagNames: Set(tags.map { $0.name.lowercased() }),
                serverURL: serverURL,
                onCreated: { newTag in
                    tags.append(newTag)
                    isShowingCreateForm = false
                    onTagsChanged?()
                },
                onUpdated: { _ in },
                onCancel: {
                    isShowingCreateForm = false
                }
            )
        }
        .sheet(item: $tagToEdit) { tag in
            TagFormSheetView(
                mode: .edit(tag),
                existingTagNames: Set(tags.filter { $0.id != tag.id }.map { $0.name.lowercased() }),
                serverURL: serverURL,
                onCreated: { _ in },
                onUpdated: { updatedTag in
                    if let index = tags.firstIndex(where: { $0.id == updatedTag.id }) {
                        tags[index] = updatedTag
                    }
                    tagToEdit = nil
                    onTagsChanged?()
                },
                onCancel: {
                    tagToEdit = nil
                }
            )
        }
        .alert("Delete Tag", isPresented: $showDeleteConfirmation, presenting: tagToDelete) { tag in
            Button("Cancel", role: .cancel) {
                tagToDelete = nil
            }
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await onDeleteTag(tag.id)
                        await MainActor.run {
                            tags.removeAll { $0.id == tag.id }
                            tagToDelete = nil
                            onTagsChanged?()
                        }
                    } catch {
                        await MainActor.run {
                            deleteError = error.localizedDescription
                            showDeleteError = true
                            tagToDelete = nil
                        }
                    }
                }
            }
        } message: { tag in
            Text(deleteConfirmationMessage(for: tag))
        }
        .alert("Error", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {
                deleteError = nil
            }
        } message: {
            Text(deleteError ?? String(localized: "An error occurred"))
        }
    }

    // MARK: - Delete Confirmation Message

    private func deleteConfirmationMessage(for tag: TagInfo) -> String {
        let affectedSmartLists = SmartListQueryBuilder.findSmartListsContainingTag(smartLists, tagId: tag.id)

        var message = String(localized: "Are you sure you want to delete the tag \"\(tag.name)\"? This will remove it from all videos.")

        if !affectedSmartLists.isEmpty {
            let smartListNames = affectedSmartLists.map { "\"\($0.name)\"" }.joined(separator: ", ")
            if affectedSmartLists.count == 1 {
                message += "\n\n" + String(localized: "This tag is also used in Smart List \(smartListNames). The tag condition will be removed from this Smart List.")
            } else {
                message += "\n\n" + String(localized: "This tag is also used in \(affectedSmartLists.count) Smart Lists: \(smartListNames). The tag conditions will be removed from these Smart Lists.")
            }
        }

        return message
    }

    // MARK: - Tag List

    private var tagListView: some View {
        List {
            Section {
                ForEach(tags) { tag in
                    TagRowView(
                        tag: tag,
                        smartListCount: smartListCountForTag(tag.id),
                        isAppliedToVideo: localAppliedTagIds.contains(tag.id),
                        isApplying: applyingTagId == tag.id,
                        showVideoActions: currentVideoId != nil,
                        onApplyToVideo: {
                            applyTagToVideo(tag)
                        },
                        onDetachFromVideo: {
                            detachTagFromVideo(tag)
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            tagToDelete = tag
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            tagToEdit = tag
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            } footer: {
                tagCountFooter
            }
        }
        .listStyle(.insetGrouped)
    }

    private func smartListCountForTag(_ tagId: UUID) -> Int {
        SmartListQueryBuilder.findSmartListsContainingTag(smartLists, tagId: tagId).count
    }

    private var tagCountFooter: some View {
        Text("\(tags.count) of \(maxTagCount) tags used")
            .foregroundStyle(tags.count >= maxTagCount ? .red : .secondary)
    }

    // MARK: - Apply/Detach Tag

    private func applyTagToVideo(_ tag: TagInfo) {
        guard let fileId = currentVideoId, let serverURL = serverURL else {
            AppLogger.video.error("applyTagToVideo: Missing fileId or serverURL")
            return
        }

        AppLogger.video.info("applyTagToVideo: Starting - fileId=\(fileId), tag=\(tag.name) (\(tag.id))")

        applyingTagId = tag.id

        Task { @MainActor in
            do {
                // Additive attach: never resend a possibly stale full set,
                // which would drop tags added meanwhile from another client.
                let serverTagIds = try await contentLibraryService.attachTag(
                    fileId: fileId,
                    tagId: tag.id,
                    serverURL: serverURL
                )

                localAppliedTagIds = serverTagIds.union([tag.id])
                applyingTagId = nil

                onTagAppliedToVideo?(tag)
            } catch {
                AppLogger.video.error("applyTagToVideo: Failed - \(error.localizedDescription)")
                applyingTagId = nil
                deleteError = String(localized: "Failed to apply tag: \(error.localizedDescription)")
                showDeleteError = true
            }
        }
    }

    private func detachTagFromVideo(_ tag: TagInfo) {
        guard let fileId = currentVideoId, let serverURL = serverURL else {
            AppLogger.video.error("detachTagFromVideo: Missing fileId or serverURL")
            return
        }

        AppLogger.video.info("detachTagFromVideo: Starting - fileId=\(fileId), tag=\(tag.name) (\(tag.id))")
        AppLogger.video.info("detachTagFromVideo: localAppliedTagIds before=\(localAppliedTagIds.map { $0.uuidString })")

        applyingTagId = tag.id

        Task { @MainActor in
            do {
                try await contentLibraryService.detachTag(
                    fileId: fileId,
                    tagId: tag.id,
                    serverURL: serverURL
                )

                localAppliedTagIds.remove(tag.id)
                applyingTagId = nil

                AppLogger.video.info("detachTagFromVideo: Success - localAppliedTagIds after=\(localAppliedTagIds.map { $0.uuidString })")

                onTagAppliedToVideo?(tag)
            } catch {
                AppLogger.video.error("detachTagFromVideo: Failed - \(error.localizedDescription)")
                applyingTagId = nil
                deleteError = String(localized: "Failed to detach tag: \(error.localizedDescription)")
                showDeleteError = true
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Tags", systemImage: "tag")
        } description: {
            Text("Create tags to organize and categorize your videos.")
        } actions: {
            Button("Create Tag") {
                isShowingCreateForm = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Tag Row View

struct TagRowView: View {
    let tag: TagInfo
    let smartListCount: Int
    let isAppliedToVideo: Bool
    let isApplying: Bool
    let showVideoActions: Bool
    let onApplyToVideo: () -> Void
    let onDetachFromVideo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tag.swiftUIColor)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "film")
                            .font(.caption2)
                        Text("\(tag.videoCount) videos")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)

                    if tag.ratingEnabled {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                            Text("Rating enabled")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }

                    if smartListCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.caption2)
                            Text("\(smartListCount) Smart Lists")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if showVideoActions {
                if isApplying {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 60)
                } else if isAppliedToVideo {
                    Button {
                        onDetachFromVideo()
                    } label: {
                        Text("Detach")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button {
                        onApplyToVideo()
                    } label: {
                        Text("Apply")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [String(localized: "\(tag.name) tag")]
        if tag.ratingEnabled {
            parts.append(String(localized: "rating enabled"))
        }
        if smartListCount > 0 {
            parts.append(String(localized: "used in \(smartListCount) Smart Lists"))
        }
        if showVideoActions {
            parts.append(isAppliedToVideo ? String(localized: "applied to video") : String(localized: "not applied to video"))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

#Preview("Tag Management") {
    struct PreviewWrapper: View {
        @State private var tags = [
            TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: false),
            TagInfo(id: UUID(), name: "comedy", color: "#22C55E", ratingEnabled: true),
            TagInfo(id: UUID(), name: "drama", color: "#3B82F6", ratingEnabled: false)
        ]

        var body: some View {
            NavigationStack {
                TagManagementContentView(
                    tags: $tags,
                    smartLists: [],
                    serverURL: URL(string: "http://localhost:8080"),
                    onDeleteTag: { _ in }
                )
                .navigationTitle("Tags")
            }
        }
    }

    return PreviewWrapper()
}

#Preview("Empty Tags") {
    struct PreviewWrapper: View {
        @State private var tags: [TagInfo] = []

        var body: some View {
            NavigationStack {
                TagManagementContentView(
                    tags: $tags,
                    smartLists: [],
                    serverURL: URL(string: "http://localhost:8080"),
                    onDeleteTag: { _ in }
                )
                .navigationTitle("Tags")
            }
        }
    }

    return PreviewWrapper()
}
