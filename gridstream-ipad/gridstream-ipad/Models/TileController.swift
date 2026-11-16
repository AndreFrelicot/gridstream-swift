//
//  TileController.swift
//  gridstream-ipad
//
//  Server metadata for the video a tile shows: rating and tag ratings, tags,
//  time ranges, annotations, captures and list badges. Shared by the grid
//  tile and the fullscreen view so both load, save and guard it the same way.
//

import Foundation
import GridStreamAPI
import OSLog
import SwiftUI

/// What a tile's server metadata depends on besides the video: the server,
/// and the session token while requests are authorized (nil otherwise).
struct MetadataReloadKey: Equatable {
    let serverURL: URL?
    let authorizedTokenRevision: Int?
}

@MainActor
@Observable
final class TileController {

    // MARK: - Displayed Video

    /// The video the tile shows. Every load re-checks it after its await, so
    /// a response for a video the tile has since left is dropped.
    private(set) var displayedVideoId: String?
    /// The server the displayed video streams from.
    private(set) var serverURL: URL?

    // MARK: - Rating And Tags

    /// Read and written by the rating overlay through a binding.
    var ratingInfo = VideoRatingInfo(globalRating: 0, tagRatings: [:])
    /// The ratings as last loaded from or saved to the server. A failed save
    /// rolls back to these, not to the value `ratingInfo` held when the change
    /// handler ran: the hearts write the new rating through the binding
    /// before they call the handler.
    @ObservationIgnored private var savedRatingInfo = VideoRatingInfo()
    /// Bumped by every rating picked on the tile. A load that started before
    /// a pick answers with the server's state from before that save, so it
    /// leaves the ratings alone.
    @ObservationIgnored private var ratingEdits = 0
    private(set) var videoTags: [TagInfo] = []
    /// True for a moment after a rating save failed.
    private(set) var ratingSaveFailed = false
    private(set) var playCount: Int
    private(set) var viewTime: Int

    // MARK: - Lists

    private(set) var smartLists: [SmartListInfo] = []
    private(set) var simpleLists: [SimpleListDTO] = []
    private(set) var smartListVideoCount: Int?

    // MARK: - Time Of Interest

    private(set) var timeRanges: [TimeRangeDTO] = []
    var pendingToIStart: Double?
    var editingToIRangeId: UUID?

    // MARK: - Annotations

    let annotationManager: AnnotationManager

    // MARK: - Captures

    private(set) var captures: [FrameCaptureDTO] = []
    private(set) var isCapturingFrame = false
    private(set) var frameCaptureSuccess = false
    private(set) var frameCaptureError = false
    private(set) var showCaptureFlash = false

    // MARK: - Services

    @ObservationIgnored private let contentLibraryService: ContentLibraryService
    @ObservationIgnored private let smartListService: SmartListService
    @ObservationIgnored private let simpleListService: SimpleListService
    @ObservationIgnored private let tileSmartListService: TileSmartListService
    @ObservationIgnored private let timeRangeService: TimeRangeService
    @ObservationIgnored private let videoAPIService: VideoAPIService
    @ObservationIgnored private let membershipStore: SmartListMembershipStore

    init(
        playCount: Int = 0,
        viewTime: Int = 0,
        session: ServerSessionManager? = nil,
        membershipStore: SmartListMembershipStore? = nil
    ) {
        self.playCount = playCount
        self.viewTime = viewTime
        let contentLibraryService = ContentLibraryService(sessionManager: session)
        let smartListService = SmartListService(sessionManager: session)
        self.contentLibraryService = contentLibraryService
        self.smartListService = smartListService
        self.simpleListService = SimpleListService(sessionManager: session)
        self.tileSmartListService = TileSmartListService(
            contentLibraryService: contentLibraryService,
            smartListService: smartListService
        )
        self.timeRangeService = TimeRangeService(sessionManager: session)
        self.videoAPIService = VideoAPIService(sessionManager: session)
        self.annotationManager = AnnotationManager(store: AnnotationAPIService(sessionManager: session))
        self.membershipStore = membershipStore ?? .shared
    }

