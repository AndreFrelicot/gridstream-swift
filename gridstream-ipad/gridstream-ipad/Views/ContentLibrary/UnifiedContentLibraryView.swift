//
//  UnifiedContentLibraryView.swift
//  gridstream-ipad
//

import GridStreamAPI
import OSLog
import SwiftUI

/// Tab options for the unified content library
enum UnifiedContentTab: String, CaseIterable {
    case content = "content"
    case history = "history"
    case tags = "tags"
    case smartLists = "smartLists"
    case simpleLists = "simpleLists"
    case audio = "audio"
    case presets = "presets"
    case diagnostics = "diagnostics"

    var title: LocalizedStringResource {
        switch self {
        case .content: return "Content"
        case .history: return "History"
        case .tags: return "Tags"
        case .smartLists: return "Smart Lists"
        case .simpleLists: return "Simple Lists"
        case .audio: return "Audio"
        case .presets: return "Presets"
        case .diagnostics: return "Diagnostics"
        }
    }

    var icon: String {
        switch self {
        case .content: return "square.grid.2x2"
        case .history: return "clock.arrow.circlepath"
        case .tags: return "tag"
        case .smartLists: return "list.bullet.rectangle"
        case .simpleLists: return "rectangle.stack"
        case .audio: return "speaker.wave.3"
        case .presets: return "square.stack.3d.up"
        case .diagnostics: return "waveform.path.ecg"
        }
    }
}

/// Unified container view combining Content Library, Tag Management, and Smart List Management.
/// Provides browsing, filtering, selection, tag CRUD, and smart list CRUD in a single dialog.
struct UnifiedContentLibraryView: View {
    @Binding var isPresented: Bool
    let serverURL: URL?

    var initialTab: UnifiedContentTab = .content
    var currentVideoId: String? = nil
    var appliedTagIds: Set<UUID> = []
    var onTagAppliedToVideo: ((TagInfo) -> Void)? = nil
    var targetTileIndex: Int? = nil
    var onVideoSelected: ((VideoItem) -> Void)? = nil
    /// Legacy callbacks: apply a list to `targetTileIndex`, ignoring the tile
    /// chosen in a tile picker. Prefer the `...At` variants.
    var onApplySmartListToTile: ((UUID) -> Void)? = nil
    var onApplySimpleListToTile: ((UUID) -> Void)? = nil
    /// Apply a list to the tile at the given index (the one chosen in the
    /// tile picker, or `targetTileIndex`). Take precedence over the legacy
    /// callbacks.
    var onApplySmartListToTileAt: ((UUID, Int) -> Void)? = nil
    var onApplySimpleListToTileAt: ((UUID, Int) -> Void)? = nil
    var tiles: [Tile] = []
    var activePreset: LayoutPreset? = nil
    var orientation: LayoutOrientation = .horizontal
    var initialSmartListId: UUID? = nil
    var initialSimpleListId: UUID? = nil

    @Environment(CatalogStatusManager.self) private var catalogStatusManager: CatalogStatusManager?

    // MARK: - State

    @State private var library: ContentLibraryState
    @State private var selectedTab: UnifiedContentTab

    @State private var selectedVideoIds: Set<String> = []
    @State private var isMultiSelectEnabled = false

    @State private var showingTagPicker = false
    @State private var showingTagFilterPicker = false
    @State private var showingRatingPicker = false
    @State private var showingRatingFilterPicker = false
    @State private var showingSourceDirectoryPicker = false
    @State private var showingSmartListForm = false
    @State private var editingSmartList: SmartListInfo?
    @State private var showingSimpleListPicker = false

    @State private var selectedTagIds: Set<UUID> = []
    @State private var bulkRating: Int = 5
    @State private var bulkErrorMessage: String?

    // Tile picker state for content tab list selection
    @State private var showingContentTabTilePicker = false
    @State private var listToApplyFromContentTab: (name: String, isSmartList: Bool, id: UUID)?

    private let contentLibraryService = ContentLibraryService()
    private let smartListService = SmartListService()
    private let simpleListService = SimpleListService()

    // MARK: - Initializer

