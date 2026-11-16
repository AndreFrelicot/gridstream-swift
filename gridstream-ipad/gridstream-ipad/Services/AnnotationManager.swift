import Foundation
import GridStreamAPI
import OSLog

/// Server calls the annotation manager depends on (injectable for tests).
@MainActor
protocol AnnotationStore: AnyObject {
    func fetchAnnotations(forFileId fileId: String, serverURL: URL) async throws -> [AnnotationDTO]
    func upsertAnnotation(
        forFileId fileId: String,
        frameTime: Double,
        frameRate: Double,
        strokesJSON: String,
        text: String?,
        serverURL: URL
    ) async throws -> AnnotationDTO
    func deleteAnnotation(forFileId fileId: String, annotationId: String, serverURL: URL) async throws
}

extension AnnotationAPIService: AnnotationStore {}

@Observable @MainActor
final class AnnotationManager {
    /// The video (and its frame rate) a drawing belongs to. Captured when the
    /// canvas loads a frame, so a debounced save that fires after the user has
    /// switched videos still goes to the video it was drawn on.
    struct Target: Equatable {
        let fileId: String
        let serverURL: URL
        let frameRate: Double

        /// Same video, whatever frame rate was known when each was captured.
        func isSameVideo(as other: Target?) -> Bool {
            fileId == other?.fileId && serverURL == other?.serverURL
        }
    }

    /// Annotations keyed by integer frame number — eliminates floating-point key mismatch
    private(set) var annotations: [Int: AnnotationDTO] = [:]
    private(set) var isAnnotationMode: Bool = false
    private(set) var currentFrameStrokes: [StrokeData] = []
    var currentFrameText: String = ""
    var isTextInputVisible: Bool = false

    /// Frame number that `currentFrameStrokes` / `currentFrameText` belong to.
    /// nil when nothing is loaded. Everything that writes displayed content
    /// checks against it, so a debounced save or a late server response cannot
    /// paint a frame the user has already left.
    private(set) var currentFrameNumber: Int?

    private let apiService: AnnotationStore
    private var currentVideoFileId: String?
    private var currentServerURL: URL?
    private var currentFrameRate: Double = 24.0
    private var textSaveTask: Task<Void, Never>?
    private var pendingTextSaveFrameNumber: Int?
    private var pendingTextByFrameNumber: [Int: String] = [:]
    /// Strokes sent to the server and not confirmed yet, by frame number.
    /// Loading a frame prefers them over `annotations`, which still holds the
    /// previous version until the save returns: without them, leaving pencil
    /// mode right after erasing a drawing showed the old drawing again, and it
    /// stayed on screen once the save had landed.
    private var pendingStrokesByFrameNumber: [Int: (saveId: UUID, strokes: [StrokeData])] = [:]

    init(store: AnnotationStore? = nil) {
        self.apiService = store ?? AnnotationAPIService()
    }

    // Explicit teardown avoids the isolated-deinit back-deploy shim when
    // SwiftUI releases the tile controller outside a Swift task.
    deinit {}

    /// The loaded video, for a canvas to remember with the frame it shows.
    /// `frameRate` is the player's rate at the time the canvas loads; until the
    /// player knows it, the rate the annotations were loaded with is used.
    func target(frameRate: Double) -> Target? {
        guard let fileId = currentVideoFileId, let serverURL = currentServerURL else { return nil }
        return Target(fileId: fileId, serverURL: serverURL, frameRate: frameRate > 0 ? frameRate : currentFrameRate)
    }

    private func isCurrentVideo(fileId: String, serverURL: URL) -> Bool {
        currentVideoFileId == fileId && currentServerURL == serverURL
    }

    /// Time of the frame whose content is displayed, nil when none is loaded.
    /// The pencil canvas edits this frame, not the player's live time: in
    /// pencil mode the timeline is not followed, so the two can differ, and
    /// strokes saved to another frame than the displayed one would not show
    /// once pencil mode is left.
    var displayedFrameTime: Double? {
        guard let currentFrameNumber, currentFrameRate > 0 else { return nil }
        return Double(currentFrameNumber) / currentFrameRate
    }