    // Explicit teardown avoids the isolated-deinit back-deploy shim: a tile
    // view makes a controller each time SwiftUI builds it and keeps only the
    // first, so the others are released during a view update, outside any
    // Swift task.
    deinit {}

    /// Points the controller at the video the tile shows now. Another video
    /// also clears the time-range editing state and leaves annotation mode.
    func show(videoId: String?, serverURL: URL?) {
        let isNewVideo = videoId != displayedVideoId
        displayedVideoId = videoId
        self.serverURL = serverURL
        guard isNewVideo else { return }
        // The previous video's ratings must not show on this one: tapping the
        // heart that matches them would toggle this video's rating to 0.
        ratingInfo = VideoRatingInfo()
        savedRatingInfo = ratingInfo
        videoTags = []
        pendingToIStart = nil
        editingToIRangeId = nil
        if annotationManager.isAnnotationMode {
            annotationManager.setAnnotationMode(false)
        }
    }

    private func isShowing(_ videoId: String, on serverURL: URL) -> Bool {
        displayedVideoId == videoId && self.serverURL == serverURL
    }

    // MARK: - Rating

    /// Loads the rating, tag ratings, tags and play stats of the video.
    @discardableResult
    func loadRating() -> Task<Void, Never>? {
        guard let videoId = displayedVideoId, let serverURL else { return nil }
        let editsAtStart = ratingEdits
        return Task {
            do {
                let videoInfo = try await contentLibraryService.fetchVideoInfo(forFileId: videoId, serverURL: serverURL)
                guard isShowing(videoId, on: serverURL) else { return }
                guard let videoInfo else {
                    AppLogger.playback.warning("loadRating: no video info for \(videoId)")
                    videoTags = []
                    return
                }
                playCount = videoInfo.playCount
                viewTime = videoInfo.totalViewTime
                let (tags, tagRatings) = TagInfo.fromWithRatings(videoInfo.tags)
                videoTags = tags
                guard ratingEdits == editsAtStart else { return }
                ratingInfo.globalRating = videoInfo.rating
                ratingInfo.tagRatings = tagRatings
                savedRatingInfo = ratingInfo
            } catch {
                AppLogger.playback.error("loadRating failed: \(error.localizedDescription)")
            }
        }
    }

    /// Shows `newRating` at once and saves it. A failed save rolls back to
    /// the last saved rating, unless the video changed or another rating was
    /// picked meanwhile.
    @discardableResult
    func setGlobalRating(_ newRating: Int) -> Task<Void, Never>? {
        guard let videoId = displayedVideoId, let serverURL else { return nil }
        ratingEdits += 1
        ratingInfo.globalRating = newRating

        return Task {
            do {
                try await contentLibraryService.setRating(forVideoId: videoId, rating: newRating, serverURL: serverURL)
                if displayedVideoId == videoId {
                    savedRatingInfo.globalRating = newRating
                }
                // Rating can change membership of rating-based smart lists.
                await membershipStore.load(from: serverURL, force: true)
            } catch {
                AppLogger.video.error("Failed to set rating: \(error.localizedDescription)")
                guard displayedVideoId == videoId else { return }
                if ratingInfo.globalRating == newRating {
                    ratingInfo.globalRating = savedRatingInfo.globalRating
                }
                flashRatingSaveError()
            }
        }
    }

    /// Like `setGlobalRating`, for one tag's rating on the video.
    @discardableResult
    func setTagRating(_ tagId: UUID, _ newRating: Int) -> Task<Void, Never>? {
        guard let videoId = displayedVideoId, let serverURL else { return nil }
        ratingEdits += 1
        ratingInfo.tagRatings[tagId] = newRating

        return Task {
            do {
                try await contentLibraryService.setTagRating(
                    forVideoId: videoId, tagId: tagId, rating: newRating, serverURL: serverURL
                )
                if displayedVideoId == videoId {
                    savedRatingInfo.tagRatings[tagId] = newRating
                }
                // Tag ratings can change membership of tag+rating smart lists.
                await membershipStore.load(from: serverURL, force: true)
            } catch {
                AppLogger.video.error("Failed to set tag rating: \(error.localizedDescription)")
                guard displayedVideoId == videoId else { return }
                if ratingInfo.tagRatings[tagId] == newRating {
                    ratingInfo.tagRatings[tagId] = savedRatingInfo.tagRatings[tagId]
                }
                flashRatingSaveError()
            }
        }
    }

