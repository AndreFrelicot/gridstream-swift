//
//  SmartListFormView.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

/// Form view for creating or editing a Smart List.
/// Provides name field, dynamic condition rows, and preview count display.
///
/// This view calls SmartListService directly for create/update operations to avoid
/// callback chain corruption issues in SwiftUI. The onCreated/onUpdated callbacks
/// only receive the result after the service call completes successfully.
struct SmartListFormView: View {
    enum Mode {
        case create
        case edit(SmartListInfo)

        var title: LocalizedStringResource {
            switch self {
            case .create: return "Create Smart List"
            case .edit: return "Edit Smart List"
            }
        }

        var saveButtonTitle: LocalizedStringResource {
            switch self {
            case .create: return "Create"
            case .edit: return "Save"
            }
        }

        var smartListId: UUID? {
            switch self {
            case .create: return nil
            case .edit(let smartList): return smartList.id
            }
        }
    }

    let mode: Mode
    let existingNames: Set<String>
    let tags: [TagInfo]
    let sourceDirectories: [SourceDirectoryDTO]
    let simpleLists: [SimpleListDTO]
    let smartLists: [SmartListInfo]
    let tiles: [Tile]
    let serverURL: URL?
    /// Called after a Smart List is successfully created. Passes the result, not the input data.
    let onCreated: (SmartListInfo) -> Void
    /// Called after a Smart List is successfully updated. Passes the result, not the input data.
    let onUpdated: (SmartListInfo) -> Void
    let onCancel: () -> Void
    let onApplyToTile: (SmartListInfo, Int) -> Void

    @State private var name: String = ""
    @State private var conditions: [FilterCondition] = []
    @State private var previewCount: Int?
    @State private var previewVideos: [VideoItem] = []
    @State private var isLoadingPreview = false
    @State private var previewError: Error?
    @State private var showingTilePicker = false
    @State private var selectedTileIndex: Int?
    @State private var isSaving = false
    @State private var saveError: Error?
    @State private var showSaveError = false

    // Debounce timer for preview count
    @State private var previewDebounceTask: Task<Void, Never>?

    /// Service for Smart List operations - created locally to avoid actor boundary issues
    private let smartListService = SmartListService()
    /// Service for fetching preview videos
    private let contentLibraryService = ContentLibraryService()

    init(
        mode: Mode,
        existingNames: Set<String>,
        tags: [TagInfo],
        sourceDirectories: [SourceDirectoryDTO],
        simpleLists: [SimpleListDTO] = [],
        smartLists: [SmartListInfo] = [],
        tiles: [Tile],
        serverURL: URL?,
        onCreated: @escaping (SmartListInfo) -> Void,
        onUpdated: @escaping (SmartListInfo) -> Void,
        onCancel: @escaping () -> Void,
        onApplyToTile: @escaping (SmartListInfo, Int) -> Void
    ) {
        self.mode = mode
        self.existingNames = existingNames
        self.tags = tags
        self.sourceDirectories = sourceDirectories
        self.simpleLists = simpleLists
        self.smartLists = smartLists
        self.tiles = tiles
        self.serverURL = serverURL
        self.onCreated = onCreated
        self.onUpdated = onUpdated
        self.onCancel = onCancel
        self.onApplyToTile = onApplyToTile

        if case .edit(let smartList) = mode {
            _name = State(initialValue: smartList.name)
            _conditions = State(initialValue: smartList.criteria.conditions)
        }
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNameValid: Bool {
        !normalizedName.isEmpty && !existingNames.contains(normalizedName.lowercased())
    }

    private var nameValidationMessage: String? {
        let trimmed = normalizedName
        if trimmed.isEmpty {
            return nil
        }
        if existingNames.contains(trimmed.lowercased()) {
            return String(localized: "A smart list with this name already exists")
        }
        return nil
    }

    private var usedCategories: Set<CriteriaCategory> {
        Set(conditions.map { $0.criteriaType.category }.filter { $0 != .simpleList && $0 != .smartList })
    }

    /// Smart lists available for the "In Smart List" filter, excluding self to prevent circular references
    private var availableSmartLists: [SmartListInfo] {
        if let editId = mode.smartListId {
            return smartLists.filter { $0.id != editId }
        }
        return smartLists
    }

    private var canAddCondition: Bool {
        true
    }

    var body: some View {
        NavigationStack {
            Form {
                // Name Section
                nameSection

                // Conditions Section
                conditionsSection

                // Preview Section
                previewSection

                // Apply to Tile Section (only in edit mode and when tiles are available)
                if case .edit = mode, !tiles.isEmpty {
                    applyToTileSection
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.saveButtonTitle) {
                        Task {
                            await saveSmartList()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isNameValid || isSaving)
                }
            }
            .onChange(of: conditions) { _, _ in
                updatePreviewCountDebounced()
            }
            .onAppear {
                updatePreviewCountDebounced()
            }
            .sheet(isPresented: $showingTilePicker) {
                FormTilePickerSheet(
                    tiles: tiles,
                    selectedIndex: $selectedTileIndex,
                    onApply: { tileIndex in
                        if case .edit(let smartList) = mode {
                            onApplyToTile(smartList, tileIndex)
                        }
                        showingTilePicker = false
                    },
                    onCancel: {
                        showingTilePicker = false
                    }
                )
            }
            .alert("Error", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError?.localizedDescription ?? String(localized: "An error occurred while saving"))
            }
        }
    }

