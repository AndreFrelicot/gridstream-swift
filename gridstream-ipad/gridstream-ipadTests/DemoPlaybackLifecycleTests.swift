import AVFoundation
import CoreVideo
import XCTest
@testable import gridstream_ipad

@MainActor
final class DemoPlaybackLifecycleTests: XCTestCase {
    func testLocalPlaybackSurvivesRepeatedSuspensionsWithoutInterruptionEnd() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("demo-lifecycle.mp4")
        try await writeTestClip(to: url)

        let state = VideoPlayerState(activateAudioSession: {})
        defer { state.releasePlayerResources() }
        state.setupPlayer(url: url, autoplay: false)
        let ready = await state.waitUntilReadyToPlay(timeout: 10)
        XCTAssertTrue(ready)
        guard ready else { return }
        XCTAssertTrue(state.currentAsset is AVURLAsset)
        XCTAssertEqual((state.currentAsset as? AVURLAsset)?.url, url)

        state.play()
        var advanced = try await waitForPlayback(state, beyond: 0.2)
        XCTAssertTrue(advanced, "The generated clip must actually play before testing suspension")
        guard advanced else { return }

        for cycle in 0..<3 {
            let position = try XCTUnwrap(state.player).currentTime().seconds
            state.handleAppWillResignActive()
            state.handleAudioInterruption(.began, shouldResume: false)
            XCTAssertFalse(state.isPlaying)
            try await Task.sleep(for: .milliseconds(100))
            state.handleAppDidBecomeActive()

            XCTAssertFalse(state.isAudioInterrupted)
            XCTAssertTrue(state.wantsToPlay)
            advanced = try await waitForPlayback(state, beyond: position + 0.2)
            XCTAssertTrue(advanced, "Playback did not advance after suspension \(cycle + 1)")
            guard advanced else { return }
            XCTAssertNil(state.error)
        }

        state.pause()
        let pausedPosition = try XCTUnwrap(state.player).currentTime().seconds
        state.handleAppWillResignActive()
        state.handleAudioInterruption(.began, shouldResume: false)
        state.handleAppDidBecomeActive()
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertFalse(state.wantsToPlay)
        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(try XCTUnwrap(state.player).rate, 0)
        XCTAssertEqual(try XCTUnwrap(state.player).currentTime().seconds, pausedPosition, accuracy: 0.08)

        state.play()
        advanced = try await waitForPlayback(state, beyond: pausedPosition + 0.2)
        XCTAssertTrue(advanced, "An explicit Play must still work after a paused foreground return")
    }

    private func waitForPlayback(_ state: VideoPlayerState, beyond position: Double) async throws -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let player = state.player,
               player.currentTime().seconds > position,
               player.timeControlStatus == .playing {
                return true
            }
            if state.error != nil { return false }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private func writeTestClip(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ])
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { throw ClipError.writerFailed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ClipError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer)
        guard result == kCVReturnSuccess, let pixelBuffer else { throw ClipError.pixelBufferUnavailable }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let bytes = CVPixelBufferGetBaseAddress(pixelBuffer) {
            bytes.initializeMemory(as: UInt8.self, repeating: 0, count: CVPixelBufferGetBytesPerRow(pixelBuffer) * 64)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let deadline = Date().addingTimeInterval(10)
        for frame in 0..<200 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? ClipError.writerFailed }
                guard Date() < deadline else { throw ClipError.timedOut }
                try await Task.sleep(for: .milliseconds(2))
            }
            guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)) else {
                throw writer.error ?? ClipError.writerFailed
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ClipError.writerFailed }
    }

    private enum ClipError: Error {
        case writerFailed
        case pixelBufferUnavailable
        case timedOut
    }
}
