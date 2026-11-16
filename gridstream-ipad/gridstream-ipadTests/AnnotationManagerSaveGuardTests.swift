//
//  AnnotationManagerSaveGuardTests.swift
//  gridstream-ipadTests
//

import GridStreamAPI
import XCTest
@testable import gridstream_ipad

@MainActor
private final class FakeAnnotationStore: AnnotationStore {
    struct Upsert {
        let fileId: String
        let frameTime: Double
        let text: String?
    }

    var annotationsByFile: [String: [AnnotationDTO]] = [:]
    var upserts: [Upsert] = []
    /// When set, the next upsert waits for `releaseUpsert()` before returning.
    var holdUpserts = false
    private var heldContinuation: CheckedContinuation<Void, Never>?

    func fetchAnnotations(forFileId fileId: String, serverURL: URL) async throws -> [AnnotationDTO] {
        annotationsByFile[fileId] ?? []
    }

    func upsertAnnotation(
        forFileId fileId: String,
        frameTime: Double,
        frameRate: Double,
        strokesJSON: String,
        text: String?,
        serverURL: URL
    ) async throws -> AnnotationDTO {
        upserts.append(Upsert(fileId: fileId, frameTime: frameTime, text: text))
        if holdUpserts {
            await withCheckedContinuation { heldContinuation = $0 }
        }
        return Self.annotation(fileId: fileId, frameTime: frameTime, frameRate: frameRate, text: text)
    }

    func deleteAnnotation(forFileId fileId: String, annotationId: String, serverURL: URL) async throws {}

    func releaseUpsert() {
        heldContinuation?.resume()
        heldContinuation = nil
    }

    var hasHeldUpsert: Bool { heldContinuation != nil }