    // MARK: - Save Smart List

    /// Saves the Smart List by calling the service directly.
    /// This avoids callback chain corruption issues by encoding data locally before the async call.
    @MainActor
    private func saveSmartList() async {
        guard let serverURL = serverURL else {
            saveError = APIError.invalidURL
            showSaveError = true
            return
        }

        isSaving = true

        do {
            // Encode criteria to JSON string locally on main actor BEFORE crossing actor boundary
            let criteria = SmartListCriteria(conditions: conditions)
            let criteriaJSON = try encodeCriteriaToJSON(criteria)

            switch mode {
            case .create:
                // Call service directly with pre-encoded JSON string
                let createdSmartList = try await smartListService.createSmartList(
                    name: normalizedName,
                    criteriaJSON: criteriaJSON,
                    serverURL: serverURL
                )
                // Success - notify parent with result
                onCreated(createdSmartList)

            case .edit(let existingSmartList):
                // Call service directly with pre-encoded JSON string
                let updatedSmartList = try await smartListService.updateSmartList(
                    id: existingSmartList.id,
                    name: normalizedName,
                    criteriaJSON: criteriaJSON,
                    serverURL: serverURL
                )
                // Success - notify parent with result
                onUpdated(updatedSmartList)
            }
        } catch {
            saveError = error
            showSaveError = true
        }

        isSaving = false
    }

