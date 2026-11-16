import Foundation
import GridStreamAPI
import Observation
import OSLog

@Observable
@MainActor
final class ContentLibraryState {
    typealias Page = (videos: [VideoItem], total: Int)
    typealias PageLoader = @MainActor (URL, ContentLibraryFilters, SmartListCriteria?, Int, Int) async throws -> Page
    typealias MetadataLoader = @MainActor (URL) async throws -> Metadata
    typealias VersionLoader = @MainActor (URL) async throws -> Int64

    struct Metadata {
        var tags: [TagInfo] = []
        var sourceDirectories: [SourceDirectoryDTO] = []
        var smartLists: [SmartListInfo] = []
        var simpleLists: [SimpleListDTO] = []
    }

    private(set) var videos: [VideoItem] = []
    var videoRatings: [String: Int] = [:]
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    var filters = ContentLibraryFilters() {
        didSet {
            if filters != oldValue { loadGeneration += 1 }
        }
    }
    var tags: [TagInfo] = []
    var smartLists: [SmartListInfo] = []
    var simpleLists: [SimpleListDTO] = []
    var sourceDirectories: [SourceDirectoryDTO] = []
    var selectedSmartListId: UUID?
    var selectedSimpleListId: UUID?
    var activeSmartListCriteria: SmartListCriteria? {
        didSet {
            if activeSmartListCriteria != oldValue { loadGeneration += 1 }
        }
    }
    private(set) var smartListVideoCounts: [UUID: Int] = [:]
    private(set) var totalVideoCount = 0
    private(set) var currentOffset = 0
    private var loadGeneration = 0
    private var metadataGeneration = 0
    private var catalogRefreshID: UUID?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let loadPage: PageLoader
    @ObservationIgnored private let loadMetadata: MetadataLoader
    @ObservationIgnored private let loadVersion: VersionLoader
    private var serverURL: URL?
    private let initialSmartListId: UUID?
    private let initialSimpleListId: UUID?
    private var didApplyInitialFilters = false
    private let pageSize: Int
    private let contentLibraryService = ContentLibraryService()
    private let simpleListService = SimpleListService()

    var hasMoreVideos: Bool { videos.count < totalVideoCount }

    init(
        serverURL: URL?,
        initialSmartListId: UUID? = nil,
        initialSimpleListId: UUID? = nil,
        pageSize: Int = 100,
        loadPage: PageLoader? = nil,
        loadMetadata: MetadataLoader? = nil,
        loadVersion: VersionLoader? = nil
    ) {
        self.serverURL = serverURL
        self.initialSmartListId = initialSmartListId
        self.initialSimpleListId = initialSimpleListId
        self.pageSize = pageSize
        self.loadPage = loadPage ?? { url, filters, criteria, limit, offset in
            let service = ContentLibraryService()
            if let criteria {
                return try await service.fetchVideosWithSmartListCriteria(from: url, criteria: criteria, limit: limit, offset: offset)
            }
            return try await service.fetchVideos(from: url, filters: filters, limit: limit, offset: offset)
        }
        self.loadMetadata = loadMetadata ?? { url in
            let content = ContentLibraryService()
            let smart = SmartListService()
            let simple = SimpleListService()
            async let tags = content.fetchTags(from: url)
            async let directories = content.fetchSourceDirectories(from: url)
            async let smartLists = smart.fetchSmartLists(from: url)
            let (fetchedTags, fetchedDirectories, fetchedSmartLists) = try await (tags, directories, smartLists)
            let simpleLists: [SimpleListDTO]
            do {
                simpleLists = try await simple.fetchSimpleLists(from: url)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                AppLogger.video.debug("Simple Lists not available: \(error.localizedDescription)")
                simpleLists = []
            }
            return Metadata(tags: fetchedTags, sourceDirectories: fetchedDirectories, smartLists: fetchedSmartLists, simpleLists: simpleLists)
        }
        self.loadVersion = loadVersion ?? { url in
            try await ContentLibraryService().fetchCatalogStatus(from: url)
        }
    }

    deinit {}

    func configure(serverURL: URL?) {
        guard self.serverURL != serverURL else { return }
        cancelRefresh()
        self.serverURL = serverURL
        catalogRefreshID = nil
        isRefreshing = false
        videos = []
        videoRatings = [:]
        totalVideoCount = 0
        currentOffset = 0
        tags = []
        sourceDirectories = []
        smartLists = []
        simpleLists = []
        smartListVideoCounts = [:]
        selectedSmartListId = nil
        selectedSimpleListId = nil
        activeSmartListCriteria = nil
        filters = ContentLibraryFilters()
        didApplyInitialFilters = false
        errorMessage = nil
    }