    init(
        isPresented: Binding<Bool>,
        serverURL: URL?,
        initialTab: UnifiedContentTab = .content,
        currentVideoId: String? = nil,
        appliedTagIds: Set<UUID> = [],
        onTagAppliedToVideo: ((TagInfo) -> Void)? = nil,
        targetTileIndex: Int? = nil,
        onVideoSelected: ((VideoItem) -> Void)? = nil,
        onApplySmartListToTile: ((UUID) -> Void)? = nil,
        onApplySimpleListToTile: ((UUID) -> Void)? = nil,
        onApplySmartListToTileAt: ((UUID, Int) -> Void)? = nil,
        onApplySimpleListToTileAt: ((UUID, Int) -> Void)? = nil,
        tiles: [Tile] = [],
        activePreset: LayoutPreset? = nil,
        orientation: LayoutOrientation = .horizontal,
        initialSmartListId: UUID? = nil,
        initialSimpleListId: UUID? = nil
    ) {
        self._isPresented = isPresented
        self.serverURL = serverURL
        self.initialTab = initialTab
        self.currentVideoId = currentVideoId
        self.appliedTagIds = appliedTagIds
        self.onTagAppliedToVideo = onTagAppliedToVideo
        self.targetTileIndex = targetTileIndex
        self.onVideoSelected = onVideoSelected
        self.onApplySmartListToTile = onApplySmartListToTile
        self.onApplySimpleListToTile = onApplySimpleListToTile
        self.onApplySmartListToTileAt = onApplySmartListToTileAt
        self.onApplySimpleListToTileAt = onApplySimpleListToTileAt
        self.tiles = tiles
        self.activePreset = activePreset
        self.orientation = orientation
        self.initialSmartListId = initialSmartListId
        self.initialSimpleListId = initialSimpleListId

        self._selectedTab = State(initialValue: initialTab)
        self._library = State(initialValue: ContentLibraryState(
            serverURL: serverURL, initialSmartListId: initialSmartListId, initialSimpleListId: initialSimpleListId
        ))
    }

    // MARK: - Computed Properties