    /// Encodes SmartListCriteria to JSON string synchronously on main actor.
    /// Done before any async calls to avoid actor boundary issues.
    @MainActor
    private func encodeCriteriaToJSON(_ criteria: SmartListCriteria) throws -> String {
        // ISO 8601 dates (contract §1); the default `.deferredToDate`
        // strategy emitted a bare number the server and web can't read.
        let data = try JSONEncoder.gridStream().encode(criteria)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw APIError.encodingError
        }
        return jsonString
    }

    // MARK: - Name Section

    private var nameSection: some View {
        Section {
            TextField("Smart List Name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            if let validationMessage = nameValidationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Name")
        } footer: {
            Text("Give your smart list a descriptive name.")
        }
    }

    // MARK: - Conditions Section

    private var conditionsSection: some View {
        Section {
            if conditions.isEmpty {
                Text("No conditions added")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(Array(conditions.enumerated()), id: \.element.id) { index, condition in
                    SmartListConditionRow(
                        condition: binding(for: condition),
                        isFirst: index == 0,
                        tags: tags,
                        sourceDirectories: sourceDirectories,
                        simpleLists: simpleLists,
                        smartLists: availableSmartLists,
                        usedCategories: usedCategoriesExcluding(condition),
                        onRemove: {
                            removeCondition(condition)
                        }
                    )
                }
                .onDelete { indexSet in
                    conditions.remove(atOffsets: indexSet)
                }
            }

            Button {
                addCondition()
            } label: {
                Label("Add Condition", systemImage: "plus.circle")
            }
            .disabled(!canAddCondition)
        } header: {
            Text("Conditions")
        } footer: {
            Text("Add conditions to filter which videos appear.")
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                previewStatusRow

                if !previewVideos.isEmpty {
                    previewThumbnailsView
                }
            }
        } header: {
            Text("Preview")
        } footer: {
            if let count = previewCount, count == 0 {
                Text("No videos match these conditions. Consider adjusting your filters.")
                    .foregroundColor(.orange)
            }
        }
    }

    private var previewStatusRow: some View {
        HStack {
            if isLoadingPreview {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading preview...")
                    .foregroundStyle(.secondary)
            } else if let count = previewCount {
                Image(systemName: count > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(count > 0 ? .green : .orange)
                Text("\(count) matching videos")
                    .foregroundColor(count > 0 ? .primary : .orange)
            } else if previewError != nil {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Could not load preview")
                    .foregroundStyle(.secondary)
            } else {
                Text("Add conditions to see preview")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previewThumbnailsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(previewVideos.prefix(15)) { video in
                    previewThumbnailCell(for: video)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func previewThumbnailCell(for video: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: thumbnailURL(for: video)) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                case .failure:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "film")
                                .foregroundStyle(.secondary)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(video.filename)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 120, alignment: .leading)
        }
    }

    private func thumbnailURL(for video: VideoItem) -> URL? {
        guard let serverURL = serverURL else { return nil }
        // Server-provided versioned URL, authorized for the media route
        return VideoURLBuilder.authorizedThumbnailURL(for: video, serverURL: serverURL)
    }

    // MARK: - Apply to Tile Section

    private var applyToTileSection: some View {
        Section {
            Button {
                showingTilePicker = true
            } label: {
                Label("Apply to Tile", systemImage: "square.grid.2x2")
            }
        } header: {
            Text("Tile Assignment")
        } footer: {
            Text("Apply this smart list to a tile to filter its video selection.")
        }
    }

    // MARK: - Helpers

    private func binding(for condition: FilterCondition) -> Binding<FilterCondition> {
        Binding(
            get: {
                conditions.first { $0.id == condition.id } ?? condition
            },
            set: { newValue in
                if let index = conditions.firstIndex(where: { $0.id == condition.id }) {
                    conditions[index] = newValue
                }
            }
        )
    }

    private func usedCategoriesExcluding(_ condition: FilterCondition) -> Set<CriteriaCategory> {
        Set(conditions.filter { $0.id != condition.id }.map { $0.criteriaType.category }.filter { $0 != .simpleList && $0 != .smartList })
    }

    private func addCondition() {
        // Find an unused category (simpleList and smartList are excluded from usedCategories so always available)
        let unusedCategories = Set(CriteriaCategory.allCases).subtracting(usedCategories)
        let category = unusedCategories.first(where: { $0 != .simpleList && $0 != .smartList }) ?? .simpleList

        let criteriaType = defaultCriteriaType(for: category)
        let newCondition = FilterCondition(
            criteriaType: criteriaType,
            logicOperator: .and
        )
        conditions.append(newCondition)
    }

    private func removeCondition(_ condition: FilterCondition) {
        conditions.removeAll { $0.id == condition.id }
    }

    private func defaultCriteriaType(for category: CriteriaCategory) -> CriteriaType {
        switch category {
        case .tags:
            return .tagsInclude(tagIds: [], tagRatings: [])
        case .rating:
            return .ratingMin(value: 3)
        case .source:
            return .sourceDirectory(id: sourceDirectories.first?.id ?? "")
        case .fileSize:
            return .fileSizeMin(megabytes: 100)
        case .filename:
            return .filenameContains(text: "")
        case .date:
            return .dateAddedAfter(date: Date().addingTimeInterval(-86400 * 30))
        case .playCount:
            return .playCountMin(value: 1)
        case .annotations:
            return .hasAnnotations(value: true)
        case .segments:
            return .hasTimeRanges(value: true)
        case .simpleList:
            return .simpleListInclude(simpleListId: UUID())
        case .smartList:
            return .smartListInclude(smartListId: UUID())
        }
    }

    private func updatePreviewCountDebounced() {
        previewDebounceTask?.cancel()
        previewDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await updatePreviewCount()
        }
    }

    @MainActor
    private func updatePreviewCount() async {
        guard !conditions.isEmpty else {
            previewCount = nil
            previewVideos = []
            return
        }

        guard let serverURL = serverURL else {
            previewError = APIError.invalidURL
            previewCount = nil
            previewVideos = []
            return
        }

        isLoadingPreview = true
        previewError = nil

        do {
            // Build criteria and fetch videos (which includes count)
            let criteria = SmartListCriteria(conditions: conditions)
            let result = try await contentLibraryService.fetchVideosWithSmartListCriteria(
                from: serverURL,
                criteria: criteria,
                limit: 15,
                offset: 0
            )
            previewCount = result.total
            previewVideos = result.videos
        } catch {
            previewError = error
            previewCount = nil
            previewVideos = []
        }

        isLoadingPreview = false
    }

    /// Builds query parameters from conditions - done locally to avoid actor boundary issues
    @MainActor
    private func buildQueryParams(from conditions: [FilterCondition]) -> [String: String] {
        var params: [String: String] = [:]

        for condition in conditions {
            switch condition.criteriaType {
            case .tagsInclude(let tagIds, let tagRatings):
                params["tags"] = tagIds.map { $0.uuidString }.joined(separator: ",")
                // Add tag ratings if any have filters
                let ratingsWithFilter = tagRatings.filter { $0.hasRatingFilter }
                if !ratingsWithFilter.isEmpty {
                    let tagRatingsString = ratingsWithFilter.map { filter -> String in
                        let min = filter.minRating.map { String($0) } ?? ""
                        let max = filter.maxRating.map { String($0) } ?? ""
                        return "\(filter.tagId.uuidString):\(min)-\(max)"
                    }.joined(separator: ",")
                    params["tagRatings"] = tagRatingsString
                }
            case .tagsExclude(let tagIds):
                params["excludeTags"] = tagIds.map { $0.uuidString }.joined(separator: ",")
            case .ratingMin(let value):
                params["minRating"] = String(value)
            case .ratingMax(let value):
                params["maxRating"] = String(value)
            case .sourceDirectory(let id):
                params["sourceDirectoryId"] = id
            case .fileSizeMin(let megabytes):
                params["minFileSize"] = String(Int64(megabytes * 1024 * 1024))
            case .fileSizeMax(let megabytes):
                params["maxFileSize"] = String(Int64(megabytes * 1024 * 1024))
            case .filenameContains(let text):
                params["search"] = text
            case .filenameStartsWith(let text):
                params["filenameStartsWith"] = text
            case .filenameEndsWith(let text):
                params["filenameEndsWith"] = text
            case .filenameRegex(let pattern):
                params["filenameRegex"] = pattern
            case .dateAddedAfter(let date):
                params["addedAfter"] = ISO8601DateFormatter().string(from: date)
            case .dateAddedBefore(let date):
                params["addedBefore"] = ISO8601DateFormatter().string(from: date)
            case .dateModifiedAfter(let date):
                params["modifiedAfter"] = ISO8601DateFormatter().string(from: date)
            case .dateModifiedBefore(let date):
                params["modifiedBefore"] = ISO8601DateFormatter().string(from: date)
            case .playCountMin(let value):
                params["minPlayCount"] = String(value)
            case .playCountMax(let value):
                params["maxPlayCount"] = String(value)
            case .hasAnnotations(let value):
                params["hasAnnotations"] = String(value)
            case .annotationCountMin(let value):
                params["minAnnotationCount"] = String(value)
            case .annotationCountMax(let value):
                params["maxAnnotationCount"] = String(value)
            case .hasTextAnnotations(let value):
                params["hasTextAnnotations"] = String(value)
            case .annotationTextSearch(let text):
                params["annotationTextSearch"] = text
            case .hasTimeRanges(let value):
                params["hasTimeRanges"] = String(value)
            case .simpleListInclude(let listId):
                params["simpleListIds"] = listId.uuidString
            case .smartListInclude(let smartListId):
                params["smartListIds"] = smartListId.uuidString
            case .unrated:
                params["unrated"] = "true"
            case .unplayed:
                params["unplayed"] = "true"
            }
        }

        return params
    }
}