    /// Shows the "rating not saved" badge for a moment.
    private func flashRatingSaveError() {
        withAnimation { ratingSaveFailed = true }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { self?.ratingSaveFailed = false }
        }
    }

    /// A tag was attached to or detached from the video elsewhere: show the
    /// change at once, then refresh from the server.
    func toggleTag(_ tag: TagInfo) {
        if videoTags.contains(where: { $0.id == tag.id }) {
            videoTags.removeAll { $0.id == tag.id }
        } else {
            videoTags.append(tag)
        }
        loadRating()
    }

    // MARK: - Lists

    /// Loads the shared smart-list membership map (the store fetches once).
    func loadMemberships() {
        guard let serverURL else { return }
        Task { await membershipStore.load(from: serverURL) }
    }

    /// Smart lists the video belongs to (evaluated by the server).
    func memberSmartLists(of fileId: String?) -> [SmartListInfo] {
        guard let fileId else { return [] }
        let ids = Set(membershipStore.smartListIds(forFileId: fileId))
        guard !ids.isEmpty else { return [] }
        return smartLists.filter { ids.contains($0.id) }
    }

    /// Simple lists the video belongs to.
    func memberSimpleLists(of fileId: String?) -> [SimpleListDTO] {
        guard let fileId else { return [] }
        return simpleLists.filter { $0.videoIds.contains(fileId) }
    }

    /// Loads the smart and simple lists when they are missing or do not hold
    /// the tile's attached list, then the attached smart list's video count.
    @discardableResult
    func loadLists(smartListId: UUID?, simpleListId: UUID?, tileIndex: Int) -> Task<Void, Never>? {
        guard let serverURL else { return nil }
        return Task {
            if smartLists.isEmpty || (smartListId != nil && !smartLists.contains { $0.id == smartListId }) {
                do {
                    smartLists = try await smartListService.fetchSmartLists(from: serverURL)
                } catch {
                    AppLogger.video.error("Failed to load smart lists: \(error.localizedDescription)")
                }
            }

            if simpleLists.isEmpty || (simpleListId != nil && !simpleLists.contains { $0.id == simpleListId }) {
                do {
                    simpleLists = try await simpleListService.fetchSimpleLists(from: serverURL)
                } catch {
                    AppLogger.video.error("Failed to load simple lists: \(error.localizedDescription)")
                }
            }

            guard let smartListId else {
                smartListVideoCount = nil
                return
            }
            do {
                smartListVideoCount = try await tileSmartListService.fetchVideosForTile(
                    tileIndex: tileIndex,
                    smartListId: smartListId,
                    smartLists: smartLists,
                    serverURL: serverURL
                ).total
            } catch {
                AppLogger.video.error("Failed to load smart list video count: \(error.localizedDescription)")
                smartListVideoCount = nil
            }
        }
    }

    // MARK: - Time Ranges

    @discardableResult
    func loadTimeRanges() -> Task<Void, Never>? {
        guard let videoId = displayedVideoId, let serverURL else {
            timeRanges = []
            return nil
        }
        return Task {
            let ranges: [TimeRangeDTO]
            do {
                ranges = try await timeRangeService.fetchTimeRanges(forFileId: videoId, serverURL: serverURL)
            } catch {
                AppLogger.video.error("Failed to load time ranges: \(error.localizedDescription)")
                ranges = []
            }
            guard isShowing(videoId, on: serverURL) else { return }
            timeRanges = ranges
        }
    }

    @discardableResult
    func createTimeRange(start: Double, end: Double) -> Task<Void, Never>? {
        guard let videoId = displayedVideoId, let serverURL else { return nil }
        return Task {
            do {
                let range = try await timeRangeService.createTimeRange(
                    forFileId: videoId, startTime: start, endTime: end, label: nil, serverURL: serverURL
                )
                // The range belongs to the video it was created on; another
                // video may be showing by now.
                guard displayedVideoId == videoId else { return }
                timeRanges.append(range)
                timeRanges.sort { $0.startTime < $1.startTime }
                pendingToIStart = nil
            } catch {
                AppLogger.video.error("Failed to create time range: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func updateTimeRange(_ rangeId: UUID, start: Double, end: Double) -> Task<Void, Never>? {
        guard let videoId = displayedVideoId, let serverURL else { return nil }
        return Task {
            do {
                let updated = try await timeRangeService.updateTimeRange(
                    forFileId: videoId, rangeId: rangeId, startTime: start, endTime: end, serverURL: serverURL
                )
                guard displayedVideoId == videoId else { return }
                if let index = timeRanges.firstIndex(where: { $0.id == rangeId }) {
                    timeRanges[index] = updated
                }
                timeRanges.sort { $0.startTime < $1.startTime }
                pendingToIStart = nil
                // Edit mode stays on so the user sees the updated timecodes.
            } catch {
                AppLogger.video.error("Failed to update time range: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func deleteTimeRange(_ rangeId: UUID) -> Task<Void, Never>? {
        guard let videoId = displayedVideoId, let serverURL else { return nil }
        return Task {
            do {
                try await timeRangeService.deleteTimeRange(forFileId: videoId, rangeId: rangeId, serverURL: serverURL)
                guard displayedVideoId == videoId else { return }
                timeRanges.removeAll { $0.id == rangeId }
            } catch {
                AppLogger.video.error("Failed to delete time range: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Annotations

    /// Loads the video's annotations, then syncs the displayed frame with
    /// the player `player()` returns once they arrive.
    @discardableResult
    func loadAnnotations(syncingWith player: @escaping () -> VideoPlayerState?) -> Task<Void, Never>? {
        guard let videoId = displayedVideoId, let serverURL else { return nil }
        return Task {
            await annotationManager.loadAnnotations(forFileId: videoId, serverURL: serverURL)
            guard isShowing(videoId, on: serverURL), let player = player() else { return }
            annotationManager.setFrameRate(Double(player.videoFrameRate))
            annotationManager.loadCurrentFrame(of: player)
        }
    }

    // MARK: - Captures

    @discardableResult
    func loadCaptures() -> Task<Void, Never>? {
        guard let videoId = displayedVideoId, let serverURL else {
            captures = []
            return nil
        }
        return Task {
            let loaded: [FrameCaptureDTO]
            do {
                loaded = try await videoAPIService.fetchCaptures(fileId: videoId, serverURL: serverURL)
            } catch {
                AppLogger.video.error("Failed to load captures: \(error.localizedDescription)")
                loaded = []
            }
            guard isShowing(videoId, on: serverURL) else { return }
            captures = loaded
        }
    }

    @discardableResult
    func deleteCapture(_ captureId: String) -> Task<Void, Never>? {
        guard let serverURL else { return nil }
        return Task {
            do {
                try await videoAPIService.deleteCapture(captureId: captureId, serverURL: serverURL)
                captures.removeAll { $0.id == captureId }
            } catch {
                AppLogger.video.error("Failed to delete capture: \(error)")
            }
        }
    }

    /// Captures the frame at `timestamp`, flashes the shutter, then shows the
    /// success or error state on the capture button for a moment.
    @discardableResult
    func captureFrame(at timestamp: Double, onCaptured: (() -> Void)? = nil) -> Task<Void, Never>? {
        guard let fileId = displayedVideoId, let serverURL else { return nil }
        isCapturingFrame = true

        return Task {
            do {
                _ = try await videoAPIService.captureFrame(fileId: fileId, timestamp: timestamp, serverURL: serverURL)
                isCapturingFrame = false

                withAnimation(.easeIn(duration: 0.05)) { showCaptureFlash = true }
                try? await Task.sleep(nanoseconds: 100_000_000)
                withAnimation(.easeOut(duration: 0.3)) { showCaptureFlash = false }

                frameCaptureSuccess = true
                onCaptured?()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                frameCaptureSuccess = false
            } catch {
                isCapturingFrame = false
                frameCaptureError = true
                AppLogger.video.error("Frame capture failed: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                frameCaptureError = false
            }
        }
    }
}
