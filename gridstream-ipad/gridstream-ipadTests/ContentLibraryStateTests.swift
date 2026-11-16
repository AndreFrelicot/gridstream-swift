import GridStreamAPI
import XCTest
@testable import gridstream_ipad

@MainActor
final class ContentLibraryStateTests: XCTestCase {
    private let serverURL = URL(string: "http://library.test")!

    override func setUp() async throws {
        ContentLibraryFilterCache.shared.clear()
    }

    private func video(_ id: String) -> VideoItem {
        VideoItem(
            fileId: id, filename: "\(id).mp4", relativePath: "\(id).mp4",
            sourceDirectoryId: UUID(), duration: 10, width: 640, height: 360,
            codec: "h264", fileSize: 1_000, lastModified: Date()
        )
    }

    func testFailedVideoLoadDoesNotAcknowledgeCatalogRefresh() async {
        let state = ContentLibraryState(
            serverURL: serverURL,
            loadPage: { _, _, _, _, _ in throw URLError(.cannotConnectToHost) },
            loadMetadata: { _ in .init() },
            loadVersion: { _ in 42 }
        )
        var acknowledged: [Int64] = []
        await state.refreshCatalog { acknowledged.append($0) }
        XCTAssertTrue(acknowledged.isEmpty)
        XCTAssertNotNil(state.errorMessage)
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.isRefreshing)
    }

    func testFailedMetadataLoadDoesNotAcknowledgeCatalogRefresh() async {
        let state = ContentLibraryState(
            serverURL: serverURL,
            loadPage: { _, _, _, _, _ in ([], 0) },
            loadMetadata: { _ in throw URLError(.cannotConnectToHost) },
            loadVersion: { _ in 42 }
        )
        var acknowledged = false
        await state.refreshCatalog { _ in acknowledged = true }
        XCTAssertFalse(acknowledged)
        XCTAssertNotNil(state.errorMessage)
    }

    func testFailedVersionLoadDoesNotAcknowledgeCatalogRefresh() async {
        let state = ContentLibraryState(
            serverURL: serverURL,
            loadPage: { _, _, _, _, _ in ([], 0) },
            loadMetadata: { _ in .init() },
            loadVersion: { _ in throw URLError(.cannotConnectToHost) }
        )
        var acknowledged = false
        await state.refreshCatalog { _ in acknowledged = true }
        XCTAssertFalse(acknowledged)
        XCTAssertNotNil(state.errorMessage)
        XCTAssertFalse(state.isRefreshing)
    }

    func testSuccessfulRefreshAcknowledgesTheVersionReadBeforeLoading() async {
        let expected = video("fresh")
        let state = ContentLibraryState(
            serverURL: serverURL,
            loadPage: { _, _, _, _, _ in ([expected], 1) },
            loadMetadata: { _ in .init() },
            loadVersion: { _ in 42 }
        )
        var acknowledged: [Int64] = []
        await state.refreshCatalog { acknowledged.append($0) }
        XCTAssertEqual(acknowledged, [42])
        XCTAssertEqual(state.videos.map(\.fileId), ["fresh"])
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.isRefreshing)
    }

    func testOlderSearchCannotReplaceTheLatestResults() async {
        var pending: CheckedContinuation<ContentLibraryState.Page, Error>?
        let oldVideo = video("old")
        let newVideo = video("new")
        var requests = 0
        let state = ContentLibraryState(serverURL: serverURL, loadPage: { _, _, _, _, _ in
            requests += 1
            if requests == 1 {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return ([newVideo], 1)
        })
        let oldRequest = Task { await state.refreshVideos() }
        while pending == nil { await Task.yield() }
        state.filters.searchText = "new"
        let refreshed = await state.refreshVideos()
        XCTAssertTrue(refreshed)
        pending?.resume(returning: ([oldVideo], 1))
        let oldApplied = await oldRequest.value
        XCTAssertFalse(oldApplied)
        XCTAssertEqual(state.videos.map(\.fileId), ["new"])
        XCTAssertNil(state.errorMessage)
        XCTAssertFalse(state.isLoading)
    }

    func testFailedStaleRequestCannotOverwriteTheLatestSuccess() async {
        var pending: CheckedContinuation<ContentLibraryState.Page, Error>?
        let expected = video("new")
        var requests = 0
        let state = ContentLibraryState(serverURL: serverURL, loadPage: { _, _, _, _, _ in
            requests += 1
            if requests == 1 {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return ([expected], 1)
        })
        let oldRequest = Task { await state.refreshVideos() }
        while pending == nil { await Task.yield() }
        _ = await state.refreshVideos()
        pending?.resume(throwing: URLError(.timedOut))
        _ = await oldRequest.value
        XCTAssertEqual(state.videos.map(\.fileId), ["new"])
        XCTAssertNil(state.errorMessage)
        XCTAssertFalse(state.isLoading)
    }

    func testStaleCatalogLoadIsNotAcknowledged() async {
        var pending: CheckedContinuation<ContentLibraryState.Page, Error>?
        let expected = video("new")
        var requests = 0
        let state = ContentLibraryState(
            serverURL: serverURL,
            loadPage: { _, _, _, _, _ in
                requests += 1
                if requests == 1 {
                    return try await withCheckedThrowingContinuation { pending = $0 }
                }
                return ([expected], 1)
            },
            loadMetadata: { _ in .init() },
            loadVersion: { _ in 42 }
        )
        var acknowledged = false
        let refresh = Task { await state.refreshCatalog { _ in acknowledged = true } }
        while pending == nil { await Task.yield() }
        state.filters.searchText = "new"
        _ = await state.refreshVideos()
        pending?.resume(returning: ([], 0))
        await refresh.value
        XCTAssertFalse(acknowledged)
        XCTAssertEqual(state.videos.map(\.fileId), ["new"])
        XCTAssertFalse(state.isRefreshing)
    }

    func testFailedPageRetriesTheSameOffsetWithoutLosingVideos() async {
        let first = [video("a"), video("b")]
        let second = [video("c"), video("d")]
        var offsets: [Int] = []
        let state = ContentLibraryState(serverURL: serverURL, pageSize: 2, loadPage: { _, _, _, _, offset in
            offsets.append(offset)
            if offsets.count == 2 { throw URLError(.timedOut) }
            return (offset == 0 ? first : second, 4)
        })
        _ = await state.refreshVideos()
        await state.loadMoreVideos()
        XCTAssertEqual(state.videos.map(\.fileId), ["a", "b"])
        XCTAssertEqual(state.currentOffset, 2)
        XCTAssertNotNil(state.errorMessage)
        await state.loadMoreVideos()
        XCTAssertEqual(offsets, [0, 2, 2])
        XCTAssertEqual(state.videos.map(\.fileId), ["a", "b", "c", "d"])
        XCTAssertFalse(state.hasMoreVideos)
        XCTAssertNil(state.errorMessage)
    }

    func testSearchDoesNotDiscardInitialSmartListCounts() async {
        let list = SmartListInfo(name: "All", criteria: SmartListCriteria(conditions: []))
        var page: CheckedContinuation<ContentLibraryState.Page, Error>?
        let state = ContentLibraryState(serverURL: serverURL, loadPage: { _, filters, _, limit, _ in
            if limit == 0 { return ([], 23) }
            if filters.searchText.isEmpty {
                return try await withCheckedThrowingContinuation { page = $0 }
            }
            return ([], 0)
        }, loadMetadata: { _ in .init(smartLists: [list]) })
        let initial = Task { await state.loadInitialData() }
        while page == nil { await Task.yield() }
        state.filters.searchText = "new"
        _ = await state.refreshVideos()
        page?.resume(returning: ([], 0))
        _ = await initial.value
        XCTAssertEqual(state.smartListVideoCounts[list.id], 23)
    }

    func testServerChangeDropsOldMetadataAndPages() async {
        let newServer = URL(string: "http://second.test")!
        var metadata: CheckedContinuation<ContentLibraryState.Metadata, Error>?
        let oldServer = serverURL
        let state = ContentLibraryState(serverURL: oldServer, loadPage: { _, _, _, _, _ in ([], 0) }, loadMetadata: { url in
            if url == oldServer {
                return try await withCheckedThrowingContinuation { metadata = $0 }
            }
            return .init()
        })
        let old = Task { await state.loadInitialData() }
        while metadata == nil { await Task.yield() }
        state.configure(serverURL: newServer)
        _ = await state.loadInitialData()
        metadata?.resume(returning: .init(smartLists: [SmartListInfo(name: "Old", criteria: SmartListCriteria(conditions: []))]))
        _ = await old.value
        XCTAssertTrue(state.smartLists.isEmpty)
        XCTAssertFalse(state.isLoading)
    }

    func testEmptyPageStopsPagination() async {
        let expected = video("a")
        let state = ContentLibraryState(serverURL: serverURL, loadPage: { _, _, _, _, offset in
            (offset == 0 ? [expected] : [], 100)
        })
        _ = await state.refreshVideos()
        await state.loadMoreVideos()
        XCTAssertFalse(state.hasMoreVideos)
        XCTAssertEqual(state.videos.count, 1)
    }
}