    static func annotation(fileId: String, frameTime: Double, frameRate: Double, text: String?) -> AnnotationDTO {
        AnnotationDTO(
            id: UUID(),
            videoFileId: fileId,
            frameTime: frameTime,
            frameRate: frameRate,
            strokesJSON: "[]",
            text: text,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

@MainActor
final class AnnotationManagerSaveGuardTests: XCTestCase {
    private let server = URL(string: "http://localhost:8080")!
    private let stroke = StrokeData(color: "#FF0000", width: 4, opacity: 1, points: [
        StrokePoint(x: 0.1, y: 0.1, pressure: 1),
        StrokePoint(x: 0.2, y: 0.2, pressure: 1)
    ])

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    func testStrokesDrawnBeforeAVideoSwitchAreSavedToTheOriginalVideo() async throws {
        let store = FakeAnnotationStore()
        store.annotationsByFile["A"] = [FakeAnnotationStore.annotation(fileId: "A", frameTime: 1, frameRate: 25, text: "keep me")]
        let manager = AnnotationManager(store: store)
        await manager.loadAnnotations(forFileId: "A", serverURL: server)
        let target = try XCTUnwrap(manager.target(frameRate: 25))

        // The user switches to B before the debounced save fires
        await manager.loadAnnotations(forFileId: "B", serverURL: server)
        await manager.saveAnnotation(frameTime: 1, strokes: [stroke], target: target)

        XCTAssertEqual(store.upserts.map(\.fileId), ["A"])
        XCTAssertEqual(store.upserts.first?.text, "keep me", "The original video's text survives the stroke save")
        XCTAssertTrue(manager.annotations.isEmpty, "B's annotations are untouched")
        XCTAssertTrue(manager.currentFrameStrokes.isEmpty, "B's displayed frame is untouched")
    }

    func testSaveCompletingAfterAVideoSwitchDoesNotLandInTheNewVideo() async throws {
        let store = FakeAnnotationStore()
        store.holdUpserts = true
        let manager = AnnotationManager(store: store)
        await manager.loadAnnotations(forFileId: "A", serverURL: server)
        let target = try XCTUnwrap(manager.target(frameRate: 25))

        let save = Task { await manager.saveAnnotation(frameTime: 2, strokes: [stroke], target: target) }
        await waitUntil { store.hasHeldUpsert }
        store.holdUpserts = false
        await manager.loadAnnotations(forFileId: "B", serverURL: server)
        store.releaseUpsert()
        await save.value

        XCTAssertEqual(store.upserts.map(\.fileId), ["A"])
        XCTAssertTrue(manager.annotations.isEmpty, "A's annotation must not be keyed into B's map")
    }

    func testSaveOnTheLoadedVideoUpdatesState() async throws {
        let store = FakeAnnotationStore()
        let manager = AnnotationManager(store: store)
        await manager.loadAnnotations(forFileId: "A", serverURL: server)
        let target = try XCTUnwrap(manager.target(frameRate: 25))

        await manager.saveAnnotation(frameTime: 2, strokes: [stroke], target: target)

        XCTAssertEqual(store.upserts.map(\.fileId), ["A"])
        XCTAssertEqual(manager.annotations.keys.sorted(), [50])
        XCTAssertEqual(manager.currentFrameStrokes.count, 1)
    }

    func testFrameReloadedWhileItsSaveIsInFlightShowsTheNewStrokes() async throws {
        // Frame 25 at 25 fps already has a drawing on the server.
        let strokesJSON = String(decoding: try JSONEncoder().encode([stroke]), as: UTF8.self)
        let store = FakeAnnotationStore()
        store.annotationsByFile["A"] = [AnnotationDTO(
            id: UUID(), videoFileId: "A", frameTime: 1, frameRate: 25,
            strokesJSON: strokesJSON, text: nil, createdAt: Date(), updatedAt: Date()
        )]
        let manager = AnnotationManager(store: store)
        await manager.loadAnnotations(forFileId: "A", serverURL: server)
        manager.syncCurrentFrameContent(forTime: 1, frameRate: 25)
        XCTAssertEqual(manager.currentFrameStrokes.count, 1)
        let target = try XCTUnwrap(manager.target(frameRate: 25))

        // The user erases it; the save is still on its way when the frame
        // is loaded again (leaving pencil mode re-syncs it).
        store.holdUpserts = true
        let save = Task { await manager.saveAnnotation(frameTime: 1, strokes: [], target: target) }
        await waitUntil { store.hasHeldUpsert }
        manager.syncCurrentFrameContent(forTime: 2, frameRate: 25)
        manager.syncCurrentFrameContent(forTime: 1, frameRate: 25)
        XCTAssertTrue(manager.currentFrameStrokes.isEmpty, "The erased drawing must not come back")

        store.releaseUpsert()
        await save.value
        manager.syncCurrentFrameContent(forTime: 2, frameRate: 25)
        manager.syncCurrentFrameContent(forTime: 1, frameRate: 25)
        XCTAssertTrue(manager.currentFrameStrokes.isEmpty)
    }

    func testDisplayedFrameTimeIsTheLoadedFrame() async {
        let manager = AnnotationManager(store: FakeAnnotationStore())
        await manager.loadAnnotations(forFileId: "A", serverURL: server)
        XCTAssertNil(manager.displayedFrameTime)

        // 1.01 s falls in frame 25 at 25 fps, which starts at 1 s.
        manager.syncCurrentFrameContent(forTime: 1.01, frameRate: 25)
        XCTAssertEqual(try XCTUnwrap(manager.displayedFrameTime), 1, accuracy: 0.0001)
    }

    func testTextSaveCompletingAfterAVideoSwitchDoesNotLandInTheNewVideo() async {
        let store = FakeAnnotationStore()
        store.holdUpserts = true
        let manager = AnnotationManager(store: store)
        await manager.loadAnnotations(forFileId: "A", serverURL: server)

        await manager.saveTextAnnotation(text: "note", frameTime: 1, frameRate: 25)
        // The text save is debounced by one second before it reaches the store
        for _ in 0..<40 where !store.hasHeldUpsert {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(store.hasHeldUpsert)
        store.holdUpserts = false
        await manager.loadAnnotations(forFileId: "B", serverURL: server)
        store.releaseUpsert()
        await waitUntil { false }

        XCTAssertEqual(store.upserts.map(\.fileId), ["A"])
        XCTAssertTrue(manager.annotations.isEmpty)
    }

    // MARK: - Pencil mode

    /// A manager with a drawing on frame 0 of video A, and a player parked
    /// there (no item loaded: time 0 at the default 24 fps).
    private func managerWithADrawingOnFrameZero() async throws -> (AnnotationManager, VideoPlayerState) {
        let strokesJSON = String(decoding: try JSONEncoder().encode([stroke]), as: UTF8.self)
        let store = FakeAnnotationStore()
        store.annotationsByFile["A"] = [AnnotationDTO(
            id: UUID(), videoFileId: "A", frameTime: 0, frameRate: 24,
            strokesJSON: strokesJSON, text: nil, createdAt: Date(), updatedAt: Date()
        )]
        let manager = AnnotationManager(store: store)
        await manager.loadAnnotations(forFileId: "A", serverURL: server)
        return (manager, VideoPlayerState())
    }

    func testEnteringPencilModeLoadsTheDrawingOfThePlayersFrame() async throws {
        let (manager, player) = try await managerWithADrawingOnFrameZero()
        XCTAssertFalse(manager.isAnnotationMode)

        manager.toggleAnnotationMode(of: player)
        XCTAssertTrue(manager.isAnnotationMode)
        XCTAssertEqual(manager.currentFrameStrokes.count, 1, "The canvas opens with the frame's drawing")

        manager.toggleAnnotationMode(of: player)
        XCTAssertFalse(manager.isAnnotationMode)
    }

    func testResumingPlaybackLeavesPencilMode() async throws {
        let (manager, player) = try await managerWithADrawingOnFrameZero()
        manager.toggleAnnotationMode(of: player)

        manager.exitAnnotationModeForPlayback(of: player)
        XCTAssertFalse(manager.isAnnotationMode)
    }
}