    /// Sorted frame times for UI display, derived from integer frame number keys
    var annotationTimes: [Double] {
        guard currentFrameRate > 0 else { return [] }
        return annotations.keys.sorted().map { Double($0) / currentFrameRate }
    }

    /// Convert time to integer frame number
    private func frameNumber(forTime time: Double) -> Int {
        Int(round(time * currentFrameRate))
    }

    private func resetCurrentFrameContent() {
        currentFrameNumber = nil
        currentFrameStrokes = []
        currentFrameText = ""
    }

    /// True when `frame` is the frame whose content is on screen. Content loaded
    /// for another frame must never be overwritten by a write meant for `frame`.
    private func isDisplayedFrame(_ frame: Int) -> Bool {
        currentFrameNumber == nil || currentFrameNumber == frame
    }

    private func cancelPendingTextSave() {
        textSaveTask?.cancel()
        textSaveTask = nil
        pendingTextSaveFrameNumber = nil
    }

    func loadAnnotations(forFileId fileId: String, serverURL: URL) async {
        cancelPendingTextSave()
        currentVideoFileId = fileId
        currentServerURL = serverURL
        isTextInputVisible = false
        pendingTextByFrameNumber = [:]
        pendingStrokesByFrameNumber = [:]
        resetCurrentFrameContent()

        do {
            let fetched = try await apiService.fetchAnnotations(forFileId: fileId, serverURL: serverURL)
            guard currentVideoFileId == fileId, currentServerURL == serverURL else {
                return
            }

            // Use the annotation's own frameRate for frame number computation,
            // not currentFrameRate which may still be at the default (24.0).
            // Each annotation stores the frameRate it was saved with.
            if let first = fetched.first, first.frameRate > 0 {
                currentFrameRate = first.frameRate
            }

            var map: [Int: AnnotationDTO] = [:]
            for annotation in fetched {
                let fn = frameNumber(forTime: annotation.frameTime)
                map[fn] = annotation
                AppLogger.video.debug("Load annotation: apiTime=\(annotation.frameTime), frame#=\(fn), frameRate=\(self.currentFrameRate)")
            }
            annotations = map
            // Force the next sync to re-read content: the frame marker may have
            // been set from the empty map while the fetch was in flight.
            currentFrameNumber = nil
            AppLogger.video.info("Loaded \(fetched.count) annotations for video \(fileId), frameRate=\(self.currentFrameRate), frame keys: \(map.keys.sorted())")
        } catch {
            annotations = [:]
            resetCurrentFrameContent()
            AppLogger.video.error("Failed to load annotations: \(error.localizedDescription)")
        }
    }

    func toggleAnnotationMode() {
        setAnnotationMode(!isAnnotationMode)
    }

    /// Pencil mode is the only state in which a drawing is on screen: the
    /// canvas exists in pencil mode only, and nothing else paints strokes.
    func setAnnotationMode(_ enabled: Bool) {
        isAnnotationMode = enabled
        if !enabled {
            isTextInputVisible = false
        }
        AppLogger.video.info("Pencil mode \(enabled ? "on" : "off", privacy: .public): video \(self.currentVideoFileId ?? "none", privacy: .public)")
    }

    /// Leaves pencil mode when playback resumes. An annotation belongs to a
    /// single frame, so it must not stay painted over a moving picture.
    /// Content is re-synced to the frame the player is on; from there the
    /// timeline sync takes over as playback advances.
    func exitAnnotationModeForPlayback(of player: VideoPlayerState) {
        guard isAnnotationMode else { return }
        setAnnotationMode(false)
        loadCurrentFrame(of: player)
    }