    private var catalogIsDirty: Bool {
        catalogStatusManager?.catalogIsDirty ?? false
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker
                    .padding(.horizontal)
                    .padding(.top, 8)

                Divider()
                    .padding(.top, 8)

                tabContent
            }
            .navigationTitle("Content Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
        }
        .task(id: serverURL) {
            library.configure(serverURL: serverURL)
            await library.loadInitialData()
        }
        .onChange(of: library.filters) { _, _ in
            library.scheduleRefresh()
        }
        .onDisappear {
            library.cancelRefresh()
        }
        .alert(
            "Bulk Operation Failed",
            isPresented: Binding(
                get: { bulkErrorMessage != nil },
                set: { if !$0 { bulkErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { bulkErrorMessage = nil }
        } message: {
            Text(bulkErrorMessage ?? "")
        }
        .sheet(isPresented: $showingTagPicker) {
            tagPickerSheet
        }
        .sheet(isPresented: $showingTagFilterPicker) {
            tagFilterPickerSheet
        }
        .sheet(isPresented: $showingRatingPicker) {
            ratingPickerSheet
        }
        .sheet(isPresented: $showingRatingFilterPicker) {
            ratingFilterPickerSheet
        }
        .sheet(isPresented: $showingSourceDirectoryPicker) {
            sourceDirectoryPickerSheet
        }
        .sheet(isPresented: $showingSmartListForm) {
            smartListFormSheet
        }
        .sheet(isPresented: $showingSimpleListPicker) {
            SimpleListPickerSheet(
                videoIds: Array(selectedVideoIds),
                serverURL: serverURL,
                onDismiss: {
                    showingSimpleListPicker = false
                },
                onSuccess: { _ in
                    showingSimpleListPicker = false
                    clearSelection()
                }
            )
        }
        .sheet(isPresented: $showingContentTabTilePicker) {
            if let listInfo = listToApplyFromContentTab {
                TilePickerSheet(
                    tiles: tiles,
                    listName: listInfo.name,
                    activePreset: activePreset,
                    orientation: orientation,
                    currentTileIndex: targetTileIndex,
                    onApply: { tileIndex in
                        if listInfo.isSmartList {
                            applySmartList(listInfo.id, toTileAt: tileIndex)
                        } else {
                            applySimpleList(listInfo.id, toTileAt: tileIndex)
                        }
                        showingContentTabTilePicker = false
                        listToApplyFromContentTab = nil
                        isPresented = false
                    },
                    onCancel: {
                        showingContentTabTilePicker = false
                        listToApplyFromContentTab = nil
                    }
                )
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(UnifiedContentTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.icon)
                            .font(.subheadline)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
                            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .accessibilityLabel("Content library tab selector")
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .content:
            contentTabView
        case .history:
            historyTabView
        case .tags:
            tagsTabView
        case .smartLists:
            smartListsTabView
        case .simpleLists:
            simpleListsTabView
        case .audio:
            audioTabView
        case .presets:
            presetsTabView
        case .diagnostics:
            diagnosticsTabView
        }
    }

    // MARK: - Content Tab

    private var contentTabView: some View {
        VStack(spacing: 0) {
            if catalogIsDirty {
                catalogRefreshBanner
            }

            smartListSelectorRow
                .padding(.horizontal)
                .padding(.top, 8)

            searchAndFilterSection
                .padding(.horizontal)
                .padding(.vertical, 8)

            if library.filters.hasActiveFilters {
                FilterChipRow(filters: library.filters) { chip in
                    library.filters.removeChip(chip)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            HStack {
                Text("\(library.totalVideoCount) videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 4)

            Divider()

            ZStack {
                VideoGridView(
                    videos: library.videos,
                    serverURL: serverURL,
                    selectedVideoIds: selectedVideoIds,
                    videoRatings: library.videoRatings,
                    isLoading: library.isLoading,
                    errorMessage: library.errorMessage,
                    hasMoreVideos: library.hasMoreVideos,
                    onVideoTap: { video in
                        handleVideoTap(video)
                    },
                    onRetry: {
                        Task {
                            await library.loadInitialData()
                        }
                    },
                    onLoadMore: {
                        Task {
                            await library.loadMoreVideos()
                        }
                    }
                )

                if !selectedVideoIds.isEmpty {
                    VStack {
                        Spacer()
                        BulkOperationsBar(
                            selectedCount: selectedVideoIds.count,
                            onApplyTags: {
                                showingTagPicker = true
                            },
                            onSetRating: {
                                showingRatingPicker = true
                            },
                            onAddToList: {
                                showingSimpleListPicker = true
                            },
                            onClearSelection: {
                                clearSelection()
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - History Tab

    private var historyTabView: some View {
        HistoryTabView(
            serverURL: serverURL,
            onVideoSelected: { video in
                handleVideoTap(video)
            }
        )
    }

    // MARK: - Tags Tab

    private var tagsTabView: some View {
        TagManagementContentView(
            tags: $library.tags,
            smartLists: library.smartLists,
            serverURL: serverURL,
            currentVideoId: currentVideoId,
            appliedTagIds: appliedTagIds,
            onDeleteTag: handleDeleteTag,
            onTagAppliedToVideo: onTagAppliedToVideo,
            onTagsChanged: {
                Task {
                    await library.refreshTags()
                }
            }
        )
    }

    // MARK: - Smart Lists Tab

    private var smartListsTabView: some View {
        SmartListManagementView(
            smartLists: $library.smartLists,
            smartListVideoCounts: library.smartListVideoCounts,
            tags: library.tags,
            sourceDirectories: library.sourceDirectories,
            simpleLists: library.simpleLists,
            tiles: tiles,
            targetTileIndex: targetTileIndex,
            activePreset: activePreset,
            orientation: orientation,
            serverURL: serverURL,
            onDeleteSmartList: handleDeleteSmartList,
            onApplyToTile: { smartList, tileIndex in
                applySmartList(smartList.id, toTileAt: tileIndex)
                isPresented = false
            }
        )
    }

    // MARK: - Simple Lists Tab

    private var simpleListsTabView: some View {
        SimpleListManagementView(
            simpleLists: $library.simpleLists,
            tiles: tiles,
            targetTileIndex: targetTileIndex,
            activePreset: activePreset,
            orientation: orientation,
            serverURL: serverURL,
            onDeleteSimpleList: handleDeleteSimpleList,
            onApplyToTile: { simpleList, tileIndex in
                applySimpleList(simpleList.id, toTileAt: tileIndex)
                isPresented = false
            }
        )
    }

    // MARK: - Audio Tab

    private var audioTabView: some View {
        AudioSettingsTabView()
    }

    // MARK: - Presets Tab

    private var presetsTabView: some View {
        SourcePresetsSettingsView(
            smartLists: library.smartLists,
            simpleLists: library.simpleLists,
            onDismiss: {
                isPresented = false
            }
        )
    }

    // MARK: - Diagnostics Tab

    private var diagnosticsTabView: some View {
        PlaybackDiagnosticsView()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                library.saveFiltersIfNeeded()
                isPresented = false
            }
        }

        ToolbarItem(placement: .primaryAction) {
            if selectedTab == .content {
                HStack(spacing: 8) {
                    if isMultiSelectEnabled && !selectedVideoIds.isEmpty {
                        Text("\(selectedVideoIds.count) selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        toggleMultiSelect()
                    } label: {
                        Image(systemName: isMultiSelectEnabled ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 20))
                    }
                    .accessibilityLabel(isMultiSelectEnabled ? "Exit multi-select mode" : "Enter multi-select mode")
                }
            } else {
                Button("Done") {
                    library.saveFiltersIfNeeded()
                    isPresented = false
                }
            }
        }
    }

    // MARK: - Smart List Selector Row

    private var smartListSelectorRow: some View {
        HStack(spacing: 12) {
            Text("Viewing:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Menu {
                Button {
                    library.selectedSmartListId = nil
                    library.selectedSimpleListId = nil
                    library.activeSmartListCriteria = nil
                    library.filters.clear()
                    library.scheduleRefresh()
                } label: {
                    HStack {
                        Text("All Videos")
                        if library.selectedSmartListId == nil && library.selectedSimpleListId == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                if !library.smartLists.isEmpty {
                    Divider()

                    ForEach(library.smartLists) { smartList in
                        Button {
                            library.selectSmartList(smartList)
                        } label: {
                            HStack {
                                Text("\(smartList.name) (\(library.smartListVideoCounts[smartList.id].map { "\($0)" } ?? "…"))")
                                if library.selectedSmartListId == smartList.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                if !library.simpleLists.isEmpty {
                    Divider()

                    ForEach(library.simpleLists) { simpleList in
                        Button {
                            library.selectSimpleList(simpleList)
                        } label: {
                            HStack {
                                Text("\(simpleList.name) (\(simpleList.videoCount))")
                                if library.selectedSimpleListId == simpleList.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

                Button {
                    showingSmartListForm = true
                    editingSmartList = nil
                } label: {
                    Label("Create Smart List...", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedListIcon)
                        .font(.system(size: 14))

                    Text(selectedListName)
                        .fontWeight(.medium)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(hasListSelected ? 0.15 : 0.08))
                .foregroundColor(hasListSelected ? .accentColor : .primary)
                .clipShape(Capsule())
            }

            Spacer()

            if let selectedId = library.selectedSmartListId,
               let smartList = library.smartLists.first(where: { $0.id == selectedId }) {
                Button {
                    editingSmartList = smartList
                    showingSmartListForm = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Edit Smart List")

                // Show Apply to Tile button when tiles are available
                if !tiles.isEmpty {
                    Button {
                        if let targetTileIndex, hasApplySmartListCallback {
                            // Direct apply when target tile is known
                            applySmartList(selectedId, toTileAt: targetTileIndex)
                        } else {
                            // Show tile picker to let user choose
                            listToApplyFromContentTab = (name: smartList.name, isSmartList: true, id: selectedId)
                            showingContentTabTilePicker = true
                        }
                    } label: {
                        Label(targetTileIndex != nil ? "Apply to Tile" : "Apply...", systemImage: "square.on.square")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Apply Smart List to tile")
                }
            } else if let selectedId = library.selectedSimpleListId,
                      let simpleList = library.simpleLists.first(where: { $0.id == selectedId }) {
                // Show Apply to Tile button when tiles are available
                if !tiles.isEmpty {
                    Button {
                        if let targetTileIndex, hasApplySimpleListCallback {
                            // Direct apply when target tile is known
                            applySimpleList(selectedId, toTileAt: targetTileIndex)
                        } else {
                            // Show tile picker to let user choose
                            listToApplyFromContentTab = (name: simpleList.name, isSmartList: false, id: selectedId)
                            showingContentTabTilePicker = true
                        }
                    } label: {
                        Label(targetTileIndex != nil ? "Apply to Tile" : "Apply...", systemImage: "square.on.square")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Apply Simple List to tile")
                }
            }
        }
    }

    private var hasListSelected: Bool {
        library.selectedSmartListId != nil || library.selectedSimpleListId != nil
    }

    private var selectedListIcon: String {
        if library.selectedSmartListId != nil {
            return "list.bullet"
        } else if library.selectedSimpleListId != nil {
            return "rectangle.stack"
        }
        return "square.grid.2x2"
    }

    private var selectedListName: String {
        if let selectedId = library.selectedSmartListId,
           let smartList = library.smartLists.first(where: { $0.id == selectedId }) {
            return smartList.name
        }
        if let selectedId = library.selectedSimpleListId,
           let simpleList = library.simpleLists.first(where: { $0.id == selectedId }) {
            return simpleList.name
        }
        return String(localized: "All Videos")
    }

    // MARK: - Search and Filter Section

    private var searchAndFilterSection: some View {
        HStack(spacing: 12) {
            SearchFilterBar(
                searchText: $library.filters.searchText,
                onSearchCommit: {
                    library.scheduleRefresh()
                }
            )

            filterButtonsRow
        }
    }

    private var filterButtonsRow: some View {
        HStack(spacing: 8) {
            Button {
                showingTagFilterPicker = true
            } label: {
                Image(systemName: "tag")
                    .font(.system(size: 18))
                    .foregroundColor(library.filters.activeTagFilters.isEmpty ? .secondary : .accentColor)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Filter by tags")

            Button {
                showingRatingFilterPicker = true
            } label: {
                Image(systemName: "heart")
                    .font(.system(size: 18))
                    .foregroundColor((library.filters.minRating != nil || library.filters.maxRating != nil) ? .accentColor : .secondary)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Filter by rating")

            Button {
                showingSourceDirectoryPicker = true
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 18))
                    .foregroundColor(library.filters.sourceDirectoryId != nil ? .accentColor : .secondary)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Filter by source directory")

            Toggle(isOn: $library.filters.unratedOnly) {
                Label("Unrated", systemImage: "star.slash.fill")
                    .font(.system(size: 14))
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(library.filters.unratedOnly ? .orange : .secondary)
            .accessibilityLabel("Show unrated videos only")
        }
    }

    // MARK: - Catalog Refresh Banner

    private var catalogRefreshBanner: some View {
        Button {
            Task {
                await handleCatalogRefresh()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 2) {
                    Text("New content available")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Tap to refresh the video list")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if library.isRefreshing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.accentColor.opacity(0.1))
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(library.isRefreshing)
        .accessibilityLabel("Refresh video list")
    }

    // MARK: - Sheet Views

    private var tagPickerSheet: some View {
        TagPickerView(
            availableTags: library.tags,
            selectedTagIds: $selectedTagIds,
            onApply: {
                Task {
                    await applyTagsToSelection()
                }
                showingTagPicker = false
            },
            onDismiss: {
                showingTagPicker = false
            }
        )
    }

    private var tagFilterPickerSheet: some View {
        TagFilterPickerView(
            availableTags: library.tags,
            selectedFilters: $library.filters.activeTagFilters,
            onApply: {
                showingTagFilterPicker = false
            },
            onDismiss: {
                showingTagFilterPicker = false
            }
        )
    }

    private var ratingPickerSheet: some View {
        BulkRatingPickerView(
            rating: $bulkRating,
            onApply: {
                Task {
                    await applyRatingToSelection()
                }
                showingRatingPicker = false
            },
            onDismiss: {
                showingRatingPicker = false
            }
        )
    }

    private var ratingFilterPickerSheet: some View {
        RatingFilterPickerView(
            minRating: Binding(
                get: { library.filters.minRating ?? 0 },
                set: { library.filters.minRating = $0 > 0 ? $0 : nil }
            ),
            maxRating: Binding(
                get: { library.filters.maxRating ?? 10 },
                set: { library.filters.maxRating = $0 < 10 ? $0 : nil }
            ),
            onApply: {
                showingRatingFilterPicker = false
            },
            onDismiss: {
                showingRatingFilterPicker = false
            }
        )
    }

    private var sourceDirectoryPickerSheet: some View {
        SourceDirectoryPickerView(
            directories: library.sourceDirectories,
            selectedDirectoryId: Binding(
                get: { library.filters.sourceDirectoryId },
                set: { id in
                    library.filters.sourceDirectoryId = id
                    library.filters.sourceDirectoryName = library.sourceDirectories.first { $0.id == id }?.name
                }
            ),
            onApply: {
                showingSourceDirectoryPicker = false
            },
            onDismiss: {
                showingSourceDirectoryPicker = false
            }
        )
    }

    @ViewBuilder
    private var smartListFormSheet: some View {
        if let serverURL = serverURL {
            let mode: SmartListFormView.Mode = editingSmartList.map { .edit($0) } ?? .create
            let existingNames = Set(library.smartLists.map { $0.name })

            SmartListFormView(
                mode: mode,
                existingNames: existingNames,
                tags: library.tags,
                sourceDirectories: library.sourceDirectories,
                simpleLists: library.simpleLists,
                smartLists: library.smartLists,
                tiles: tiles,
                serverURL: serverURL,
                onCreated: { newSmartList in
                    library.smartLists.append(newSmartList)
                    library.selectedSmartListId = newSmartList.id
                    library.activeSmartListCriteria = newSmartList.criteria
                    library.filters = ContentLibraryFilters()
                    showingSmartListForm = false
                    library.scheduleRefresh()
                },
                onUpdated: { updatedSmartList in
                    if let index = library.smartLists.firstIndex(where: { $0.id == updatedSmartList.id }) {
                        library.smartLists[index] = updatedSmartList
                        if library.selectedSmartListId == updatedSmartList.id {
                            library.activeSmartListCriteria = updatedSmartList.criteria
                            library.scheduleRefresh()
                        }
                    }
                    showingSmartListForm = false
                },
                onCancel: {
                    showingSmartListForm = false
                    editingSmartList = nil
                },
                onApplyToTile: { smartList, tileIndex in
                    applySmartList(smartList.id, toTileAt: tileIndex)
                }
            )
        }
    }

    // MARK: - Actions

    private var hasApplySmartListCallback: Bool {
        onApplySmartListToTileAt != nil || onApplySmartListToTile != nil
    }

    private var hasApplySimpleListCallback: Bool {
        onApplySimpleListToTileAt != nil || onApplySimpleListToTile != nil
    }

    /// Applies a smart list to the tile the user chose (the index used to be
    /// dropped, so the list always landed on the selected tile or tile 0).
    private func applySmartList(_ id: UUID, toTileAt tileIndex: Int) {
        if let onApplySmartListToTileAt {
            onApplySmartListToTileAt(id, tileIndex)
        } else {
            onApplySmartListToTile?(id)
        }
    }

    private func applySimpleList(_ id: UUID, toTileAt tileIndex: Int) {
        if let onApplySimpleListToTileAt {
            onApplySimpleListToTileAt(id, tileIndex)
        } else {
            onApplySimpleListToTile?(id)
        }
    }

    private func handleVideoTap(_ video: VideoItem) {
        if isMultiSelectEnabled {
            if selectedVideoIds.contains(video.fileId) {
                selectedVideoIds.remove(video.fileId)
            } else {
                selectedVideoIds.insert(video.fileId)
            }
        } else {
            library.saveFiltersIfNeeded()
            onVideoSelected?(video)
            isPresented = false
        }
    }

    private func toggleMultiSelect() {
        isMultiSelectEnabled.toggle()
        if !isMultiSelectEnabled {
            clearSelection()
        }
    }

    private func clearSelection() {
        selectedVideoIds.removeAll()
    }

    // MARK: - Delete Handlers

    private func handleDeleteTag(_ id: UUID) async throws {
        guard let serverURL = serverURL else {
            throw APIError.invalidURL
        }
        try await contentLibraryService.deleteTag(id: id, serverURL: serverURL)
        // The server removes the tag from every smart list's criteria
        // (contract §2): reload them instead of patching locally.
        if let lists = try? await smartListService.fetchSmartLists(from: serverURL) {
            library.smartLists = lists
        }
    }

    private func handleDeleteSmartList(_ id: UUID) async throws {
        guard let serverURL = serverURL else {
            throw APIError.invalidURL
        }
        try await smartListService.deleteSmartList(id: id, serverURL: serverURL)
    }

    private func handleDeleteSimpleList(_ id: UUID) async throws {
        guard let serverURL = serverURL else {
            throw APIError.invalidURL
        }
        try await simpleListService.deleteSimpleList(id: id, serverURL: serverURL)
    }

    private func handleCatalogRefresh() async {
        await library.refreshCatalog { version in
            guard catalogStatusManager?.configuredServerURL == serverURL else { return }
            await catalogStatusManager?.markRefreshed(newVersion: version)
        }
    }

    // MARK: - Bulk Operations

    private func applyTagsToSelection() async {
        guard let serverURL = serverURL else { return }

        let fileIds = Array(selectedVideoIds)
        let tagIds = Array(selectedTagIds)
        guard !fileIds.isEmpty, !tagIds.isEmpty else { return }

        do {
            // Additive: existing tags (and their per-tag ratings) are kept.
            try await contentLibraryService.applyTagChanges(
                toFileIds: fileIds,
                addTagIds: tagIds,
                serverURL: serverURL
            )
            AppLogger.video.info("Applied tags to \(fileIds.count) videos")
            selectedTagIds.removeAll()
            library.scheduleRefresh()
        } catch {
            AppLogger.video.error("Failed to apply tags: \(error.localizedDescription)")
            bulkErrorMessage = String(localized: "Couldn't apply the tags: \(error.localizedDescription)")
        }
    }

    private func applyRatingToSelection() async {
        guard let serverURL = serverURL else { return }

        let videoIds = Array(selectedVideoIds)

        do {
            try await contentLibraryService.setRatingBulk(
                forVideoIds: videoIds,
                rating: bulkRating,
                serverURL: serverURL
            )

            for videoId in videoIds {
                library.videoRatings[videoId] = bulkRating
            }

            AppLogger.video.info("Set rating \(bulkRating) for \(videoIds.count) videos")
        } catch {
            AppLogger.video.error("Failed to set rating: \(error.localizedDescription)")
            bulkErrorMessage = String(localized: "Couldn't set the rating on every video: \(error.localizedDescription)")
            // Some videos may have been updated before the failure: reload
            // the truth instead of guessing.
            library.scheduleRefresh()
        }
    }
}

// MARK: - Tag Filter Picker View

/// A picker for selecting tags to filter by, with optional per-tag rating filters.
struct TagFilterPickerView: View {
    let availableTags: [TagInfo]
    @Binding var selectedFilters: [TagFilter]
    let onApply: () -> Void
    let onDismiss: () -> Void

    // Use array-based state to avoid SwiftUI dictionary mutation issues
    @State private var localFilters: [TagFilter]

    init(
        availableTags: [TagInfo],
        selectedFilters: Binding<[TagFilter]>,
        onApply: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.availableTags = availableTags
        self._selectedFilters = selectedFilters
        self.onApply = onApply
        self.onDismiss = onDismiss
        // Initialize local state from existing filters
        self._localFilters = State(initialValue: selectedFilters.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            tagFilterContent
                .navigationTitle("Filter by Tags")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onDismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            selectedFilters = localFilters
                            onApply()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var tagFilterContent: some View {
        if availableTags.isEmpty {
            ContentUnavailableView(
                "No Tags Available",
                systemImage: "tag.slash",
                description: Text("Create tags to filter videos.")
            )
        } else {
            List {
                ForEach(availableTags) { tag in
                    TagFilterRow(
                        tag: tag,
                        isSelected: isTagSelected(tag.id),
                        minRating: getMinRating(for: tag.id),
                        maxRating: getMaxRating(for: tag.id),
                        onToggle: { toggleTag(tag) },
                        onMinRatingChange: { newMin in setMinRating(newMin, for: tag.id) },
                        onMaxRatingChange: { newMax in setMaxRating(newMax, for: tag.id) }
                    )
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - State Helpers

    private func isTagSelected(_ tagId: UUID) -> Bool {
        localFilters.contains { $0.tag.id == tagId }
    }

    private func getMinRating(for tagId: UUID) -> Int? {
        localFilters.first { $0.tag.id == tagId }?.minRating
    }

    private func getMaxRating(for tagId: UUID) -> Int? {
        localFilters.first { $0.tag.id == tagId }?.maxRating
    }

    private func toggleTag(_ tag: TagInfo) {
        if let index = localFilters.firstIndex(where: { $0.tag.id == tag.id }) {
            localFilters.remove(at: index)
        } else {
            localFilters.append(TagFilter(tag: tag))
        }
    }

    private func setMinRating(_ rating: Int?, for tagId: UUID) {
        if let index = localFilters.firstIndex(where: { $0.tag.id == tagId }) {
            localFilters[index].minRating = rating
        }
    }

    private func setMaxRating(_ rating: Int?, for tagId: UUID) {
        if let index = localFilters.firstIndex(where: { $0.tag.id == tagId }) {
            localFilters[index].maxRating = rating
        }
    }
}

/// Individual row in the tag filter picker showing tag name, selection state, and optional rating filters.
private struct TagFilterRow: View {
    let tag: TagInfo
    let isSelected: Bool
    let minRating: Int?
    let maxRating: Int?
    let onToggle: () -> Void
    let onMinRatingChange: (Int?) -> Void
    let onMaxRatingChange: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row with tag selection
            Button(action: onToggle) {
                HStack {
                    Circle()
                        .fill(tag.swiftUIColor)
                        .frame(width: 16, height: 16)

                    Text(tag.name)
                        .foregroundStyle(.primary)

                    if tag.ratingEnabled {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)

            // Rating filter controls (only show when selected and tag has ratingEnabled)
            if isSelected && tag.ratingEnabled {
                TagRatingFilterControls(
                    minRating: minRating,
                    maxRating: maxRating,
                    onMinRatingChange: onMinRatingChange,
                    onMaxRatingChange: onMaxRatingChange
                )
                .padding(.top, 12)
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Compact rating filter controls for per-tag rating ranges.
private struct TagRatingFilterControls: View {
    let minRating: Int?
    let maxRating: Int?
    let onMinRatingChange: (Int?) -> Void
    let onMaxRatingChange: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rating Filter")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                // Min rating picker
                HStack(spacing: 4) {
                    Text("Min:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { minRating ?? -1 },
                        set: { onMinRatingChange($0 == -1 ? nil : $0) }
                    )) {
                        Text("Any").tag(-1)
                        ForEach(0...10, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                // Max rating picker
                HStack(spacing: 4) {
                    Text("Max:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { maxRating ?? -1 },
                        set: { onMaxRatingChange($0 == -1 ? nil : $0) }
                    )) {
                        Text("Any").tag(-1)
                        ForEach(0...10, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }
}

// MARK: - Rating Filter Picker View

/// A picker for setting rating filter range.
struct RatingFilterPickerView: View {
    @Binding var minRating: Int
    @Binding var maxRating: Int
    let onApply: () -> Void
    let onDismiss: () -> Void

    @State private var localMin: Int
    @State private var localMax: Int

    init(
        minRating: Binding<Int>,
        maxRating: Binding<Int>,
        onApply: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self._minRating = minRating
        self._maxRating = maxRating
        self.onApply = onApply
        self.onDismiss = onDismiss
        self._localMin = State(initialValue: minRating.wrappedValue)
        self._localMax = State(initialValue: maxRating.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Minimum Rating: \(localMin)")
                            .font(.subheadline)
                        Slider(value: Binding(
                            get: { Double(localMin) },
                            set: { localMin = Int($0) }
                        ), in: 0...10, step: 1)

                        Text("Maximum Rating: \(localMax)")
                            .font(.subheadline)
                        Slider(value: Binding(
                            get: { Double(localMax) },
                            set: { localMax = Int($0) }
                        ), in: 0...10, step: 1)
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    Button("Clear Rating Filter") {
                        localMin = 0
                        localMax = 10
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Filter by Rating")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        minRating = localMin
                        maxRating = localMax
                        onApply()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Source Directory Picker View

/// A picker for selecting source directory to filter by.
struct SourceDirectoryPickerView: View {
    let directories: [SourceDirectoryDTO]
    @Binding var selectedDirectoryId: String?
    let onApply: () -> Void
    let onDismiss: () -> Void

    @State private var localSelection: String?

    init(
        directories: [SourceDirectoryDTO],
        selectedDirectoryId: Binding<String?>,
        onApply: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.directories = directories
        self._selectedDirectoryId = selectedDirectoryId
        self.onApply = onApply
        self.onDismiss = onDismiss
        self._localSelection = State(initialValue: selectedDirectoryId.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            directoryPickerContent
                .navigationTitle("Filter by Directory")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onDismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            selectedDirectoryId = localSelection
                            onApply()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var directoryPickerContent: some View {
        if directories.isEmpty {
            ContentUnavailableView(
                "No Source Directories",
                systemImage: "folder.badge.questionmark",
                description: Text("No source directories have been configured.")
            )
        } else {
            List {
                // All directories option
                Button {
                    localSelection = nil
                } label: {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)

                        Text("All Directories")
                            .foregroundStyle(.primary)

                        Spacer()

                        if localSelection == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)

                ForEach(directories) { directory in
                    Button {
                        localSelection = directory.id
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)

                            Text(directory.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            if localSelection == directory.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

// MARK: - Previews

#Preview("Content Tab") {
    struct PreviewWrapper: View {
        @State private var isPresented = true

        var body: some View {
            Color.gray.opacity(0.3)
                .sheet(isPresented: $isPresented) {
                    UnifiedContentLibraryView(
                        isPresented: $isPresented,
                        serverURL: URL(string: "http://localhost:8080"),
                        initialTab: .content,
                        onVideoSelected: { video in
                            print("Selected: \(video.filename)")
                        }
                    )
                }
        }
    }

    return PreviewWrapper()
}

#Preview("Tags Tab") {
    struct PreviewWrapper: View {
        @State private var isPresented = true

        var body: some View {
            Color.gray.opacity(0.3)
                .sheet(isPresented: $isPresented) {
                    UnifiedContentLibraryView(
                        isPresented: $isPresented,
                        serverURL: URL(string: "http://localhost:8080"),
                        initialTab: .tags,
                        currentVideoId: "test-video-id",
                        appliedTagIds: []
                    )
                }
        }
    }

    return PreviewWrapper()
}

#Preview("Smart Lists Tab") {
    struct PreviewWrapper: View {
        @State private var isPresented = true

        var body: some View {
            Color.gray.opacity(0.3)
                .sheet(isPresented: $isPresented) {
                    UnifiedContentLibraryView(
                        isPresented: $isPresented,
                        serverURL: URL(string: "http://localhost:8080"),
                        initialTab: .smartLists,
                        tiles: [Tile(index: 0), Tile(index: 1)]
                    )
                }
        }
    }

    return PreviewWrapper()
}

#Preview("Audio Tab") {
    struct PreviewWrapper: View {
        @State private var isPresented = true

        var body: some View {
            Color.gray.opacity(0.3)
                .sheet(isPresented: $isPresented) {
                    UnifiedContentLibraryView(
                        isPresented: $isPresented,
                        serverURL: URL(string: "http://localhost:8080"),
                        initialTab: .audio
                    )
                }
        }
    }

    return PreviewWrapper()
}