// MARK: - Tile Picker Sheet

private struct FormTilePickerSheet: View {
    let tiles: [Tile]
    @Binding var selectedIndex: Int?
    let onApply: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                    Button {
                        selectedIndex = index
                    } label: {
                        HStack {
                            Image(systemName: "square.fill")
                                .foregroundStyle(.blue)

                            Text("Tile \(index + 1)")

                            if tile.hasVideo {
                                Text("(has video)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if selectedIndex == index {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Tile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if let index = selectedIndex {
                            onApply(index)
                        }
                    }
                    .disabled(selectedIndex == nil)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Create Mode") {
    SmartListFormView(
        mode: .create,
        existingNames: ["favorites", "recent"],
        tags: [
            TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: false),
            TagInfo(id: UUID(), name: "comedy", color: "#22C55E", ratingEnabled: true)
        ],
        sourceDirectories: [
            SourceDirectoryDTO(id: "1", name: "Movies", path: "/movies"),
            SourceDirectoryDTO(id: "2", name: "TV Shows", path: "/tv")
        ],
        simpleLists: [],
        tiles: [Tile(index: 0), Tile(index: 1)],
        serverURL: URL(string: "http://localhost:8080"),
        onCreated: { _ in },
        onUpdated: { _ in },
        onCancel: {},
        onApplyToTile: { _, _ in }
    )
}

#Preview("Edit Mode") {
    SmartListFormView(
        mode: .edit(SmartListInfo(
            name: "Favorites",
            criteria: SmartListCriteria(conditions: [
                FilterCondition(criteriaType: .ratingMin(value: 4), logicOperator: .and),
                FilterCondition(criteriaType: .playCountMin(value: 5), logicOperator: .or)
            ])
        )),
        existingNames: ["recent"],
        tags: [
            TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: false)
        ],
        sourceDirectories: [],
        simpleLists: [],
        tiles: [Tile(index: 0)],
        serverURL: URL(string: "http://localhost:8080"),
        onCreated: { _ in },
        onUpdated: { _ in },
        onCancel: {},
        onApplyToTile: { _, _ in }
    )
}