    /// Toggles pencil mode and re-syncs the displayed content to the player's
    /// own frame. Entering pauses first, so the frame drawn on is the one the
    /// player stops on, and the canvas opens with that frame's drawing.
    func toggleAnnotationMode(of player: VideoPlayerState) {
        if !isAnnotationMode {
            player.pause()
        }
        toggleAnnotationMode()
        loadCurrentFrame(of: player)
    }

    /// Saves the strokes drawn on `frameTime` of `target`'s video. Local state
    /// is only touched while that video is still the loaded one, checked again
    /// after every await: a save that lands after a video switch must not show
    /// up in (or overwrite) the new video's annotations.
    func saveAnnotation(frameTime: Double, strokes: [StrokeData], target: Target) async {
        let fn = Int(round(frameTime * target.frameRate))
        let snappedTime = Double(fn) / target.frameRate

        AppLogger.video.info("Save annotation: inputTime=\(frameTime), frame#=\(fn), snappedTime=\(snappedTime)")

        let text: String?
        let saveId = UUID()
        if isCurrentVideo(fileId: target.fileId, serverURL: target.serverURL) {
            currentFrameRate = target.frameRate
            cancelPendingTextSave()
            pendingStrokesByFrameNumber[fn] = (saveId, strokes)
            if isDisplayedFrame(fn) {
                currentFrameStrokes = strokes
            }
            text = isDisplayedFrame(fn)
                ? (currentFrameText.isEmpty ? nil : currentFrameText)
                : (pendingTextByFrameNumber[fn] ?? annotations[fn]?.text)
        } else {
            // The user has moved on to another video. Its text for this frame
            // is no longer in memory; read it back so the upsert keeps it.
            do {
                let existing = try await apiService.fetchAnnotations(forFileId: target.fileId, serverURL: target.serverURL)
                text = existing.first { Int(round($0.frameTime * target.frameRate)) == fn }?.text
            } catch {
                AppLogger.video.error("Failed to read annotation text before saving strokes: \(error.localizedDescription)")
                return
            }
        }

        do {
            let strokesData = try JSONEncoder().encode(strokes)
            let strokesString = String(data: strokesData, encoding: .utf8) ?? "[]"

            let saved = try await apiService.upsertAnnotation(
                forFileId: target.fileId,
                frameTime: snappedTime,
                frameRate: target.frameRate,
                strokesJSON: strokesString,
                text: text,
                serverURL: target.serverURL
            )
            guard isCurrentVideo(fileId: target.fileId, serverURL: target.serverURL) else {
                AppLogger.video.info("Saved annotation at frame#=\(fn) of \(target.fileId), no longer displayed")
                return
            }
            annotations[fn] = saved
            // A newer save of this frame keeps its own pending strokes.
            if pendingStrokesByFrameNumber[fn]?.saveId == saveId {
                pendingStrokesByFrameNumber.removeValue(forKey: fn)
            }
            AppLogger.video.info("Saved annotation at frame#=\(fn) (time=\(snappedTime))")
        } catch {
            // Kept pending: the frame shows what was drawn, not the last
            // version the server has.
            AppLogger.video.error("Failed to save annotation: \(error.localizedDescription)")
        }
    }

    func updateCurrentFrameText(forTime time: Double) {
        let fn = frameNumber(forTime: time)
        if let pendingText = pendingTextByFrameNumber[fn] {
            currentFrameText = pendingText
            AppLogger.video.debug("Loaded pending text for frame#=\(fn) (time=\(time))")
            return
        }
        if let annotation = annotations[fn] {
            currentFrameText = annotation.text ?? ""
            AppLogger.video.debug("Loaded text for frame#=\(fn) (time=\(time))")
        } else if !currentFrameText.isEmpty {
            currentFrameText = ""
        }
    }

    func setTextInputVisible(_ visible: Bool) {
        isTextInputVisible = visible
    }