    @discardableResult
    func loadInitialData() async -> Bool {
        guard let serverURL else {
            errorMessage = String(localized: "Server not connected")
            isLoading = false
            return false
        }
        loadGeneration += 1
        metadataGeneration += 1
        let metadataRequest = metadataGeneration
        var generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let metadata = try await loadMetadata(serverURL)
            guard metadataRequest == metadataGeneration, self.serverURL == serverURL, !Task.isCancelled else { return false }
            tags = metadata.tags
            sourceDirectories = metadata.sourceDirectories
            smartLists = metadata.smartLists
            simpleLists = metadata.simpleLists
            applyInitialFilters()
            generation = loadGeneration
            async let counts: Void = fetchSmartListVideoCounts(metadataRequest: metadataRequest, from: serverURL)
            let result = try await loadPage(serverURL, filters, activeSmartListCriteria, pageSize, 0)
            guard isCurrent(generation) else {
                await counts
                return false
            }
            replaceVideos(with: result)
            await counts
            return isCurrent(generation)
        } catch {
            finishFailure(error, generation: generation)
            return false
        }
    }

    func refreshCatalog(markRefreshed: (Int64) async -> Void) async {
        guard !isRefreshing, let serverURL else { return }
        let refreshID = UUID()
        catalogRefreshID = refreshID
        isRefreshing = true
        defer {
            if catalogRefreshID == refreshID {
                catalogRefreshID = nil
                isRefreshing = false
            }
        }
        let generation = loadGeneration
        do {
            let version = try await loadVersion(serverURL)
            guard isCurrent(generation), await loadInitialData() else { return }
            await markRefreshed(version)
        } catch {
            if generation == loadGeneration { errorMessage = error.localizedDescription }
        }
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { await refreshVideos() }
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        metadataGeneration += 1
        loadGeneration += 1
        isLoading = false
    }

    @discardableResult
    func refreshVideos() async -> Bool {
        guard let serverURL else { return false }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let result = try await loadPage(serverURL, filters, activeSmartListCriteria, pageSize, 0)
            guard isCurrent(generation) else { return false }
            replaceVideos(with: result)
            return true
        } catch {
            finishFailure(error, generation: generation)
            return false
        }
    }

    func loadMoreVideos() async {
        guard let serverURL, !isLoading, hasMoreVideos else { return }
        isLoading = true
        errorMessage = nil
        let generation = loadGeneration
        let nextOffset = currentOffset
        do {
            let result = try await loadPage(serverURL, filters, activeSmartListCriteria, pageSize, nextOffset)
            guard isCurrent(generation) else { return }
            let existingIds = Set(videos.map(\.fileId))
            videos.append(contentsOf: result.videos.filter { !existingIds.contains($0.fileId) })
            currentOffset = nextOffset + result.videos.count
            totalVideoCount = result.videos.isEmpty ? videos.count : result.total
            videoRatings.merge(Self.ratings(for: result.videos)) { _, new in new }
            isLoading = false
        } catch {
            finishFailure(error, generation: generation)
        }
    }

    func refreshTags() async {
        guard let serverURL else { return }
        do {
            tags = try await contentLibraryService.fetchTags(from: serverURL)
        } catch {
            AppLogger.video.error("Failed to refresh tags: \(error.localizedDescription)")
        }
    }

    func selectSmartList(_ smartList: SmartListInfo) {
        selectedSimpleListId = nil
        selectedSmartListId = smartList.id
        activeSmartListCriteria = smartList.criteria
        filters = ContentLibraryFilters()
        scheduleRefresh()
    }

    func selectSimpleList(_ simpleList: SimpleListDTO) {
        selectedSmartListId = nil
        selectedSimpleListId = simpleList.id
        activeSmartListCriteria = nil
        loadGeneration += 1
        let generation = loadGeneration
        guard let serverURL else { return }
        Task {
            do {
                guard let fullList = try await simpleListService.fetchSimpleList(id: simpleList.id, from: serverURL),
                      isCurrent(generation), selectedSimpleListId == simpleList.id else { return }
                filters = ContentLibraryFilters(videoIds: fullList.videoIds)
                scheduleRefresh()
            } catch {
                finishFailure(error, generation: generation)
            }
        }
    }

    func saveFiltersIfNeeded() {
        if selectedSmartListId == nil && selectedSimpleListId == nil
            && initialSmartListId == nil && initialSimpleListId == nil {
            ContentLibraryFilterCache.shared.save(filters)
        }
    }

    private func applyInitialFilters() {
        guard !didApplyInitialFilters else { return }
        didApplyInitialFilters = true
        if let smartListId = initialSmartListId,
           let smartList = smartLists.first(where: { $0.id == smartListId }) {
            selectedSmartListId = smartListId
            activeSmartListCriteria = smartList.criteria
        } else if let simpleListId = initialSimpleListId,
                  let simpleList = simpleLists.first(where: { $0.id == simpleListId }) {
            selectedSimpleListId = simpleListId
            filters = ContentLibraryFilters(videoIds: simpleList.videoIds)
        } else if let cachedFilters = ContentLibraryFilterCache.shared.restore() {
            filters = cachedFilters
        }
    }

    private func fetchSmartListVideoCounts(metadataRequest: Int, from serverURL: URL) async {
        await withTaskGroup(of: (UUID, Int?).self) { group in
            let loader = loadPage
            for smartList in smartLists {
                group.addTask {
                    let total = try? await loader(serverURL, ContentLibraryFilters(), smartList.criteria, 0, 0).total
                    return (smartList.id, total)
                }
            }
            var counts: [UUID: Int] = [:]
            for await (id, count) in group {
                if let count { counts[id] = count }
            }
            if metadataRequest == metadataGeneration, self.serverURL == serverURL, !Task.isCancelled {
                smartListVideoCounts = counts
            }
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        guard generation == loadGeneration else { return false }
        if Task.isCancelled {
            isLoading = false
            return false
        }
        return true
    }

    private func replaceVideos(with result: Page) {
        videos = result.videos
        currentOffset = result.videos.count
        totalVideoCount = result.total
        videoRatings = Self.ratings(for: videos)
        isLoading = false
    }

    private func finishFailure(_ error: Error, generation: Int) {
        guard generation == loadGeneration else { return }
        isLoading = false
        if !Task.isCancelled, !(error is CancellationError) {
            errorMessage = error.localizedDescription
        }
    }

    private static func ratings(for videos: [VideoItem]) -> [String: Int] {
        Dictionary(videos.map { ($0.fileId, $0.rating) }, uniquingKeysWith: { _, last in last })
    }
}