    func saveTextAnnotation(text: String, frameTime: Double, frameRate: Double) async {
        currentFrameRate = frameRate
        let fn = frameNumber(forTime: frameTime)
        if isDisplayedFrame(fn) {
            currentFrameText = text
        }
        guard let fileId = currentVideoFileId, let serverURL = currentServerURL else { return }

        let snappedTime = Double(fn) / frameRate

        cancelPendingTextSave()
        pendingTextByFrameNumber[fn] = text
        pendingTextSaveFrameNumber = fn
        textSaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            // A video switch cancels this task, but re-check: the frame
            // number below belongs to this video only.
            guard isCurrentVideo(fileId: fileId, serverURL: serverURL) else { return }

            do {
                let existingAnnotation = annotations[fn]
                let strokesString = existingAnnotation?.strokesJSON ?? "[]"
                let textValue = text.isEmpty ? nil : text
                let saved = try await apiService.upsertAnnotation(
                    forFileId: fileId,
                    frameTime: snappedTime,
                    frameRate: frameRate,
                    strokesJSON: strokesString,
                    text: textValue,
                    serverURL: serverURL
                )
                guard isCurrentVideo(fileId: fileId, serverURL: serverURL) else { return }
                annotations[fn] = saved
                pendingTextByFrameNumber.removeValue(forKey: fn)
                if pendingTextSaveFrameNumber == fn {
                    textSaveTask = nil
                    pendingTextSaveFrameNumber = nil
                }
                AppLogger.video.info("Saved text annotation at frame#=\(fn)")
            } catch {
                guard isCurrentVideo(fileId: fileId, serverURL: serverURL) else { return }
                pendingTextByFrameNumber[fn] = text
                if pendingTextSaveFrameNumber == fn {
                    textSaveTask = nil
                    pendingTextSaveFrameNumber = nil
                }
                AppLogger.video.error("Failed to save text annotation: \(error.localizedDescription)")
            }
        }
    }

    func deleteAnnotation(frameTime: Double) async {
        guard let fileId = currentVideoFileId, let serverURL = currentServerURL else { return }

        let fn = frameNumber(forTime: frameTime)
        AppLogger.video.info("Delete annotation: inputTime=\(frameTime), frame#=\(fn)")
        cancelPendingTextSave()

        guard let annotation = annotations[fn] else {
            AppLogger.video.warning("Delete: no annotation found for frame#=\(fn), keys=\(self.annotations.keys.sorted())")
            return
        }

        do {
            try await apiService.deleteAnnotation(
                forFileId: fileId,
                annotationId: annotation.id.uuidString,
                serverURL: serverURL
            )
            guard isCurrentVideo(fileId: fileId, serverURL: serverURL) else { return }
            annotations.removeValue(forKey: fn)
            pendingTextByFrameNumber.removeValue(forKey: fn)
            pendingStrokesByFrameNumber.removeValue(forKey: fn)
            // The editor can delete any listed frame, not just the displayed
            // one; only refresh what's on screen when they are the same frame.
            if isDisplayedFrame(fn) {
                updateCurrentFrameStrokes(forTime: frameTime)
                updateCurrentFrameText(forTime: frameTime)
            }
            AppLogger.video.info("Deleted annotation at frame#=\(fn)")
        } catch {
            AppLogger.video.error("Failed to delete annotation: \(error.localizedDescription)")
        }
    }

    func updateCurrentFrameStrokes(forTime time: Double) {
        let fn = frameNumber(forTime: time)
        if let pending = pendingStrokesByFrameNumber[fn] {
            currentFrameStrokes = pending.strokes
            AppLogger.video.debug("Loaded pending strokes for frame#=\(fn) (time=\(time))")
        } else if let annotation = annotations[fn] {
            if let data = annotation.strokesJSON.data(using: .utf8),
               let strokes = try? JSONDecoder().decode([StrokeData].self, from: data) {
                currentFrameStrokes = strokes
                AppLogger.video.debug("Loaded strokes for frame#=\(fn) (time=\(time))")
            } else {
                currentFrameStrokes = []
                AppLogger.video.warning("Failed to decode strokes for frame#=\(fn)")
            }
        } else if !currentFrameStrokes.isEmpty {
            // Skip the no-op write: every frame without an annotation would
            // otherwise invalidate the views observing this state.
            currentFrameStrokes = []
        }
    }

    func snapToFrame(time: Double, frameRate: Double) -> Double {
        AnnotationCoordinateHelper.snapToFrame(time: time, frameRate: frameRate)
    }

    func setFrameRate(_ frameRate: Double) {
        currentFrameRate = frameRate
    }

    /// Loads the content of the frame containing `time`. A no-op when that frame
    /// is already the displayed one, so repeated time-observer ticks on a single
    /// frame don't churn observable state.
    func syncCurrentFrameContent(forTime time: Double, frameRate: Double? = nil) {
        if let frameRate, frameRate > 0 {
            currentFrameRate = frameRate
        }
        let fn = frameNumber(forTime: time)
        guard fn != currentFrameNumber else { return }
        currentFrameNumber = fn
        updateCurrentFrameStrokes(forTime: time)
        updateCurrentFrameText(forTime: time)
    }

    // MARK: - Playback Coupling
    //
    // Shared between the grid tile and the fullscreen player so the annotation
    // frame logic lives in one place. Keep these here rather than duplicating
    // the pause/sync/seek dance in each view.

    /// Load the annotation of the frame the player is parked on, without
    /// seeking — used when entering and leaving pencil mode. No seek: the app
    /// frame rate doesn't exactly match the video's, so seeking would nudge the
    /// player to a neighbouring frame whose key has no annotation and clear the
    /// drawing. Reads the player's exact time: the published one is refreshed
    /// only every half second, so right after a pause it can still name a
    /// frame several frames earlier.
    func loadCurrentFrame(of player: VideoPlayerState) {
        syncCurrentFrameContent(forTime: player.exactCurrentTime, frameRate: Double(player.videoFrameRate))
    }

    /// Refresh current-frame content from the timeline time-observer, but only
    /// when NOT actively annotating. While annotating the user is parked on one
    /// frame; the observer can report a sub-frame/neighbouring time that maps to
    /// a different frame key with no annotation and would wipe the in-progress
    /// drawing.
    func syncFromTimelineIfNeeded(of player: VideoPlayerState) {
        guard !isAnnotationMode else { return }
        syncCurrentFrameContent(forTime: player.currentTime, frameRate: Double(player.videoFrameRate))
    }

    /// Re-sync after an explicit seek (scrubbing, frame stepping, jumping to a
    /// marked frame). Unlike the timeline observer this is deliberate
    /// navigation, so it applies in annotation mode too: the frame really did
    /// change and the previous frame's drawing must not follow the user there.
    /// The seek target is used rather than `player.currentTime` because the
    /// observer can report a sub-frame time that maps to a neighbouring frame.
    func syncFromSeek(_ marker: VideoPlayerState.SeekMarker, of player: VideoPlayerState) {
        syncCurrentFrameContent(forTime: marker.targetTime, frameRate: Double(player.videoFrameRate))
    }

    /// Snap to the current frame ± delta (integer frame numbers avoid float
    /// drift), load that frame's annotation, and seek the player there.
    func stepFrame(by delta: Int, of player: VideoPlayerState) {
        let frameRate = Double(player.videoFrameRate)
        guard frameRate > 0 else { return }
        let currentFrameNumber = (player.currentTime * frameRate).rounded()
        let targetTime = (currentFrameNumber + Double(delta)) / frameRate
        let clamped = max(0, min(targetTime, player.duration))
        syncCurrentFrameContent(forTime: clamped, frameRate: frameRate)
        player.seek(to: clamped)
    }

    /// Load the annotation for an explicit frame time and seek the player there
    /// (used when tapping an annotated frame in the editor).
    func seekToFrame(time: Double, of player: VideoPlayerState) {
        syncCurrentFrameContent(forTime: time, frameRate: Double(player.videoFrameRate))
        player.seek(to: time)
    }
}
